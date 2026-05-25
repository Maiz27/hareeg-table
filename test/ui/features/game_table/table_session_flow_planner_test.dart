import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/ui/features/game_table/table_session_flow_planner.dart';

void main() {
  group('ClassicHareegTableSessionFlowPlanner', () {
    test('centralizes human input gating', () {
      expect(
        ClassicHareegTableSessionFlowPlanner.canAcceptHumanInput(
          isCpuRunning: false,
          isOpeningDealRunning: false,
          isHumanActionPending: false,
        ),
        isTrue,
      );

      expect(
        ClassicHareegTableSessionFlowPlanner.canAcceptHumanInput(
          isCpuRunning: true,
          isOpeningDealRunning: false,
          isHumanActionPending: false,
        ),
        isFalse,
      );
      expect(
        ClassicHareegTableSessionFlowPlanner.canAcceptHumanInput(
          isCpuRunning: false,
          isOpeningDealRunning: true,
          isHumanActionPending: false,
        ),
        isFalse,
      );
      expect(
        ClassicHareegTableSessionFlowPlanner.canAcceptHumanInput(
          isCpuRunning: false,
          isOpeningDealRunning: false,
          isHumanActionPending: true,
        ),
        isFalse,
      );
    });

    test('keeps Table-tier fast-forward narrowly scoped', () {
      expect(
        ClassicHareegTableSessionFlowPlanner.canFastForwardRound(
          strictness: TableStrictness.table,
          removedSeats: const {PlayerSeat.south},
          isRoundOver: false,
        ),
        isTrue,
      );

      expect(
        ClassicHareegTableSessionFlowPlanner.canFastForwardRound(
          strictness: TableStrictness.strict,
          removedSeats: const {PlayerSeat.south},
          isRoundOver: false,
        ),
        isFalse,
      );
      expect(
        ClassicHareegTableSessionFlowPlanner.canFastForwardRound(
          strictness: TableStrictness.table,
          removedSeats: const {PlayerSeat.east},
          isRoundOver: false,
        ),
        isFalse,
      );
      expect(
        ClassicHareegTableSessionFlowPlanner.canFastForwardRound(
          strictness: TableStrictness.table,
          removedSeats: const {PlayerSeat.south},
          isRoundOver: true,
        ),
        isFalse,
      );
    });
  });
}
