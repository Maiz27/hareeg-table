import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/ui/features/game_table/table_session_config.dart';
import 'package:hareeg_table/ui/features/game_table/widgets/physical_table_playfield.dart';
import 'package:hareeg_table/ui/features/game_table/widgets/table_center_area.dart';

import '../../../support/branch_sandbox_harness.dart';

/// A sandbox plays like a real match and stores nothing.
///
/// The two are separate claims and this file only makes the first: the table
/// progresses, crosses rounds, handles elimination and hands the turn round the
/// seats. That it reaches no repository is proven separately, by a guard that
/// records attempted mutations rather than by the absence of one here.
void main() {
  PhysicalTablePlayfield playfield(WidgetTester tester) =>
      tester.widget<PhysicalTablePlayfield>(
        find.byType(PhysicalTablePlayfield),
      );

  group('progression without persistence', () {
    testWidgets('an ephemeral branch crosses a round in memory', (
      tester,
    ) async {
      await pumpBranchSandbox(
        tester,
        branchSandboxApp(
          frame: branchFrame(
            branchSnapshot(
              southHand: branchFinishingHand,
              openingState: branchOpened(PlayerSeat.south),
            ),
          ),
          visibility: BranchVisibility.blind,
          coachEligible: false,
        ),
      );

      expect(playfield(tester).currentSeat, PlayerSeat.south);

      await branchFinishRound(tester);
      // Round-over is only proven by the *next* round being dealt. A finished
      // round that stopped there would leave the sandbox stuck on a board
      // nobody can play, which is exactly what a progression-less branch
      // would look like.
      await tester.pumpAndSettle(const Duration(seconds: 30));

      final table = playfield(tester);
      // The crossing is only proven by a *fresh deal*. South went out on the
      // four-card finishing hand, so a sandbox that stopped at round-over
      // would show zero cards and one that never applied the finish would show
      // the same four. Neither passes this.
      expect(
        table.cardCounts[PlayerSeat.south],
        greaterThan(branchFinishingHand.length),
        reason: 'south holds a freshly dealt hand, so the round really crossed',
      );
      final ids = table.southCards.map((c) => c.id).toSet();
      for (final card in branchFinishingHand) {
        expect(
          ids,
          isNot(contains(card.id)),
          reason: 'the finished round cards must be gone',
        );
      }
      expect(
        table.activeSeats,
        contains(PlayerSeat.south),
        reason: 'a crossed round leaves south in play',
      );
    });

    testWidgets('south elimination ends the sandbox instead of stalling', (
      tester,
    ) async {
      // South is already past the elimination threshold with the CPUs still
      // playing. Live play abandons the match here; a sandbox has nothing to
      // abandon, so what has to be proven is that it still *stops* rather than
      // dealing a spectator round.
      await pumpBranchSandbox(
        tester,
        branchSandboxApp(
          frame: branchFrame(
            branchSnapshot(
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
            ),
            index: 40,
          ),
          visibility: BranchVisibility.blind,
          coachEligible: false,
        ),
      );

      // The sandbox reaches its completion surface, and offers exactly the two
      // exits a sandbox has.
      expect(find.text('Return to replay'), findsOneWidget);
      expect(find.text('Restart from branch point'), findsOneWidget);
      // And none of the live match-over affordances.
      expect(find.text('Rematch'), findsNothing);
    });
  });

  group('south is the only playable seat', () {
    testWidgets('no opponent rail is actionable, in either visibility', (
      tester,
    ) async {
      for (final visibility in BranchVisibility.values) {
        await pumpBranchSandbox(
          tester,
          branchSandboxApp(
            frame: branchFrame(branchSnapshot()),
            visibility: visibility,
            coachEligible: false,
          ),
        );

        final table = playfield(tester);
        // The table's whole action surface is south's: the hand, the discard
        // and the meld affordances. There is no per-seat handler at all for
        // north, east or west, in either visibility — which is why "study mode
        // changes rendering only" is a structural claim rather than a promise.
        expect(table.southCards, isNotEmpty);
        expect(table.isHumanTurn, isTrue);
        for (final seat in const [
          PlayerSeat.north,
          PlayerSeat.east,
          PlayerSeat.west,
        ]) {
          expect(
            table.cardCounts[seat],
            greaterThan(0),
            reason: '$seat should still hold cards in $visibility',
          );
        }
        expect(table.onExpandRevealedHand, isNotNull);
        // Expansion is the only opponent-facing affordance, and it exists only
        // where a hand is already revealed.
        expect(
          table.revealedHands.isEmpty,
          visibility == BranchVisibility.blind,
          reason: '$visibility',
        );
      }
    });

    testWidgets('a CPU-current seed runs the CPUs until south can act', (
      tester,
    ) async {
      await pumpBranchSandbox(
        tester,
        branchSandboxApp(
          frame: branchFrame(
            branchSnapshot(
              currentSeat: PlayerSeat.east,
              turnPhase: TurnPhase.draw,
            ),
          ),
          visibility: BranchVisibility.blind,
          coachEligible: false,
        ),
      );

      // The seed handed the sandbox a CPU turn. Once it settles, the turn is
      // south's — the CPUs ran on their own, exactly as live play does.
      final table = playfield(tester);
      expect(table.currentSeat, PlayerSeat.south);
      expect(table.isCpuRunning, isFalse);
      expect(
        table.isHumanTurn,
        isTrue,
        reason: 'south input unlocks only after the CPU turns finish',
      );
    });
  });

  group('the sandbox runs on its own clock', () {
    testWidgets('advancing the injected clock advances the Fifty timer', (
      tester,
    ) async {
      // The window opened one second before the frame's clock, so the rebased
      // sandbox starts with the same remaining time the archived position had
      // — not a fresh timer, and not an already-expired one.
      final frameClock = DateTime.utc(2026, 6, 1, 12);
      final snapshot = branchSnapshot(
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.draw,
        discardPile: [branchCard(CardRank.king, CardSuit.hearts)],
        fiftyWindowOpenedAt: frameClock.subtract(const Duration(seconds: 1)),
        fiftyWindowDiscarder: PlayerSeat.east,
        savedAt: frameClock,
      );
      final clock = BranchTestClock(DateTime.utc(2026, 9, 7, 9));

      await pumpBranchSandbox(
        tester,
        branchSandboxApp(
          frame: branchFrame(snapshot, clock: frameClock),
          visibility: BranchVisibility.blind,
          coachEligible: false,
          clock: clock.call,
        ),
      );

      final total = snapshot.setup.fiftyTimerSeconds;
      int? shown() {
        final cue = find.byType(TableFiftyCue);
        if (cue.evaluate().isEmpty) {
          return null;
        }
        return tester.widget<TableFiftyCue>(cue).secondsRemaining;
      }

      expect(
        total,
        greaterThan(2),
        reason: 'the fixture needs room to tick before it expires',
      );
      expect(
        shown(),
        total - 1,
        reason: 'the sandbox inherits the historical remaining time',
      );

      // Advancing the clock the sandbox was handed — not the wall clock, and
      // with no sleep anywhere — moves the timer.
      clock.advance(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 600));
      expect(shown(), total - 2);

      clock.advance(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 600));
      expect(shown(), total - 3);
    });
  });
}
