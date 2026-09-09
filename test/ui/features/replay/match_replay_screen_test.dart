import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/coaching/analysis_coach_settings.dart';
import 'package:hareeg_table/data/persistence/match_history_repository.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_outcomes.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_summary.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_replay_record.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_action_transcript.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/features/game_table/widgets/physical_table_playfield.dart';
import 'package:hareeg_table/ui/features/replay/views/match_replay_screen.dart';
import 'package:hareeg_table/ui/features/replay/widgets/review_table_playfield.dart';

import '../../../support/completed_match_fixture.dart';
import '../../../support/test_fixtures.dart';

const _matchId = 'm-screen-aaaaaaaa';
const _slow = Timeout(Duration(minutes: 5));

late MatchActionTranscript _transcript;

/// Serves one prepared answer, and counts how many times it was asked.
class _ScriptedHistoryRepository extends MemoryMatchHistoryRepository {
  _ScriptedHistoryRepository(this._answer);

  MatchReplayOpenOutcome Function(int attempt) _answer;
  int openCalls = 0;
  MatchReplayRepairOutcome repairAnswer = MatchReplayRepaired(
    historySummary(matchId: _matchId, replayable: false),
  );

  set answer(MatchReplayOpenOutcome Function(int) value) => _answer = value;

  @override
  Future<MatchReplayOpenOutcome> openReplay(String matchId) async {
    openCalls += 1;
    return _answer(openCalls);
  }

  @override
  Future<MatchReplayRepairOutcome> repairUnusableReplay({
    required String matchId,
    required String reason,
  }) async {
    repairCalls.add(matchId);
    return repairAnswer;
  }
}

Widget _app(MatchHistoryRepository repository, {MatchHistorySummary? summary}) {
  return MaterialApp(
    home: MatchReplayScreen(
      summary: summary ?? historySummary(matchId: _matchId),
      historyRepository: repository,
      analysisCoach: AnalysisCoachSettings.defaults(),
    ),
  );
}

MatchActionTranscript _mutatedSeat() {
  final entries = [..._transcript.entries];
  final target = entries[40];
  entries[40] = MatchActionTranscriptEntry(
    order: target.order,
    seat: PlayerSeat.values.firstWhere((s) => s != target.seat),
    roundNumber: target.roundNumber,
    phase: target.phase,
    actionId: target.actionId,
  );
  return MatchActionTranscript(
    initialSnapshot: _transcript.initialSnapshot,
    entries: entries,
  );
}

