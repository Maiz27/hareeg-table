import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/match_progression_rules.dart';

import '../classic_hareeg_match_driver.dart';
import 'match_invariants.dart';

/// The tightened-sweep half of issue #94: a round forced to a draw by the
/// stock-exhaustion liveness backstop is a *failure* for converging configs.
/// Pairs with the controller-level reproduction (pickup_finish_liveness_test):
/// that proves the detector/executor disagreement makes the engine reach for the
/// backstop; this proves the no-recovery sweep then turns that backstop draw —
/// which the recovering driver tolerated as a silent draw — into a failure.
void main() {
  final setup = ClassicHareegSetup.defaults();

  DrivenRoundReport roundReport({required bool endedByLivelockBackstop}) {
    final snapshot = ClassicHareegMatchSnapshot(
      setup: setup,
      hands: const {},
      stock: const [],
      discardPile: const [],
      starter: PlayerSeat.south,
      currentSeat: PlayerSeat.south,
      turnPhase: TurnPhase.draw,
      savedAt: DateTime.utc(2026),
    );
    return DrivenRoundReport(
      roundNumber: 3,
      result: const RoundProgressResult(
        type: RoundOutcomeType.draw,
        remainingCardCounts: {},
      ),
      progress: null,
      scoresBefore: const {},
      scoresAfter: const {},
      snapshotAtRoundOver: snapshot,
      endedByLivelockBackstop: endedByLivelockBackstop,
    );
  }

  test('converging checker fails a backstop-forced draw', () {
    // The backstop assertion runs before the value invariants, so this isolates
    // the liveness check on a minimal round report.
    final checker = MatchInvariantChecker(
      setup: setup,
      seed: 1,
      requireNoBackstopDraw: true,
    );
    expect(
      () => checker.checkRound(roundReport(endedByLivelockBackstop: true)),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('liveness backstop'),
        ),
      ),
    );
  });
}
