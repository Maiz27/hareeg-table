import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/coaching/analysis_coach_settings.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_outcomes.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_replay_record.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_action_transcript.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/features/replay/replay_hud_layout.dart';
import 'package:hareeg_table/ui/features/replay/views/match_replay_screen.dart';
import 'package:hareeg_table/ui/features/replay/widgets/replay_scrub_bar.dart';
import 'package:hareeg_table/ui/features/replay/widgets/review_table_playfield.dart';

import '../../../support/completed_match_fixture.dart';
import '../../../support/max_content_table_fixture.dart';
import '../../../support/test_fixtures.dart';

/// A29's own proof.
///
/// The expanded scrubber is grandfathered by the scrubber-precedence ruling as
/// a transient overlay, but its **rectangle** is not: while open it may cover
/// the rendered `SouthHandFan` and the trailing-drop target inside it, and
/// nothing else at all. The previous full-width bottom band crossed the stock,
/// both side meld lanes, Last and the permanent scrub target.
///
/// Nothing here relaxes Correction 02's permanent-HUD geometry checks; those
/// live in `replay_hud_overlap_test.dart` and still run against the permanent
/// inventory only.

const _matchId = 'm-screen-aaaaaaaa';
const _slow = Timeout(Duration(minutes: 5));

const _shortSizes = <Size>[Size(844, 390), Size(914, 411), Size(926, 428)];

/// The two contracted short safe-inset vectors.
const _insetCases = <String, EdgeInsets>{
  'S1 left:47': EdgeInsets.only(left: 47),
  'S2 right:47': EdgeInsets.only(right: 47),
};

late MatchActionTranscript _maxContent;
late MatchActionTranscript _longMatch;

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

