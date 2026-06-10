import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Single source of truth for where each placed meld sits inside a seat's
/// meld lane.
///
/// Both the lane renderer ([SeatMeldLane]) and the flight geometry
/// ([resolveTableMeldSlot]) read from this module so a meld animates to the
/// exact slot it will rest in, instead of the lane drawing melds in one
/// layout while the flight aims at a separate, index-blind guess (the old
/// "everything flies to the lane centre" behaviour).
///
/// The maths is pure — no widget state — so it can be unit-tested and shared.
abstract final class SeatMeldArrangement {
  /// Padding the rotated side-meld body adds around itself
  /// (`_TableMeldStack.orientedBody`).
  static double orientedPad(bool compact) => compact ? 8.0 : 10.0;

  /// Inter-card overlap factor inside one meld stack. Mirrors
  /// `_TableMeldStack`'s resting `horizontalGap`.
  static double cardGapFactor(bool sideFacing) => sideFacing ? 0.68 : 0.43;

  /// Resting on-screen footprint of one meld stack of [cardCount] cards.
  ///
  /// For flat lanes (north/south, `sideFacing == false`) this is the fanned
  /// card row: `width = cardW + (n-1)*gap`, `height = cardH`.
  ///
  /// For side lanes (east/west, `sideFacing == true`) the body is rotated a
  /// quarter turn and wrapped in a padded box, so the screen footprint is
  /// `(cardH + pad) x (cardW + (n-1)*gap + pad)`.
  static Size footprint({
    required Size cardSize,
    required int cardCount,
    required bool compact,
    required bool sideFacing,
  }) {
    final n = math.max(1, cardCount);
    final gap = cardSize.width * cardGapFactor(sideFacing);
    final bodyWidth = cardSize.width + (n - 1) * gap;
    final bodyHeight = cardSize.height;
    if (!sideFacing) {
      return Size(bodyWidth, bodyHeight);
    }
    final pad = orientedPad(compact);
    return Size(bodyHeight + pad, bodyWidth + pad);
  }

  /// Arranges the side (east/west) melds into centred columns that grow
  /// toward the table centre.
  ///
  /// Melds fill a column top-to-bottom; when the next meld would overflow the
  /// lane height a new column starts toward the centre (capped by how many
  /// columns fit in [laneSize] width). The column block hugs the seat's rail
  /// edge — [growFromRail] right for east, left for west — so unused space is
  /// the gap toward the table centre that the next column fills. Each column
  /// is centred vertically; each meld is centred within its column width.
  static SeatMeldLayout side({
    required Size laneSize,
    required List<Size> footprints,
    required double meldGap,
    required double columnGap,
    required bool growFromRailRight,
  }) {
    if (footprints.isEmpty || laneSize.height <= 0) {
      return SeatMeldLayout(slots: const [], contentSize: laneSize);
    }
    // Side footprints all share the same width (cardH + pad), so a single
    // representative column width yields a stable column count.
    final colWidth = footprints
        .map((f) => f.width)
        .reduce(math.max);
    final maxColumns = math.max(
      1,
      ((laneSize.width + columnGap) / (colWidth + columnGap)).floor(),
    );

    // Greedy column-major fill with a height cap.
    final columns = <List<int>>[];
    var col = <int>[];
    var colHeight = 0.0;
    for (var i = 0; i < footprints.length; i++) {
      final h = footprints[i].height;
      final add = col.isEmpty ? h : meldGap + h;
      final wouldOverflow =
          col.isNotEmpty && colHeight + add > laneSize.height;
      final canOpenColumn = columns.length + 1 < maxColumns;
      if (wouldOverflow && canOpenColumn) {
        columns.add(col);
        col = <int>[i];
        colHeight = h;
      } else {
        col.add(i);
        colHeight += add;
      }
    }
    if (col.isNotEmpty) {
      columns.add(col);
    }

    final slots = List<Rect>.filled(footprints.length, Rect.zero);
    final colWidths = [
      for (final c in columns)
        c.map((i) => footprints[i].width).reduce(math.max),
    ];
    final blockWidth =
        colWidths.fold<double>(0, (s, w) => s + w) +
        math.max(0, columns.length - 1) * columnGap;

    var maxColHeight = 0.0;
    // Cross-axis cursor: distance of the current column's outer edge from the
    // rail. The outer column hugs the rail; later columns step toward centre.
    var crossCursor = 0.0;
    for (var k = 0; k < columns.length; k++) {
      final c = columns[k];
      final cw = colWidths[k];
      final columnHeight =
          c.map((i) => footprints[i].height).fold<double>(0, (s, h) => s + h) +
          math.max(0, c.length - 1) * meldGap;
      maxColHeight = math.max(maxColHeight, columnHeight);
      final left = growFromRailRight
          ? laneSize.width - crossCursor - cw
          : crossCursor;
      var y = math.max(0.0, (laneSize.height - columnHeight) / 2);
      for (final i in c) {
        final f = footprints[i];
        slots[i] = Rect.fromLTWH(
          left + (cw - f.width) / 2,
          y,
          f.width,
          f.height,
        );
        y += f.height + meldGap;
      }
      crossCursor += cw + columnGap;
    }

    return SeatMeldLayout(
      slots: slots,
      contentSize: Size(
        math.max(laneSize.width, blockWidth),
        math.max(laneSize.height, maxColHeight),
      ),
    );
  }

