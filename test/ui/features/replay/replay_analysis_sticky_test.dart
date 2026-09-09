import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/coaching/analysis_coach_settings.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_outcomes.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_replay_record.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_action_transcript.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/features/game_table/widgets/physical_table_playfield.dart';
import 'package:hareeg_table/ui/features/replay/views/match_replay_screen.dart';
import 'package:hareeg_table/ui/features/replay/widgets/analysis_coach_panel.dart';
import 'package:hareeg_table/ui/features/replay/widgets/review_table_playfield.dart';

import '../../../support/completed_match_fixture.dart';
import '../../../support/test_fixtures.dart';

const _matchId = 'm-screen-aaaaaaaa';
const _slow = Timeout(Duration(minutes: 5));
const _short = Size(844, 390);

late MatchActionTranscript _transcript;

class _StaticHistoryRepository extends MemoryMatchHistoryRepository {
  _StaticHistoryRepository(this._value);

  final MatchActionTranscript _value;

  @override
  Future<MatchReplayOpenOutcome> openReplay(String matchId) async {
    return MatchReplayOpened(
      MatchReplayRecord(matchId: _matchId, transcript: _value),
    );
  }
}

Finder _byTypeName(String name) => find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == name,
);

Future<void> _pumpShort(WidgetTester tester) async {
  tester.view.physicalSize = _short;
  tester.view.devicePixelRatio = 1.0;

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();

  await tester.pumpWidget(
    MaterialApp(
      home: MatchReplayScreen(
        summary: historySummary(matchId: _matchId),
        historyRepository: _StaticHistoryRepository(_transcript),
        analysisCoach: const AnalysisCoachSettings(
          verbosity: AnalysisVerbosity.narrateAll,
          cardDeathWarnings: true,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 1));

  // Onto a played move, so the coach has something to say.
  for (var i = 0; i < 6; i++) {
    await tester.tap(find.byTooltip(AppStrings.english.replayNext));
    await tester.pumpAndSettle();
  }
}

/// Opens the card from the 44 x 44 Analysis affordance in the physical-left
/// rail. The wide headline chip it replaced is withdrawn.
Future<void> _expand(WidgetTester tester) async {
  await tester.tap(find.byTooltip(AppStrings.english.replayCoachTitle));
  await tester.pumpAndSettle();
  expect(find.byType(AnalysisCoachPanel), findsOneWidget);
}

/// Runs [action] with the passive-boundary trace captured.
///
/// Restored inside the body rather than from a tear-down: the framework
/// verifies the foundation debug variables are back to their defaults before
/// tear-downs run, so a late restore fails the test for the wrong reason.
Future<List<String>> _captureTrace(
  WidgetTester tester,
  Future<void> Function() action,
) async {
  final delivered = <String>[];
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null &&
        message.startsWith(PassiveTableInteraction.traceTag)) {
      delivered.add(message);
    }
  };
  try {
    await action();
  } finally {
    debugPrint = original;
  }
  return delivered;
}

String _panelText(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byType(AnalysisCoachPanel),
        matching: find.byType(Text),
      ),
    )
    .map((t) => t.data)
    .join('|');