Future<void> _pump(
  WidgetTester tester,
  Size screen,
  AppStrings strings, {
  EdgeInsets insets = EdgeInsets.zero,
  bool longMatch = false,
}) async {
  tester.view.physicalSize = screen;
  tester.view.devicePixelRatio = 1.0;

  // A fresh tree per case. RenderFlex reports a given overflow once per render
  // object, so a reused tree reports later sizes as clean when they are not.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();

  await tester.pumpWidget(
    MaterialApp(
      home: AppStringsScope(
        strings: strings,
        child: Directionality(
          textDirection: strings.textDirection,
          child: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(padding: insets),
              child: MatchReplayScreen(
                summary: historySummary(matchId: _matchId),
                historyRepository: _StaticHistoryRepository(
                  longMatch ? _longMatch : _maxContent,
                ),
                analysisCoach: const AnalysisCoachSettings(
                  verbosity: AnalysisVerbosity.narrateAll,
                  cardDeathWarnings: true,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 1));
}

Rect _rect(WidgetTester tester, Finder finder) => tester.getRect(finder);

List<Rect> _rects(WidgetTester tester, String typeName) => _byTypeName(typeName)
    .evaluate()
    .map((element) {
      final box = element.renderObject! as RenderBox;
      return box.localToGlobal(Offset.zero) & box.size;
    })
    .toList();

List<Rect> _renderedCards(WidgetTester tester) => find
    .byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.contains('-deck-');
    })
    .evaluate()
    .map((element) {
      final box = element.renderObject! as RenderBox;
      return box.localToGlobal(Offset.zero) & box.size;
    })
    .where((rect) => !rect.isEmpty)
    .toList();

/// Opens the transient scrubber from the one permanent seek affordance.
Future<void> _open(WidgetTester tester) async {
  await tester.tap(_byTypeName('ReplayScrubTarget'));
  await tester.pumpAndSettle();
  expect(find.byType(Slider), findsOneWidget);
}

void main() {
  setUpAll(() {
    _maxContent = MatchActionTranscript(
      initialSnapshot: maximumContentSnapshot(),
      entries: const [],
    );
    final state = buildCompletedMatch(seed: 13).recorderState;
    _longMatch = MatchActionTranscript(
      initialSnapshot: state.initialSnapshot!,
      entries: state.entries,
    );
  });

  group('the permitted band exists and is derived, not chosen', () {
    for (final screen in _shortSizes) {
      test('$screen', () {
        final decision = ReplayHudLayout.resolveFor(
          screen: screen,
          safeInsets: EdgeInsets.zero,
        );
        final band = decision.rails.scrubOverlay!;
        final geometry = decision.geometry;

        // Bottom-anchored to the hand it is allowed to cover, capped at 64.
        expect(band.bottom, geometry.southHand.bottom, reason: '$screen');
        expect(band.height, lessThanOrEqualTo(64), reason: '$screen');
        expect(band.height, greaterThanOrEqualTo(44), reason: '$screen');

        // Inside the one surface the exception names.
        expect(geometry.southHand.contains(band.topLeft), isTrue);
        expect(geometry.southHand.contains(band.bottomRight - const Offset(0.01, 0.01)), isTrue);

        for (final blocked in <Rect>[
          geometry.stock,
          geometry.discardHit,
          geometry.northMeldLane,
          geometry.westMeldLane,
          geometry.eastMeldLane,
          geometry.southMeldLane,
          geometry.northCards,
          geometry.westCards,
          geometry.eastCards,
          decision.rails.popover!,
          ...decision.rails.permanent,
        ]) {
          expect(
            band.overlaps(blocked),
            isFalse,
            reason: '$band covers $blocked at $screen',
          );
        }
      });
    }

    for (final entry in _insetCases.entries) {
      test('${entry.key} keeps a permitted band', () {
        final decision = ReplayHudLayout.resolveFor(
          screen: const Size(844, 390),
          safeInsets: entry.value,
        );
        expect(decision.mode, ReplayLayoutMode.short);
        final band = decision.rails.scrubOverlay!;
        expect(band.bottom, decision.geometry.southHand.bottom);
        expect(band.height, lessThanOrEqualTo(64));
        for (final blocked in <Rect>[
          decision.geometry.stock,
          decision.geometry.westMeldLane,
          decision.geometry.eastMeldLane,
          decision.geometry.southMeldLane,
          ...decision.rails.permanent,
        ]) {
          expect(band.overlaps(blocked), isFalse, reason: entry.key);
        }
      });
    }

    test('a body with no permitted band is refused, never widened', () {
      // The guard's failure mode has to be "docked", not "cover the stock".
      final decision = ReplayHudLayout.resolveFor(
        screen: const Size(844, 390),
        safeInsets: const EdgeInsets.only(top: 47),
      );
      expect(decision.mode, ReplayLayoutMode.docked);
    });
  });

  group('the open overlay covers the South hand and nothing else', () {
    final cases = <String, ({Size screen, EdgeInsets insets})>{
      for (final size in _shortSizes)
        '$size': (screen: size, insets: EdgeInsets.zero),
      for (final entry in _insetCases.entries)
        entry.key: (screen: const Size(844, 390), insets: entry.value),
    };

    for (final entry in cases.entries) {
      for (final strings in [AppStrings.english, AppStrings.arabic]) {
        testWidgets(
          '${entry.key} in ${strings.languageCode}',
          timeout: _slow,
          (tester) async {
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await _pump(
              tester,
              entry.value.screen,
              strings,
              insets: entry.value.insets,
            );
            await _open(tester);

            final overlay = _rect(tester, find.byType(ReplayScrubOverlay));
            final hand = _rect(tester, _byTypeName('SouthHandFan'));

            // Read from the rendered tree, not from the projection.
            expect(overlay.height, lessThanOrEqualTo(64.01));
            expect(overlay.bottom, closeTo(hand.bottom, 0.01));
            expect(
              hand.contains(overlay.topLeft) &&
                  hand.contains(
                    overlay.bottomRight - const Offset(0.01, 0.01),
                  ),
              isTrue,
              reason: 'overlay $overlay escaped the hand $hand',
            );

            final forbidden = <String, List<Rect>>{
              'stock': _rects(tester, 'TableStockPile'),
              'discard': _rects(tester, 'TableDiscardPile'),
              'meld lane': _rects(tester, 'SeatMeldLane'),
              'permanent rail': _rects(tester, 'ReplayRailButton'),
              'permanent scrub': _rects(tester, 'ReplayScrubTarget'),
              'analysis popover': _rects(tester, 'ReviewAnalysisCard'),
            };
            for (final group in forbidden.entries) {
              for (final rect in group.value) {
                expect(
                  overlay.overlaps(rect),
                  isFalse,
                  reason: 'overlay covers ${group.key} $rect at ${entry.key}',
                );
              }
            }

            // Opponent cards are checked at the cards, never the rail box. The
            // hand's own cards are inside the permitted rectangle, so they are
            // excluded from this sweep by the hand test above.
            for (final card in _renderedCards(tester)) {
              if (hand.overlaps(card)) continue;
              expect(
                overlay.overlaps(card),
                isFalse,
                reason: 'overlay covers card $card at ${entry.key}',
              );
            }
          },
        );
      }
    }

    testWidgets('the trailing-drop target it may cover is inside the hand',
        timeout: _slow, (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pump(tester, const Size(844, 390), AppStrings.english);
      await _open(tester);

      final hand = _rect(tester, _byTypeName('SouthHandFan'));
      final target = find.byKey(
        const ValueKey('south-hand-trailing-drop-target'),
      );
      expect(target, findsOneWidget);
      final drop = tester.getRect(target);

      // The ruling permits covering this target only where it lies inside the
      // hand. If it ever escaped the hand the permission would not extend to
      // the part outside, so that is what is asserted.
      expect(hand.contains(drop.topLeft), isTrue);
      expect(
        hand.contains(drop.bottomRight - const Offset(0.01, 0.01)),
        isTrue,
      );
    });
  });

  group('opening it changes nothing structural', () {
    testWidgets('the table does not relayout', timeout: _slow, (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pump(tester, const Size(844, 390), AppStrings.english);
      final before = _rect(tester, find.byType(ReviewTablePlayfield));

      await _open(tester);
      expect(_rect(tester, find.byType(ReviewTablePlayfield)), before);
    });

    testWidgets('the permanent scrub is reachable before and after', timeout:
        _slow, (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pump(tester, const Size(844, 390), AppStrings.english);
      final target = _byTypeName('ReplayScrubTarget');
      expect(target.hitTestable(), findsOneWidget);
      final rect = _rect(tester, target);

      await _open(tester);
      // Still exactly one permanent seek affordance: the slider is a
      // presentation of it, not a second one.
      expect(target, findsOneWidget);
      expect(_rect(tester, target), rect);

      await tester.tap(find.byTooltip(AppStrings.english.replayNext));
      await tester.pumpAndSettle();
      expect(target.hitTestable(), findsOneWidget);
      expect(_rect(tester, target), rect);
    });

    testWidgets('the hairline stays inert and full width', timeout: _slow, (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pump(tester, const Size(844, 390), AppStrings.english);

      final hairline = find.byType(ReplayProgressHairline);
      expect(hairline, findsOneWidget);
      expect(_rect(tester, hairline).width, 844);
      // Visual only: it spans the hand, so it must absorb nothing.
      expect(
        find.descendant(of: hairline, matching: find.byType(IgnorePointer)),
        findsOneWidget,
      );
      expect(hairline.hitTestable(), findsNothing);
    });
  });

  group('it drives the one seek path', () {
    testWidgets('the slider moves the cursor through onSeek', timeout: _slow, (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pump(
        tester,
        const Size(844, 390),
        AppStrings.english,
        longMatch: true,
      );

      String position() => tester
          .widget<Tooltip>(
            find
                .descendant(
                  of: _byTypeName('ReplayScrubTarget'),
                  matching: find.byType(Tooltip),
                )
                .first,
          )
          .message!;

      final before = position();
      await _open(tester);

      await tester.drag(find.byType(Slider), const Offset(120, 0));
      await tester.pumpAndSettle();

      expect(
        position(),
        isNot(before),
        reason: 'the slider did not move the cursor',
      );
    });
  });

  group('the focus lifecycle, both halves', () {
    testWidgets('release dismisses when nothing holds focus', timeout: _slow, (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pump(
        tester,
        const Size(844, 390),
        AppStrings.english,
        longMatch: true,
      );
      await _open(tester);

      final node = Focus.of(tester.element(find.byType(Slider)));
      node.unfocus();
      await tester.pumpAndSettle();

      await tester.drag(find.byType(Slider), const Offset(60, 0));
      await tester.pumpAndSettle();

      if (find.byType(Slider).evaluate().isNotEmpty) {
        // Some pointer paths give the slider focus on drag; in that case the
        // hold is legitimate and focus leaving must be what closes it.
        expect(node.hasFocus, isTrue, reason: 'open with no focus holding it');
        node.unfocus();
        await tester.pumpAndSettle();
      }
      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('focus holds it open, and losing focus closes it', timeout:
        _slow, (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pump(
        tester,
        const Size(844, 390),
        AppStrings.english,
        longMatch: true,
      );
      await _open(tester);

      final node = Focus.of(tester.element(find.byType(Slider)));
      node.requestFocus();
      await tester.pumpAndSettle();
      expect(node.hasFocus, isTrue);

      // Operated with focus parked inside: a focus user must not be thrown out
      // of the control they are still using.
      await tester.drag(find.byType(Slider), const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(
        find.byType(Slider),
        findsOneWidget,
        reason: 'release threw a focus user out mid-seek',
      );

      // And the other half, which was missing: when that focus leaves, the
      // overlay closes rather than sitting on the hand for good.
      node.unfocus();
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsNothing);
    });
  });

  group('it is labelled and operable in both languages', () {
    for (final strings in [AppStrings.english, AppStrings.arabic]) {
      testWidgets(strings.languageCode, timeout: _slow, (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final handle = tester.ensureSemantics();
        await _pump(tester, const Size(844, 390), strings);
        await _open(tester);

        expect(
          find.bySemanticsLabel(strings.replaySeek),
          findsWidgets,
          reason: 'no localized semantics on the expanded scrubber',
        );
        expect(
          find.descendant(
            of: find.byType(ReplayScrubOverlay),
            matching: find.byTooltip(strings.replaySeek),
          ),
          findsOneWidget,
        );

        final slider = tester.getRect(find.byType(Slider));
        expect(slider.height, greaterThanOrEqualTo(44));
        expect(slider.width, greaterThanOrEqualTo(44));

        handle.dispose();
      });
    }
  });
}
