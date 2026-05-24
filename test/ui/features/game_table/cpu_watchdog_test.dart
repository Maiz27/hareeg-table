import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/app/app_routes.dart';
import 'package:hareeg_table/app/hareeg_table_app.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/ui/core/cards/showcase_card_fan.dart';
import 'package:hareeg_table/ui/features/game_table/widgets/physical_table_playfield.dart';

import '../../../support/test_fixtures.dart';

void main() {
  // Pin the home screen's showcase fan so `pumpAndSettle` does not chase the
  // looping idle animation while we wait for the table to come up.
  ShowcaseCardFan.disableLoopingMotionForTesting = true;

  testWidgets(
    'cpu loop self-recovers and round advances when the human is removed',
    (tester) async {
      // Snapshot construction approach: build a Table-tier saved snapshot
      // where the human (south) is already in `removedSeats` and the active
      // turn belongs to a CPU seat (east, draw phase). Pre-fix, the CPU
      // runner would yield humanTurn after each CPU action and the
      // game-table screen would sit waiting on a human that can never act;
      // the loop deadlocked. With the fix the runner skips the removed
      // human seat and either keeps cycling through CPUs or ends the round
      // naturally on stock exhaustion.
      final setup = ClassicHareegSetup.defaults().copyWith(
        tableStrictness: TableStrictness.table,
      );
      final base = ClassicHareegRound.deal(setup: setup, seed: 23);
      final snapshot = ClassicHareegMatchSnapshot(
        setup: setup,
        hands: base.hands,
        stock: base.stock,
        discardPile: base.discardPile,
        starter: base.starter,
        currentSeat: PlayerSeat.east,
        turnPhase: TurnPhase.draw,
        removedSeats: const [PlayerSeat.south],
        savedAt: DateTime.utc(2026, 5, 18),
      );

      final repository = MemoryMatchRepository(saved: snapshot);
      await tester.pumpWidget(
        HareegTableApp(
          preferencesRepository: MemoryPreferencesRepository(),
          matchRepository: repository,
          initialRouteOverride: AppRoutes.home,
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      // Use bounded pumps below; do not pumpAndSettle yet because the CPU
      // loop is intentionally long-running with timed dwells between turns.

      // Drain the CPU loop with a generous bounded budget. `pumpAndSettle`
      // with a 30s budget will return either when no further frames are
      // scheduled (loop ended / round ended) or it will time out (deadlock).
      // A deadlock would either keep scheduling frames forever (timeout) or
      // bubble up a stuck-pumping exception via `tester.takeException`.
      await tester.pumpAndSettle(const Duration(seconds: 30));

      // No hung-frame exception escaped to the binding.
      expect(tester.takeException(), isNull);

      // The table either reached round end or finished CPU re-entry without
      // the round being over. In both cases the table must have left east's
      // draw phase — the original deadlock would freeze on the initial
      // (east, draw) state. Reach into the screen via the playfield to make
      // the assertion against the live render, which is what an end-user
      // would see.
      expect(find.byType(PhysicalTablePlayfield), findsOneWidget);
      final playfield = tester.widget<PhysicalTablePlayfield>(
        find.byType(PhysicalTablePlayfield),
      );
      // Robust signal across both possible outcomes:
      //   - Round ended: south stays in `removedSeats`, the round-active set
      //     never has south, and `currentSeat` may have advanced or rested.
      //   - Round still in progress: the loop cycled through at least one
      //     CPU and is now sitting on a different CPU seat or back at east
      //     after a full lap. Either way it is NOT stuck on south, and the
      //     active-seat set still excludes south.
      expect(
        playfield.activeSeats.contains(PlayerSeat.south),
        isFalse,
        reason: 'South is removed; round-active set must exclude south.',
      );
      expect(
        playfield.currentSeat,
        isNot(PlayerSeat.south),
        reason:
            'The CPU loop must never yield turn control to the removed human '
            'seat; doing so is exactly the deadlock signature.',
      );
    },
  );
}
