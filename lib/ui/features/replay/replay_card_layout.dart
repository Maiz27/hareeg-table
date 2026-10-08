import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' show immutable;

import '../game_table/table_flight_geometry.dart'
    show resolveStockPileRect, stockCardSize;
import '../game_table/widgets/coach_overlay.dart';
import '../game_table/widgets/table_hud_capsule.dart';

/// The fixed measurements of the replay card (design contract 7.6).
///
/// Shared by the placement below and by the card widget, so the room the
/// placement reserves is the room the card lays itself out in.
abstract final class ReplayCardMetrics {
  /// Every transport control is a 44 dp square target: the contract's floor
  /// (section 5), and the reason the row has a fixed width.
  static const double tapTarget = 44;

  /// Transport actions in the one row: start, previous round, step back, step
  /// forward, next round, end.
  static const int transportCount = 6;

  /// Space between the transport row and the card's side edges. The visible
  /// chrome sits a further [chromeInset] inside each target.
  static const double rowPadding = 2;

  /// Inset between a 44 dp target and the round chrome painted inside it.
  static const double chromeInset = 3;

  /// Horizontal padding of the text lines.
  static const double textPadding = 12;

  /// Space above the card's first line.
  static const double padTop = 8;

  /// Space below the transport row (the chrome inset adds the rest).
  static const double padBottom = 4;

  /// Height of the timeline scrubber in the stacked arrangement.
  static const double sliderHeight = 36;

  /// The slider never gets thinner than this, even beside a tall overline.
  static const double minSliderHeight = 28;

  /// Space between the overline and the line under it.
  static const double lineGap = 2;

  /// Narrowest scrubber the band arrangement accepts in exchange for keeping
  /// clear of the far side seat's meld lane.
  static const double bandMinSliderWidth = 140;

  /// The smallest analysis section worth showing. Below this the section is
  /// collapsed rather than squeezed into a sliver.
  static const double minAnalysisHeight = 80;

  /// Width of the one transport row, edge padding included.
  static const double rowWidth = tapTarget * transportCount + rowPadding * 2;

  /// Narrowest card the stacked (corner) arrangement accepts.
  static const double cornerMinWidth = rowWidth;

  /// Widest band card: the row, its scrubber and a little air.
  static const double bandMaxWidth = rowWidth + 220;

  /// Overline style metrics: 11 dp at a 1.2 line height.
  static double overlineHeight(TextScaler scaler) => scaler.scale(11) * 1.2;

  /// One narration line: 14 dp at a 1.45 line height.
  static double narrationLineHeight(TextScaler scaler) =>
      scaler.scale(14) * 1.45;

  /// Height of the band arrangement's transport row: the 44 dp targets, or
  /// the overline over a usable scrubber if that is taller.
  static double bandRowHeight(TextScaler scaler) =>
      math.max(tapTarget, overlineHeight(scaler) + minSliderHeight);

  /// The stacked card with the least it may show at rest: the overline, one
  /// narration line, the scrubber and the transport row.
  static double cornerRestingMin(TextScaler scaler) =>
      padTop +
      overlineHeight(scaler) +
      lineGap +
      narrationLineHeight(scaler) +
      sliderHeight +
      tapTarget +
      padBottom;

  /// The band card with the least it may show: its transport row.
  static double bandRestingMin(TextScaler scaler) =>
      padBottom * 2 + bandRowHeight(scaler);
}

/// The protected and the preferably-clear surfaces of a live-shaped table,
/// projected from its size alone.
///
/// Coordinates are the playing surface's own (inside the rail), physical and
/// unmirrored — the table does not mirror (design contract 10).
///
/// **This restates `PhysicalTablePlayfield`'s layout arithmetic**, because the
/// card has to know where the seats will land before the table is laid out.
/// The restatement is guarded rather than trusted: `replay_layout_test`
/// measures the rendered plates, rails and hand at every contracted size and
/// fails if the card ever covers one of them.
@immutable
class ReplayTableZones {
  const ReplayTableZones._({
    required this.table,
    required this.compact,
    required this.westColumn,
    required this.eastColumn,
    required this.eastMeldLane,
    required this.northRail,
    required this.hand,
    required this.stock,
    required this.discard,
  });

