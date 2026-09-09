import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_outcomes.dart';
import 'package:hareeg_table/ui/features/history/match_history_view_state.dart';

import '../../../support/test_fixtures.dart';

void main() {
  group('MatchHistoryViewState.fromOutcome', () {
    test('a listed set of summaries loads in the order it arrived', () {
      final summaries = [
        historySummary(matchId: 'm-b-aaaaaaaa'),
        historySummary(matchId: 'm-a-aaaaaaaa'),
      ];

      final state = MatchHistoryViewState.fromOutcome(
        MatchHistoryListed(summaries: summaries, repairedMatchIds: const []),
      );

      // Not re-sorted: ordering has one owner, and it is the repository.
      expect(state, isA<MatchHistoryLoaded>());
      expect(
        (state as MatchHistoryLoaded).summaries.map((s) => s.matchId),
        ['m-b-aaaaaaaa', 'm-a-aaaaaaaa'],
      );
    });

    test('an empty listing is the empty state', () {
      final state = MatchHistoryViewState.fromOutcome(
        const MatchHistoryListed(summaries: [], repairedMatchIds: []),
      );

      expect(state, isA<MatchHistoryEmpty>());
    });

    test('a repaired summary is still listed', () {
      final state = MatchHistoryViewState.fromOutcome(
        MatchHistoryListed(
          summaries: [historySummary(matchId: 'm-a-aaaaaaaa', replayable: false)],
          repairedMatchIds: const ['m-a-aaaaaaaa'],
        ),
      );

      // Losing a replay must not lose the match.
      expect(state, isA<MatchHistoryLoaded>());
      expect((state as MatchHistoryLoaded).summaries, hasLength(1));
    });

    test('a retryable failure is failed, not empty', () {
      final state = MatchHistoryViewState.fromOutcome(
        const MatchHistoryListFailed(
          MatchHistoryFailure(
            kind: MatchHistoryFailureKind.retryable,
            message: 'store offline',
          ),
        ),
      );

      // Rendering this as "no saved matches yet" would tell the player their
      // history had been deleted.
      expect(state, isA<MatchHistoryFailed>());
      expect(state, isNot(isA<MatchHistoryEmpty>()));
      expect((state as MatchHistoryFailed).isRetryable, isTrue);
    });

    test('a corrupt failure keeps its kind so the copy can differ', () {
      final state = MatchHistoryViewState.fromOutcome(
        const MatchHistoryListFailed(
          MatchHistoryFailure(
            kind: MatchHistoryFailureKind.corrupt,
            message: 'index does not decode',
          ),
        ),
      );

      expect(state, isA<MatchHistoryFailed>());
      final failed = state as MatchHistoryFailed;
      // Flattening the failure would make the retryable/corrupt distinction
      // unrenderable, which is the whole point of the typed outcome.
      expect(failed.failure.kind, MatchHistoryFailureKind.corrupt);
      expect(failed.isRetryable, isFalse);
      expect(failed.failure.message, 'index does not decode');
    });
  });
}