  /// Arranges flat (north/south) melds into centred horizontal rows that wrap
  /// when they overflow the lane width. The block anchors to the bottom of
  /// the lane for the south seat ([anchorBottom]) and the top otherwise,
  /// matching the lane's `Wrap` so the flight lands where the meld rests.
  static SeatMeldLayout flat({
    required Size laneSize,
    required List<Size> footprints,
    required double meldGap,
    required double rowGap,
    required bool anchorBottom,
  }) {
    if (footprints.isEmpty || laneSize.width <= 0) {
      return SeatMeldLayout(slots: const [], contentSize: laneSize);
    }
    // Greedy row-major fill with a width cap.
    final rows = <List<int>>[];
    var row = <int>[];
    var rowWidth = 0.0;
    for (var i = 0; i < footprints.length; i++) {
      final w = footprints[i].width;
      final add = row.isEmpty ? w : meldGap + w;
      if (row.isNotEmpty && rowWidth + add > laneSize.width) {
        rows.add(row);
        row = <int>[i];
        rowWidth = w;
      } else {
        row.add(i);
        rowWidth += add;
      }
    }
    if (row.isNotEmpty) {
      rows.add(row);
    }

    final rowHeights = [
      for (final r in rows) r.map((i) => footprints[i].height).reduce(math.max),
    ];
    final blockHeight =
        rowHeights.fold<double>(0, (s, h) => s + h) +
        math.max(0, rows.length - 1) * rowGap;

    final slots = List<Rect>.filled(footprints.length, Rect.zero);
    // South anchors the block to the bottom of the lane (its expand headroom
    // sits above); north (and any other flat lane) centres vertically to
    // match the lane's `Alignment.center` Wrap.
    var y = anchorBottom
        ? math.max(0.0, laneSize.height - blockHeight)
        : math.max(0.0, (laneSize.height - blockHeight) / 2);
    for (var k = 0; k < rows.length; k++) {
      final r = rows[k];
      final rh = rowHeights[k];
      final widths = r.map((i) => footprints[i].width).fold<double>(
        0,
        (s, w) => s + w,
      );
      final rowSpan = widths + math.max(0, r.length - 1) * meldGap;
      var x = math.max(0.0, (laneSize.width - rowSpan) / 2);
      for (final i in r) {
        final f = footprints[i];
        slots[i] = Rect.fromLTWH(x, y + (rh - f.height) / 2, f.width, f.height);
        x += f.width + meldGap;
      }
      y += rh + rowGap;
    }

    return SeatMeldLayout(
      slots: slots,
      contentSize: Size(
        laneSize.width,
        math.max(laneSize.height, blockHeight),
      ),
    );
  }
}

/// Resolved positions for one seat's melds within its lane's local space.
@immutable
class SeatMeldLayout {
  /// Creates a meld layout.
  const SeatMeldLayout({required this.slots, required this.contentSize});

  /// Local rect of each meld, in placement order. Empty when there are no
  /// melds.
  final List<Rect> slots;

  /// Total content bounds; at least the lane size, larger only when the melds
  /// overflow (the rare degenerate case the lane scrolls).
  final Size contentSize;

  /// Centre of the meld slot at [index], or the lane-centre fallback when the
  /// index is out of range.
  Offset centerOf(int index, Size laneSize) {
    if (index < 0 || index >= slots.length) {
      return Offset(laneSize.width / 2, laneSize.height / 2);
    }
    return slots[index].center;
  }
}