void main() {
  setUpAll(() {
    final state = buildCompletedMatch(seed: 13).recorderState;
    _transcript = MatchActionTranscript(
      initialSnapshot: state.initialSnapshot!,
      entries: state.entries,
    );
  });

  testWidgets('the card stays open while the reviewer steps', timeout: _slow, (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpShort(tester);
    await _expand(tester);

    final before = _panelText(tester);

    // Comparing one decision against the next is the review task. A card that
    // collapsed on every step would make that impossible, which is why this
    // is asserted across five frames rather than one. Transport shares the
    // card's tap-region group precisely so these taps are not "outside".
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byTooltip(AppStrings.english.replayNext));
      await tester.pumpAndSettle();
      expect(
        find.byType(AnalysisCoachPanel),
        findsOneWidget,
        reason: 'the card collapsed on step $i',
      );
    }

    final after = _panelText(tester);

    // Open is not enough: it has to be showing the new position, not a frozen
    // copy of the one it was opened on.
    expect(after, isNot(before));
  });

  testWidgets('every transport action keeps the card open', timeout: _slow, (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpShort(tester);
    await _expand(tester);

    // Step, round, First, Last and seek are all part of the review
    // interaction. Listing them one by one rather than testing "next" alone:
    // the dismissal group has to cover the whole rail, not the button the
    // first test happened to use.
    final strings = AppStrings.english;
    for (final tooltip in [
      strings.replayPrevious,
      strings.replayNext,
      strings.replayNextRound,
      strings.replayPreviousRound,
      strings.replayLast,
      strings.replayFirst,
    ]) {
      await tester.tap(find.byTooltip(tooltip));
      await tester.pumpAndSettle();
      expect(
        find.byType(AnalysisCoachPanel),
        findsOneWidget,
        reason: '$tooltip dismissed the card',
      );
    }

    // Seeking through the expanded scrubber counts too.
    await tester.tap(_byTypeName('ReplayScrubTarget'));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsOneWidget);
    expect(
      find.byType(AnalysisCoachPanel),
      findsOneWidget,
      reason: 'opening the scrubber dismissed the card',
    );
  });

  testWidgets('expanding never relayouts the table', timeout: _slow, (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpShort(tester);
    final collapsed = tester.getRect(find.byType(ReviewTablePlayfield));

    await _expand(tester);
    final expanded = tester.getRect(find.byType(ReviewTablePlayfield));

    // The card is an overlay, not a band. If the table moved, it is taking
    // space from the thing being reviewed.
    expect(expanded, collapsed);
  });

  testWidgets('a tap on the table collapses the card and still reaches the '
      'table', timeout: _slow, (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpShort(tester);
    await _expand(tester);

    // The instrumented seam is pointer delivery at the passive table boundary,
    // not an action hook. Review passes `canTakeDiscard: false`, so the
    // discard's detector is built with `onTap: null` and no hook can fire even
    // on a correctly delivered tap — an empty hook trace would prove nothing.
    // Inferring delivery from the card closing would let a barrier pass.
    final delivered = await _captureTrace(tester, () async {
      await tester.tapAt(tester.getCenter(_byTypeName('TableDiscardPile')));
      await tester.pumpAndSettle();
    });

    expect(
      find.byType(AnalysisCoachPanel),
      findsNothing,
      reason: 'an outside tap should collapse the card',
    );
    expect(
      delivered,
      isNotEmpty,
      reason:
          'the tap collapsed the card but never reached the table — this is '
          'the Sprint 06 safeguard, and a barrier would fail exactly here',
    );
  });

  testWidgets('a tap on the South hand is delivered too', timeout: _slow, (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpShort(tester);
    await _expand(tester);

    final delivered = await _captureTrace(tester, () async {
      await tester.tapAt(tester.getCenter(_byTypeName('SouthHandFan')));
      await tester.pumpAndSettle();
    });

    expect(find.byType(AnalysisCoachPanel), findsNothing);
    expect(delivered, isNotEmpty);
  });

  testWidgets('the trace proves delivery without enabling anything', timeout:
      _slow, (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpShort(tester);

    // Passivity is the thing the trace must not have bought its evidence with.
    final playfield = tester.widget<PhysicalTablePlayfield>(
      find.byType(PhysicalTablePlayfield),
    );
    expect(playfield.canDrawStock, isFalse);
    expect(playfield.canTakeDiscard, isFalse);
    expect(playfield.canReturnDiscard, isFalse);
    expect(playfield.canClaimFifty, isFalse);
    expect(playfield.canReturnOpeningMelds, isFalse);
    expect(playfield.isHumanTurn, isFalse);
    expect(playfield.onPlaySelectedMeld, isNull);
  });
}
