import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/cover_rules.dart';
import 'package:hareeg_table/ui/features/game_table/table_meld_drop_target.dart';

void main() {
  group('TableMeldDropTargetPlanner', () {
    test('targets low and high ends on horizontal melds', () {
      final low = TableMeldDropTargetPlanner.targetForLocalPosition(
        owner: PlayerSeat.east,
        meldIndex: 2,
        cardCount: 3,
        localPosition: const Offset(10, 20),
        bounds: const Size(100, 40),
        vertical: false,
        quarterTurns: 0,
      );
      final middle = TableMeldDropTargetPlanner.targetForLocalPosition(
        owner: PlayerSeat.east,
        meldIndex: 2,
        cardCount: 3,
        localPosition: const Offset(50, 20),
        bounds: const Size(100, 40),
        vertical: false,
        quarterTurns: 0,
      );
      final high = TableMeldDropTargetPlanner.targetForLocalPosition(
        owner: PlayerSeat.east,
        meldIndex: 2,
        cardCount: 3,
        localPosition: const Offset(90, 20),
        bounds: const Size(100, 40),
        vertical: false,
        quarterTurns: 0,
      );

      expect(low.owner, PlayerSeat.east);
      expect(low.meldIndex, 2);
      expect(low.coverPlacement, CoverPlacement.lowEnd);
      expect(middle.coverPlacement, isNull);
      expect(high.coverPlacement, CoverPlacement.highEnd);
    });

    test('uses the vertical axis for side-facing melds', () {
      final target = TableMeldDropTargetPlanner.targetForLocalPosition(
        owner: PlayerSeat.west,
        meldIndex: 1,
        cardCount: 4,
        localPosition: const Offset(10, 90),
        bounds: const Size(40, 100),
        vertical: false,
        quarterTurns: 1,
      );

      expect(target.coverPlacement, CoverPlacement.highEnd);
      expect(target.targetsCoverEdge, isTrue);
    });

    test('does not target cover edges for undersized melds', () {
      final target = TableMeldDropTargetPlanner.targetForLocalPosition(
        owner: PlayerSeat.south,
        meldIndex: 0,
        cardCount: 2,
        localPosition: const Offset(0, 0),
        bounds: const Size(100, 40),
        vertical: false,
        quarterTurns: 0,
      );

      expect(target.coverPlacement, isNull);
      expect(target.targetsCoverEdge, isFalse);
    });
  });
}