  /// Projects the zones of a table laid out in [table].
  factory ReplayTableZones.project(Size table) {
    final w = table.width;
    final h = table.height;
    final compact = CoachOverlay.isCompactTable(table);

    final tableCard = stockCardSize(table);
    final handCard = compact ? const Size(36, 50) : const Size(48, 68);
    final opponentCard = compact ? const Size(26, 36) : const Size(32, 44);
    final sideRailWidth = compact ? 46.0 : 56.0;
    final controlWidth = compact ? 60.0 : 72.0;
    final edgeInset = (w * 0.026)
        .clamp(compact ? 14.0 : 20.0, compact ? 30.0 : 52.0)
        .toDouble();
    final topInset = (h * 0.032)
        .clamp(compact ? 8.0 : 12.0, compact ? 16.0 : 28.0)
        .toDouble();

    // The side columns hold each side seat's plate above its rail. Their
    // vertical extent is bounded by the rail's bottom, which sits clear of the
    // hand; the card never enters either column, so the column is reserved
    // whole rather than measured plate by plate.
    final sideVisible = compact ? 5 : 6;
    final sideRailHeight = opponentCard.height + (sideVisible - 1) * 16.0;
    final stockBottom = compact ? 6.0 : 10.0;
    final stockReservedHeight = tableCard.height + (compact ? 32 : 42);
    final sideRailMinTop = topInset + opponentCard.height + (compact ? 8 : 12);
    final sideRailMaxTop =
        h -
        stockBottom -
        stockReservedHeight -
        sideRailHeight -
        (compact ? 8.0 : 12.0);
    final sideRailTop = ((h - sideRailHeight) * 0.5)
        .clamp(sideRailMinTop, math.max(sideRailMinTop, sideRailMaxTop))
        .toDouble();
    final sideBottom = sideRailTop + sideRailHeight;

    // The north seat: its rail centred on the table, its cards' cue frame at
    // the most cards the rail ever shows, so the card does not move as the
    // north hand grows and shrinks. The plate sits beside the rail, inside the
    // same band.
    final northVisible = compact ? 9 : 12;
    final northStackWidth =
        opponentCard.width + (northVisible - 1) * opponentCard.width * 0.38;
    final northCueWidth = northStackWidth + (compact ? 18 : 24);
    final northRailHeight = opponentCard.height + (compact ? 16 : 20);

    // The side seats' meld lanes run the table's height beside each column.
    final sideMeldWidth =
        ((compact ? 40.0 : 48.0) + (compact ? 8 : 10)) * 2 +
        (compact ? 8 : 12) * 2;
    final sideMeldGap = compact ? 6.0 : 10.0;

    final bottomHandHeight = handCard.height + (compact ? 12 : 18);
    final handInset = math.max(
      controlWidth + edgeInset + (compact ? 10.0 : 16.0),
      compact ? 70.0 : 96.0,
    );
    final handBottom = h - (compact ? 0.0 : 2.0);

    return ReplayTableZones._(
      table: table,
      compact: compact,
      westColumn: Rect.fromLTRB(
        edgeInset,
        0,
        edgeInset + sideRailWidth,
        sideBottom,
      ),
      eastColumn: Rect.fromLTRB(
        w - edgeInset - sideRailWidth,
        0,
        w - edgeInset,
        sideBottom,
      ),
      eastMeldLane: Rect.fromLTRB(
        w - edgeInset - sideRailWidth - sideMeldGap - sideMeldWidth,
        0,
        w - edgeInset - sideRailWidth - sideMeldGap,
        h,
      ),
      northRail: Rect.fromLTWH(
        (w - northCueWidth) / 2,
        topInset,
        northCueWidth,
        northRailHeight,
      ),
      hand: Rect.fromLTRB(
        handInset,
        handBottom - bottomHandHeight,
        w - handInset,
        handBottom,
      ),
      stock: resolveStockPileRect(table),
      // The top card and the ghost of the one under it, centred in the
      // discard's drop zone and nudged by at most a few dp either way.
      discard: Rect.fromCenter(
        center: Offset(w / 2, h / 2),
        width: tableCard.width + 24,
        height: tableCard.height + 16,
      ),
    );
  }

