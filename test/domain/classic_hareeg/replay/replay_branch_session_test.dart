import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/replay/replay_branch_session.dart';

import '../../../support/branch_sandbox_harness.dart';

/// B49, clause by clause: what a restart from the branch point resets.
///
/// The board, the visibility and the divergence reset are also asserted
/// through the rendered table in `branch_exit_test.dart`. What cannot be
/// asserted there is the **clock rebase**: the sandbox clock is frozen in a
/// widget test, so a Fifty window that never expires would keep the ticker
/// scheduling frames and `pumpAndSettle` would never return. The rebase is
/// therefore proven here, where instants can be named exactly.
void main() {
  final setup = ClassicHareegSetup.defaults();
  final timer = setup.fiftyTimerSeconds;

  // The window opened one second before the frame was recorded, so it has
  // history: one second spent, the rest still to run. A window with nothing
  // spent could not tell a rebase apart from a reset to full.
  const spent = Duration(seconds: 1);
  final frameClock = DateTime.utc(2026, 6, 1, 12);
  final firstStart = DateTime.utc(2027, 1, 1, 10);
  final secondStart = firstStart.add(const Duration(minutes: 5));

  ReplayBranchSession sessionAt(DateTime branchStart) {
    final snapshot = branchSnapshot(
      // A window only restores over a non-empty pile with the seat on draw.
      currentSeat: PlayerSeat.south,
      turnPhase: TurnPhase.draw,
      discardPile: [branchCard(CardRank.four, CardSuit.hearts)],
      fiftyWindowOpenedAt: frameClock.subtract(spent),
      fiftyWindowDiscarder: PlayerSeat.east,
      savedAt: frameClock,
    );
    return ReplayBranchSession.start(
      frame: branchFrame(snapshot, clock: frameClock),
      nextFrame: null,
      coachEligible: true,
      branchStart: branchStart,
    )!;
  }

  /// Seconds left on [session]'s window [after] its own branch instant, read
  /// through the production formula rather than recomputed here.
  int? remainingAfter(ReplayBranchSession session, Duration after) {
    final at = session.seed.branchStart.add(after);
    return branchFrame(
      session.seed.snapshot,
      clock: at,
    ).fiftySecondsRemainingAt(at);
  }

  test('a restart hands back the same board it started from', () {
    final first = sessionAt(firstStart);
    final restarted = first.restart(branchStart: secondStart);

    expect(restarted.seed.snapshot.hands, first.seed.snapshot.hands);
    expect(restarted.seed.snapshot.stock, first.seed.snapshot.stock);
    expect(restarted.seed.snapshot.scores, first.seed.snapshot.scores);
    expect(restarted.seed.snapshot.currentSeat, PlayerSeat.south);
    // And it still returns to the frame the player chose.
    expect(restarted.frameIndex, first.frameIndex);
  });

  test('a restart clears divergence', () {
    final first = sessionAt(firstStart);
    first.recordAppliedAction();
    expect(first.hasDiverged, isTrue);

    final restarted = first.restart(branchStart: secondStart);
    expect(restarted.hasDiverged, isFalse);
    // The abandoned run is left alone rather than mutated, which is what makes
    // "restart resets divergence" a property of the type.
    expect(first.hasDiverged, isTrue);
  });

  test('a restart returns the coach to the archived state', () {
    final first = sessionAt(firstStart);
    expect(first.coachEnabled, isTrue, reason: 'inherited from the archive');
    first.setCoachEnabled(false);
    expect(first.coachEnabled, isFalse);

    final restarted = first.restart(branchStart: secondStart);
    expect(
      restarted.coachEnabled,
      isTrue,
      reason: 'a restart returns to the branch point, coach included',
    );
    expect(restarted.coachEligible, isTrue);
  });

  test('an open Fifty window is rebased afresh, not carried or reset', () {
    final first = sessionAt(firstStart);

    // The first run: the window opened `spent` before this run began, so it
    // has exactly the time it historically had left.
    expect(first.seed.snapshot.fiftyWindowOpenedAt, firstStart.subtract(spent));
    expect(remainingAfter(first, Duration.zero), timer - spent.inSeconds);

    // Five minutes pass — far past the window — and then the player restarts.
    final restarted = first.restart(branchStart: secondStart);

    // Rebased: anchored to the *new* branch instant.
    expect(
      restarted.seed.snapshot.fiftyWindowOpenedAt,
      secondStart.subtract(spent),
    );
    expect(
      restarted.seed.snapshot.fiftyWindowOpenedAt,
      isNot(first.seed.snapshot.fiftyWindowOpenedAt),
      reason: 'a carried-over window would still be anchored to the old run',
    );

    // Afresh, and *not* reset to full: the second run gets the same historical
    // remaining time the first one did. A window that restarted at the full
    // timer would hand the player a second more than the archived match had.
    expect(remainingAfter(restarted, Duration.zero), timer - spent.inSeconds);
    expect(
      remainingAfter(restarted, Duration.zero),
      isNot(timer),
      reason: 'the spent second must not be given back',
    );

    // And it still runs down from there, rather than being frozen open.
    expect(
      remainingAfter(restarted, const Duration(seconds: 1)),
      timer - spent.inSeconds - 1,
    );
    expect(remainingAfter(restarted, Duration(seconds: timer)), 0);
  });
}
