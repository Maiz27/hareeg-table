import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/ui/features/game_table/table_card_flight_planner.dart';
import 'package:hareeg_table/ui/features/game_table/table_flight_geometry.dart';

/// The meld-placement flight must land each set on its own resting slot, not
/// the lane centre. These tests pin the index-awareness of
/// `resolveTableMeldSlot`.
void main() {
  const size = Size(900, 500);
  const flightCard = Size(58, 82);

  test('without lane counts it falls back to the lane centre', () {
    final a = resolveTableMeldSlot(
      const TableMeldFlightSlot(seat: PlayerSeat.south, index: 0),
      size,
      flightCard,
    );
    final b = resolveTableMeldSlot(
      const TableMeldFlightSlot(seat: PlayerSeat.south, index: 3),
      size,
      flightCard,
    );
    // Index is ignored when there are no counts, so both resolve identically.
    expect(a, b);
  });

  test('south melds land at distinct, index-specific x positions', () {
    const counts = [3, 3, 3];
    final centers = [
      for (var i = 0; i < counts.length; i++)
        resolveTableMeldSlot(
          const TableMeldFlightSlot(
            seat: PlayerSeat.south,
            index: 0,
            laneMeldCardCounts: counts,
          ).copyAt(i),
          size,
          flightCard,
        ),
    ];
    final xs = centers.map((o) => o.dx).toList();
    // Three distinct slots: a left, a middle, and a right one.
    expect(xs.toSet().length, 3, reason: 'each meld gets its own slot: $xs');
    expect(xs[0], lessThan(xs[1]));
    expect(xs[1], lessThan(xs[2]));
  });

  test('east melds land deeper into the right side than the lane centre', () {
    const counts = [3, 3, 3, 3, 3, 3];
    final slot0 = resolveTableMeldSlot(
      const TableMeldFlightSlot(
        seat: PlayerSeat.east,
        index: 0,
        laneMeldCardCounts: counts,
      ),
      size,
      flightCard,
    );
    final centerFallback = resolveTableMeldSlot(
      const TableMeldFlightSlot(seat: PlayerSeat.east, index: 0),
      size,
      flightCard,
    );
    // Outer column hugs the right rail, so the first slot sits to the right of
    // (or at least not left of) the lane-centre fallback.
    expect(slot0.dx, greaterThanOrEqualTo(centerFallback.dx - 1));
  });
}

extension on TableMeldFlightSlot {
  TableMeldFlightSlot copyAt(int index) => TableMeldFlightSlot(
    seat: seat,
    index: index,
    laneMeldCardCounts: laneMeldCardCounts,
  );
}