void main() {
  setUpAll(() {
    final state = buildCompletedMatch(seed: 13).recorderState;
    _transcript = MatchActionTranscript(
      initialSnapshot: state.initialSnapshot!,
      entries: state.entries,
    );
  });

  testWidgets('a real match loads onto the real table', timeout: _slow, (
    tester,
  ) async {
    final repository = _ScriptedHistoryRepository(
      (_) => MatchReplayOpened(
        MatchReplayRecord(matchId: _matchId, transcript: _transcript),
      ),
    );

    await tester.pumpWidget(_app(repository));
    // Rebuilding a whole match cannot happen inside one frame, so the player
    // is told what is happening rather than shown a frozen screen.
    expect(find.text(AppStrings.english.replayLoading), findsOneWidget);

    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.byType(ReviewTablePlayfield), findsOneWidget);
    expect(find.byType(PhysicalTablePlayfield), findsOneWidget);
    expect(find.text(AppStrings.english.replayLoading), findsNothing);
  });

  testWidgets('stepping forward moves through the match', timeout: _slow, (
    tester,
  ) async {
    final repository = _ScriptedHistoryRepository(
      (_) => MatchReplayOpened(
        MatchReplayRecord(matchId: _matchId, transcript: _transcript),
      ),
    );

    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    final strings = AppStrings.english;
    expect(find.textContaining('1 of'), findsOneWidget);

    await tester.tap(find.byTooltip(strings.replayNext));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 of'), findsOneWidget);

    await tester.tap(find.byTooltip(strings.replayPrevious));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 of'), findsOneWidget);

    // At the start there is nowhere back to go, so back is not offered.
    final back = tester.widget<IconButton>(
      find.descendant(
        of: find.byTooltip(strings.replayPrevious),
        matching: find.byType(IconButton),
      ),
    );
    expect(back.onPressed, isNull);
  });

  testWidgets('the table cannot be played while reviewing', timeout: _slow, (
    tester,
  ) async {
    final repository = _ScriptedHistoryRepository(
      (_) => MatchReplayOpened(
        MatchReplayRecord(matchId: _matchId, transcript: _transcript),
      ),
    );

    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    await tester.tap(find.byTooltip(AppStrings.english.replayNext));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 of'), findsOneWidget);

    // Tapping the table itself must do nothing at all — not advance, not
    // navigate, not throw.
    final playfield = find.byType(PhysicalTablePlayfield);
    await tester.tapAt(tester.getCenter(playfield));
    await tester.pumpAndSettle();

    expect(find.textContaining('2 of'), findsOneWidget);
    expect(find.byType(ReviewTablePlayfield), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a replay that cannot be rebuilt repairs history and says so',
    timeout: _slow,
    (tester) async {
      final repository = _ScriptedHistoryRepository(
        (_) => MatchReplayOpened(
          MatchReplayRecord(matchId: _matchId, transcript: _mutatedSeat()),
        ),
      );

      await tester.pumpWidget(_app(repository));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // The entry is repaired rather than left as a link that fails forever.
      expect(repository.repairCalls, [_matchId]);
      expect(
        find.text(AppStrings.english.replayUnavailableTitle),
        findsOneWidget,
      );
      expect(
        find.text(AppStrings.english.replayReasonMetadataInvalid),
        findsOneWidget,
      );
      // No Retry: the same bytes would fail the same way.
      expect(find.text(AppStrings.english.replayRetry), findsNothing);
    },
  );

  testWidgets('the engine\'s own wording never reaches the player', timeout: _slow, (
    tester,
  ) async {
    final repository = _ScriptedHistoryRepository(
      (_) => MatchReplayOpened(
        MatchReplayRecord(matchId: _matchId, transcript: _mutatedSeat()),
      ),
    );

    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final value = text.data ?? '';
      expect(value, isNot(contains('deck-')));
      expect(value, isNot(contains('Transcript entry')));
      expect(value, isNot(contains('seatMismatch')));
    }
  });

  testWidgets('a retryable failure offers a real second attempt', timeout: _slow, (
    tester,
  ) async {
    final repository = _ScriptedHistoryRepository(
      (attempt) => attempt == 1
          ? MatchReplayOpenFailed(
              const MatchHistoryFailure(
                kind: MatchHistoryFailureKind.retryable,
                matchId: _matchId,
                message: 'Replay read failed.',
              ),
            )
          : MatchReplayOpened(
              MatchReplayRecord(matchId: _matchId, transcript: _transcript),
            ),
    );

    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    expect(repository.openCalls, 1);
    expect(
      find.text(AppStrings.english.replayLoadFailedRetryable),
      findsOneWidget,
    );

    await tester.tap(find.text(AppStrings.english.replayRetry));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Retry means a genuine second call, and this one succeeds.
    expect(repository.openCalls, 2);
    expect(find.byType(ReviewTablePlayfield), findsOneWidget);
  });

  testWidgets('a corrupt failure offers no retry at all', timeout: _slow, (
    tester,
  ) async {
    final repository = _ScriptedHistoryRepository(
      (_) => MatchReplayOpenFailed(
        const MatchHistoryFailure(
          kind: MatchHistoryFailureKind.corrupt,
          matchId: _matchId,
          message: 'History index is damaged.',
        ),
      ),
    );

    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    expect(
      find.text(AppStrings.english.replayLoadFailedCorrupt),
      findsOneWidget,
    );
    expect(find.text(AppStrings.english.replayRetry), findsNothing);
    expect(repository.openCalls, 1);
  });

  testWidgets('leaving mid-rebuild is safe', timeout: _slow, (tester) async {
    final repository = _ScriptedHistoryRepository(
      (_) => MatchReplayOpened(
        MatchReplayRecord(matchId: _matchId, transcript: _transcript),
      ),
    );

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    // Walk away while the match is still being rebuilt.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(tester.takeException(), isNull);
  });

  testWidgets('the coach is quiet on positions that are not moves', timeout: _slow, (
    tester,
  ) async {
    final repository = _ScriptedHistoryRepository(
      (_) => MatchReplayOpened(
        MatchReplayRecord(matchId: _matchId, transcript: _transcript),
      ),
    );

    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // The opening position is a deal, not a decision, so there is nothing to
    // review — which is a different thing from having reviewed and found
    // nothing worth saying.
    expect(
      find.text(AppStrings.english.replayCoachNothingToReview),
      findsOneWidget,
    );
    expect(find.text(AppStrings.english.replayDeal), findsOneWidget);
  });

  testWidgets(
    'the table keeps its space when the coach has a lot to say',
    timeout: _slow,
    (tester) async {
      // A real device found this: with narration on, the analysis panel sized
      // itself to its content, squeezed the table to zero height, and the
      // playfield threw. A landscape phone is the tight case, so it is the one
      // asserted here.
      // Pixel_8a in landscape: 2400x1080 PHYSICAL at ~2.625 density, which is
      // only about 914x411 logical. Using the physical numbers as logical ones
      // gives a viewport four times too tall, and the squeeze never happens.
      tester.view.physicalSize = const Size(2400, 1080);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _ScriptedHistoryRepository(
        (_) => MatchReplayOpened(
          MatchReplayRecord(matchId: _matchId, transcript: _transcript),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MatchReplayScreen(
            summary: historySummary(matchId: _matchId),
            historyRepository: repository,
            // The loudest setting, which is what produced the overflow.
            analysisCoach: const AnalysisCoachSettings(
              verbosity: AnalysisVerbosity.narrateAll,
              cardDeathWarnings: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Walk a stretch of real moves; any frame that overflows or throws fails.
      for (var i = 0; i < 12; i++) {
        await tester.tap(find.byTooltip(AppStrings.english.replayNext));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'step $i');
        expect(
          tester.getSize(find.byType(ReviewTablePlayfield)).height,
          greaterThan(0),
          reason: 'the table must never be squeezed away at step $i',
        );
      }
    },
  );
}