  /// The box the table is laid out in.
  final Size table;

  /// Whether the table renders its compact sizes.
  final bool compact;

  /// West seat plate and rail column.
  final Rect westColumn;

  /// East seat plate and rail column.
  final Rect eastColumn;

  /// East seat meld lane — the far side's lane for a start-docked card in a
  /// left-to-right table, and (the table being symmetric) the same distance
  /// from the far edge in a right-to-left one.
  final Rect eastMeldLane;

  /// North seat rail (its cue frame at the fullest hand).
  final Rect northRail;

  /// The reviewer's own hand.
  final Rect hand;

  /// The stock pile.
  final Rect stock;

  /// The visible discard cards (not the discard's wider drop zone).
  final Rect discard;

  /// Surfaces the card may never cover (design contract 7.1 reserved zones,
  /// plus the reviewer's hand).
  List<Rect> get reserved => [westColumn, eastColumn, northRail, hand];

  /// The pot. The card keeps clear of it at rest wherever the table leaves
  /// room; only an opened analysis section may reach over it.
  List<Rect> get pot => [stock, discard];

  /// Clearance kept between the card and anything it docks against.
  double get gap => compact ? 4 : 6;
}

/// How the replay card is arranged.
enum ReplayCardArrangement {
  /// Docked in the top-start corner exactly where the live coach card docks:
  /// the position, the event line, the scrubber, then the transport row.
  corner,

  /// Too little room beside the north seat for the transport row, so the card
  /// sits in the free band between the north rail and the pot, still
  /// start-docked: the transport row carries the position and the scrubber
  /// between its two halves, with the event line under it.
  band,

  /// A portrait body: the card is docked full width under the table.
  portrait,
}

/// Where the replay card goes and how much room it has.
@immutable
class ReplayCardPlacement {
  /// Creates a placement.
  const ReplayCardPlacement({
    required this.arrangement,
    required this.left,
    required this.top,
    required this.width,
    required this.restingMaxHeight,
    required this.expandedMaxHeight,
    required this.capsule,
  });

  /// The arrangement to render.
  final ReplayCardArrangement arrangement;

  /// Physical left edge, in table coordinates.
  final double left;

  /// Top edge, in table coordinates.
  final double top;

  /// Card width.
  final double width;

  /// Tallest the card may be with analysis closed.
  final double restingMaxHeight;

  /// Tallest the card may be with analysis open.
  final double expandedMaxHeight;

  /// Where the HUD capsule sits, in table coordinates.
  final Rect capsule;

  /// The card's largest possible rectangle with analysis closed.
  Rect get restingBounds => Rect.fromLTWH(left, top, width, restingMaxHeight);

  /// The card's largest possible rectangle with analysis open.
  Rect get expandedBounds => Rect.fromLTWH(left, top, width, expandedMaxHeight);

