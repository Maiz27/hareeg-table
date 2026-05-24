import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/app/app_routes.dart';
import 'package:hareeg_table/app/hareeg_table_app.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/ui/core/cards/card_view.dart';
import 'package:hareeg_table/ui/core/cards/showcase_card_fan.dart';
import 'package:hareeg_table/ui/features/game_table/widgets/physical_table_playfield.dart';

import '../../../support/test_fixtures.dart';

void main() {
  // Pin the home screen's showcase fan so `pumpAndSettle` does not chase the
  // looping idle animation.
  ShowcaseCardFan.disableLoopingMotionForTesting = true;

  testWidgets(
    'removed seat renders no hand-card widgets while south stays visible',
    (tester) async {
      // Snapshot construction approach (option a): build a Table-tier saved
      // snapshot with the west seat already pre-populated in `removedSeats`,
      // then enter the table via the Continue button. The controller still
      // holds west's full dealt hand (so the underlying state is "removed,
      // not empty"), but the renderer must zero west's visible card count.
      // Pre-fix the renderer ignored `removedSeats` and west's hand stayed
      // on the table — that is precisely the regression this test guards.
      final setup = ClassicHareegSetup.defaults().copyWith(
        tableStrictness: TableStrictness.table,
      );
      final base = ClassicHareegRound.deal(setup: setup, seed: 17);
      final snapshot = ClassicHareegMatchSnapshot(
        setup: setup,
        hands: base.hands,
        stock: base.stock,
        discardPile: base.discardPile,
        starter: base.starter,
        // South is the human seat; keep its action turn so the CPU loop does
        // not fire and the frame settles cleanly before assertions.
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.action,
        removedSeats: const [PlayerSeat.west],
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
      await tester.pumpAndSettle();

      // The PhysicalTablePlayfield must have mounted (we are on the table).
      expect(find.byType(PhysicalTablePlayfield), findsOneWidget);

      // Pre-condition: the controller really did restore west as `removed`
      // with a non-empty hand. If this ever breaks the restoration path
      // shifted and the rest of the assertions would be meaningless.
      final restoredWestHand =
          repository.saved?.hands[PlayerSeat.west] ?? const <HareegCard>[];
      expect(
        restoredWestHand,
        isNotEmpty,
        reason:
            'Pre-condition: snapshot is supposed to keep west\'s dealt hand '
            'in controller state; the renderer is responsible for hiding it.',
      );

      // Core L2 assertion: zero hand-card widgets render inside the west
      // opponent rail when west is removed.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('west-opponent-rail')),
          matching: find.byType(HareegCardView),
        ),
        findsNothing,
        reason: 'Removed seats must not render any hand cards on the table.',
      );

      // Control case: south (human) still has a visible hand.
      expect(find.byType(HareegCardView), findsWidgets);
    },
  );
}
