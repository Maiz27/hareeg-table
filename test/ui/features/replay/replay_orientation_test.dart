import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/app/app_orientation.dart';
import 'package:hareeg_table/cpu/classic_hareeg/coaching/analysis_coach_settings.dart';
import 'package:hareeg_table/data/persistence/match_history_repository.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_outcomes.dart';
import 'package:hareeg_table/ui/features/replay/views/match_replay_screen.dart';

import '../../../support/test_fixtures.dart';

/// Records what a screen asked for, in order.
///
/// A bare platform-channel mock is not enough here: the real policy skips the
/// platform call when the requested orientation is already in force, so a mode
/// left behind by an earlier screen would swallow the call and the test would
/// pass having observed nothing.
class _RecordingOrientationPolicy implements OrientationPolicy {
  final List<String> requests = [];

  @override
  Future<void> usePortrait() async => requests.add('portrait');

  @override
  Future<void> useLandscape() async => requests.add('landscape');
}

/// Never answers, so the screen stays mid-load for as long as the test needs.
class _HangingHistoryRepository extends MemoryMatchHistoryRepository {
  @override
  Future<MatchReplayOpenOutcome> openReplay(String matchId) {
    return Completer<MatchReplayOpenOutcome>().future;
  }
}

void main() {
  late _RecordingOrientationPolicy policy;
  late OrientationPolicy previous;

  setUp(() {
    policy = _RecordingOrientationPolicy();
    previous = AppOrientation.installPolicy(policy);
  });

  tearDown(() => AppOrientation.installPolicy(previous));

  Future<void> pumpReplay(WidgetTester tester, MatchHistoryRepository repo) {
    return tester.pumpWidget(
      MaterialApp(
        home: MatchReplayScreen(
          summary: historySummary(matchId: 'm-orient-aaaaaaaa'),
          historyRepository: repo,
          analysisCoach: AnalysisCoachSettings.defaults(),
        ),
      ),
    );
  }

  testWidgets('review turns the device to landscape, like the table', (
    tester,
  ) async {
    await pumpReplay(tester, _HangingHistoryRepository());
    await tester.pump();

    expect(policy.requests, contains('landscape'));
  });

  testWidgets('leaving review hands portrait back', (tester) async {
    await pumpReplay(tester, _HangingHistoryRepository());
    await tester.pump();
    policy.requests.clear();

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    expect(policy.requests, ['portrait']);
  });

  testWidgets('a load finishing after the player left changes nothing', (
    tester,
  ) async {
    final repository = _HangingHistoryRepository();
    await pumpReplay(tester, repository);
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
    policy.requests.clear();

    // Whatever the abandoned load does next, it must not reach around and
    // rotate the screen the player is now looking at.
    await tester.pump(const Duration(seconds: 2));
    expect(policy.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
