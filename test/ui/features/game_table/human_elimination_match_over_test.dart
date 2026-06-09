import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/app/app_routes.dart';
import 'package:hareeg_table/app/hareeg_table_app.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/ui/core/cards/showcase_card_fan.dart';
import 'package:hareeg_table/ui/features/game_table/widgets/physical_table_playfield.dart';
import 'package:hareeg_table/ui/features/match_over/views/match_over_screen.dart';

import '../../../support/test_fixtures.dart';

void main() {
  ShowcaseCardFan.disableLoopingMotionForTesting = true;

  testWidgets(
    'resuming a match with the human eliminated by score opens match-over',
    (tester) async {
      // Mirrors the on-device freeze: round 2, the human (south) sits at 34 —
      // past the 31 elimination threshold — removed from the round by a Table
      // penalty, with three CPUs still active and the round NOT over. Pre-fix
      // the table sat here forever (no round result -> no match-over). The
      // controller now concludes the dead round on load and the table must
      // surface match-over instead of stranding the human.
      final setup = ClassicHareegSetup.defaults().copyWith(
        tableStrictness: TableStrictness.table,
      );
      final base = ClassicHareegRound.deal(setup: setup, seed: 23);
      final snapshot = ClassicHareegMatchSnapshot(
        setup: setup,
        hands: base.hands,
        stock: base.stock,
        discardPile: base.discardPile,
        // South is the round starter — the exact on-device shape that crashed
        // `nextRoundSnapshot` ("Starter must be an active seat") once south was
        // eliminated and the round concluded as a draw.
        starter: PlayerSeat.south,
        currentSeat: PlayerSeat.north,
        turnPhase: TurnPhase.draw,
        scores: const {
          PlayerSeat.south: 34,
          PlayerSeat.east: 0,
          PlayerSeat.north: 0,
          PlayerSeat.west: 0,
        },
        removedSeats: const [PlayerSeat.south],
        roundNumber: 2,
        savedAt: DateTime.utc(2026, 6, 9),
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
      await tester.pumpAndSettle(const Duration(seconds: 30));

      expect(tester.takeException(), isNull);
      // The eliminated human must land on match-over, not the frozen table.
      expect(find.byType(MatchOverScreen), findsOneWidget);
      expect(find.byType(PhysicalTablePlayfield), findsNothing);
    },
  );
}
