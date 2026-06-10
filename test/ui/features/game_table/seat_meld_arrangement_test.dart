import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/ui/features/game_table/seat_meld_arrangement.dart';

void main() {
  group('footprint', () {
    test('flat meld is a fanned row of card height', () {
      final f = SeatMeldArrangement.footprint(
        cardSize: const Size(38, 54),
        cardCount: 3,
        compact: false,
        sideFacing: false,
      );
      // width = 38 + 2 * (38 * 0.43); height = 54.
      expect(f.width, closeTo(38 + 2 * 38 * 0.43, 0.001));
      expect(f.height, 54);
    });

    test('side meld is rotated: width is card height + pad, height grows', () {
      final f = SeatMeldArrangement.footprint(
        cardSize: const Size(34, 48),
        cardCount: 4,
        compact: false,
        sideFacing: true,
      );
      // rotated: width = cardH(48) + pad(10); height = cardW + 3*gap + pad.
      expect(f.width, closeTo(48 + 10, 0.001));
      expect(f.height, closeTo(34 + 3 * 34 * 0.68 + 10, 0.001));
    });
  });

  group('side arrangement', () {
    final footprints = List<Size>.filled(3, const Size(58, 90));

    test('few melds stay a single centred column', () {
      final layout = SeatMeldArrangement.side(
        laneSize: const Size(140, 460),
        footprints: footprints,
        meldGap: 12,
        columnGap: 10,
        growFromRailRight: false,
      );
      // 3 * 90 + 2 * 12 = 294 < 460 -> one column.
      final lefts = layout.slots.map((r) => r.left).toSet();
      expect(lefts.length, 1, reason: 'all melds share one column');
      // Column hugs the left rail (west).
      expect(layout.slots.first.left, 0);
      // Vertically centred: top gap == bottom gap.
      final topGap = layout.slots.first.top;
      final bottomGap = 460 - layout.slots.last.bottom;
      expect(topGap, closeTo(bottomGap, 0.001));
    });

    test('overflowing melds open a second column toward centre (west)', () {
      // 6 melds of height 90 + gaps can't fit one 460-tall column.
      final many = List<Size>.filled(6, const Size(58, 90));
      final layout = SeatMeldArrangement.side(
        laneSize: const Size(140, 460),
        footprints: many,
        meldGap: 12,
        columnGap: 10,
        growFromRailRight: false,
      );
      final lefts = layout.slots.map((r) => r.left).toList();
      // First column hugs the rail at x=0; a later meld sits in a column
      // stepped toward the centre (larger x).
      expect(lefts.first, 0);
      expect(lefts.any((x) => x > 0), isTrue);
    });

    test('east mirrors west: outer column hugs the right rail edge', () {
      final layout = SeatMeldArrangement.side(
        laneSize: const Size(140, 460),
        footprints: footprints,
        meldGap: 12,
        columnGap: 10,
        growFromRailRight: true,
      );
      // Single column hugs the right edge: right == laneWidth.
      expect(layout.slots.first.right, closeTo(140, 0.001));
    });
  });

  group('flat arrangement', () {
    test('single row is centred horizontally', () {
      final footprints = [
        const Size(70, 54),
        const Size(70, 54),
      ];
      final layout = SeatMeldArrangement.flat(
        laneSize: const Size(400, 70),
        footprints: footprints,
        meldGap: 10,
        rowGap: 12,
        anchorBottom: false,
      );
      final span = 70 + 10 + 70;
      expect(layout.slots.first.left, closeTo((400 - span) / 2, 0.001));
    });

    test('south anchors the block to the bottom of the lane', () {
      final layout = SeatMeldArrangement.flat(
        laneSize: const Size(400, 70),
        footprints: [const Size(70, 54)],
        meldGap: 10,
        rowGap: 12,
        anchorBottom: true,
      );
      expect(layout.slots.first.bottom, closeTo(70, 0.001));
    });
  });
}