  /// Places the card on a landscape table laid out in [table].
  ///
  /// [safeTop] is the system inset over the table's top edge, which both the
  /// capsule and the card stay below; [capsuleSegments] is the number of
  /// segments in the replay capsule.
  static ReplayCardPlacement resolve({
    required Size table,
    required TextDirection direction,
    required TextScaler textScaler,
    double safeTop = 0,
    int capsuleSegments = 3,
  }) {
    final zones = ReplayTableZones.project(table);
    final w = table.width;
    final gap = zones.gap;
    final rtl = direction == TextDirection.rtl;

    final metrics = TableHudMetrics.forViewport(w, floor: 44);
    final capsuleWidth = metrics.capsuleWidth(capsuleSegments);
    final capsuleTop = safeTop + metrics.edgeInset;
    final capsule = Rect.fromLTWH(
      rtl ? metrics.edgeInset : w - metrics.edgeInset - capsuleWidth,
      capsuleTop,
      capsuleWidth,
      metrics.buttonSize,
    );

    // The start inset is the coach card's own, and never inside the start
    // column whatever that rule gives. Every edge below is snapped inward to
    // whole pixels, so the card and the controls in it sit on the pixel grid.
    final start = math
        .max(CoachOverlay.dockedStartFor(table), zones.westColumn.right + gap)
        .ceilToDouble();

    Rect span(double left, double right, double top) =>
        Rect.fromLTRB(left, top, right, table.height);

    // Physical x-range of a start-docked card [width] wide.
    (double, double) xRange(double width) =>
        rtl ? (w - start - width, w - start) : (start, start + width);

    // The highest top edge among [blockers] that share the card's columns and
    // sit below [top], less the gap; the table's bottom when none does.
    double floorFor(Rect column, List<Rect> blockers) {
      var floor = table.height - gap;
      for (final blocker in blockers) {
        final overlaps =
            blocker.right > column.left && blocker.left < column.right;
        if (overlaps && blocker.bottom > column.top) {
          floor = math.min(floor, blocker.top - gap);
        }
      }
      return floor;
    }

    // Corner: the coach's own dock, stopping short of the north seat.
    final cornerTop = (safeTop + CoachOverlay.dockedTopFor(table))
        .ceilToDouble();
    // The table is symmetric about its centre line, so the room between the
    // start column and the north seat is the same on either side.
    final cornerWidth = math
        .min(CoachOverlay.maxDockedWidth, zones.northRail.left - gap - start)
        .floorToDouble();
    if (cornerWidth >= ReplayCardMetrics.cornerMinWidth) {
      final (left, right) = xRange(cornerWidth);
      final column = span(left, right, cornerTop);
      final restingFloor = floorFor(column, [...zones.pot, zones.hand]);
      final expandedFloor = floorFor(column, [zones.hand]);
      if (restingFloor - cornerTop >=
          ReplayCardMetrics.cornerRestingMin(textScaler)) {
        return ReplayCardPlacement(
          arrangement: ReplayCardArrangement.corner,
          left: left,
          top: cornerTop,
          width: cornerWidth,
          restingMaxHeight: restingFloor - cornerTop,
          expandedMaxHeight: expandedFloor - cornerTop,
          capsule: capsule,
        );
      }
    }

    // Band: under the north seat (and the capsule), between the side columns.
    // Kept short of the far side seat's meld lane where that still leaves a
    // usable scrubber; otherwise it runs up to the far column.
    final toLane = zones.eastMeldLane.left - gap - start;
    final bandWidth = math
        .min(
          ReplayCardMetrics.bandMaxWidth,
          toLane >=
                  ReplayCardMetrics.rowWidth +
                      ReplayCardMetrics.bandMinSliderWidth
              ? toLane
              : zones.eastColumn.left - gap - start,
        )
        .floorToDouble();
    final (left, right) = xRange(bandWidth);
    final underCapsule = capsule.left < right && capsule.right > left;
    final bandTop =
        (math.max(zones.northRail.bottom, underCapsule ? capsule.bottom : 0.0) +
                gap)
            .ceilToDouble();
    final column = span(left, right, bandTop);
    final expandedFloor = floorFor(column, [zones.hand]);
    var restingFloor = floorFor(column, [...zones.pot, zones.hand]);
    // The transport is never given up to keep the pot clear: where even the
    // bare row does not fit above it, the row reaches over it.
    if (restingFloor - bandTop < ReplayCardMetrics.bandRestingMin(textScaler)) {
      restingFloor = expandedFloor;
    }
    return ReplayCardPlacement(
      arrangement: ReplayCardArrangement.band,
      left: left,
      top: bandTop,
      width: bandWidth,
      restingMaxHeight: restingFloor - bandTop,
      expandedMaxHeight: expandedFloor - bandTop,
      capsule: capsule,
    );
  }
}
