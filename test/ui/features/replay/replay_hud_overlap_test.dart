import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/coaching/analysis_coach_settings.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_outcomes.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_replay_record.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_action_transcript.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/features/replay/replay_hud_layout.dart';
import 'package:hareeg_table/ui/features/replay/views/match_replay_screen.dart';

import '../../../support/max_content_table_fixture.dart';
import '../../../support/test_fixtures.dart';

const _matchId = 'm-screen-aaaaaaaa';
const _slow = Timeout(Duration(minutes: 5));

/// Every short size the contract names.
const _shortSizes = <Size>[
  Size(844, 390),
  Size(914, 411),
  Size(926, 428),
];

/// The HUD's **permanent** surfaces: eight rail affordances and the scrub.
///
/// The progress hairline is deliberately excluded: A18 keeps it full width
/// because it is visual only and absorbs nothing, so it may span the hand. What
/// must never cover protected content is the parts that take a touch.
const _permanentHud = <String>{'ReplayRailButton', 'ReplayScrubTarget'};

/// Content a permanent HUD rectangle may never sit on top of.
///
/// Opponent rails are absent by design and checked separately at their cards:
/// `OpponentHandRail` is a full-width row that paints its cards centred inside
/// it, and `OpponentSideRail` is a 56 dp box holding a 32 dp stack. Comparing
/// against those containers asks whether the HUD intersects empty alignment
/// space, which is a different — and unanswerable — question from whether it
/// hides a card.
const _protected = <String>{
  'TableStockPile',
  'TableDiscardPile',
  'SouthHandFan',
  'SeatMeldLane',
};

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

Future<void> _pumpShort(
  WidgetTester tester,
  Size size,
  AppStrings strings,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();

  await tester.pumpWidget(
    MaterialApp(
      home: AppStringsScope(
        strings: strings,
        child: Directionality(
          textDirection: strings.textDirection,
          child: MatchReplayScreen(
            summary: historySummary(matchId: _matchId),
            historyRepository: _StaticHistoryRepository(_transcript),
            // The loudest setting: the most the coach will ever have to say,
            // which is when its surface is largest.
            analysisCoach: const AnalysisCoachSettings(
              verbosity: AnalysisVerbosity.narrateAll,
              cardDeathWarnings: true,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 1));
}

List<Rect> _rects(WidgetTester tester, Set<String> names) {
  final found = <Rect>[];
  for (final name in names) {
    for (final element in _byTypeName(name).evaluate()) {
      final renderObject = element.renderObject;
      if (renderObject is RenderBox &&
          renderObject.attached &&
          renderObject.hasSize &&
          !renderObject.size.isEmpty) {
        found.add(
          renderObject.localToGlobal(Offset.zero) & renderObject.size,
        );
      }
    }
  }
  return found;
}

List<Rect> _renderedCards(WidgetTester tester) {
  final cards = <Rect>[];
  for (final element in find
      .byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> && key.value.contains('-deck-');
      })
      .evaluate()) {
    final renderObject = element.renderObject;
    if (renderObject is RenderBox &&
        renderObject.attached &&
        renderObject.hasSize &&
        !renderObject.size.isEmpty) {
      cards.add(renderObject.localToGlobal(Offset.zero) & renderObject.size);
    }
  }
  return cards;
}

void main() {
  setUpAll(() {
    // A32's stress fixture, handed to the screen as the whole transcript. The
    // previous fixture stepped a natural match forty frames, which never
    // reaches the visible card cap on any rail — the geometry that broke the
    // withdrawn horizontal HUD only exists on a maximally crowded table.
    _transcript = MatchActionTranscript(
      initialSnapshot: maximumContentSnapshot(),
      entries: const [],
    );
  });

  group('no permanent HUD surface covers protected table content', () {
    for (final size in _shortSizes) {
      for (final strings in [AppStrings.english, AppStrings.arabic]) {
        testWidgets(
          '$size in ${strings.languageCode}',
          timeout: _slow,
          (tester) async {
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await _pumpShort(tester, size, strings);

            final hud = _rects(tester, _permanentHud);
            final protected = _rects(tester, _protected);

            expect(hud, hasLength(10), reason: 'wrong HUD inventory at $size');
            expect(protected, isNotEmpty, reason: 'no table rendered at $size');

            // Read from the rendered tree, never assumed from source
            // arithmetic — the projection is routing input only and has no
            // business in an overlap claim.
            for (final pod in hud) {
              for (final content in protected) {
                expect(
                  pod.overlaps(content),
                  isFalse,
                  reason: 'HUD $pod covers table content $content at $size',
                );
              }
            }
          },
        );
      }
    }
  });

  group('no permanent HUD surface covers a rendered card', () {
    // A30's intent, measured at the cards themselves rather than at the layout
    // box that holds them. This is the assertion that actually protects an
    // opponent's card count, and the one the withdrawn corner clusters failed.
    for (final size in _shortSizes) {
      for (final strings in [AppStrings.english, AppStrings.arabic]) {
        testWidgets(
          '$size in ${strings.languageCode}',
          timeout: _slow,
          (tester) async {
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await _pumpShort(tester, size, strings);

            final cards = _renderedCards(tester);
            expect(cards, isNotEmpty, reason: 'no cards rendered at $size');

            for (final pod in _rects(tester, _permanentHud)) {
              for (final card in cards) {
                expect(
                  pod.overlaps(card),
                  isFalse,
                  reason: 'HUD $pod covers card $card at $size',
                );
              }
            }
          },
        );
      }
    }
  });

  group('the branch control clears every rendered card surface', () {
    // Appended for the fourth leading slot. The two groups above would already
    // fail if it covered something — it is one of the ten permanent rects they
    // sweep — but a sweep that says "one of ten overlaps" is not the same
    // evidence as "this control, the one this sprint added, is clear". Naming
    // it is what makes a regression in *this* rectangle legible.
    for (final size in _shortSizes) {
      for (final strings in [AppStrings.english, AppStrings.arabic]) {
        testWidgets(
          '$size in ${strings.languageCode}',
          timeout: _slow,
          (tester) async {
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await _pumpShort(tester, size, strings);

            final branch = find.byKey(
              const ValueKey('replay-branch-control'),
            );
            expect(branch, findsOneWidget, reason: 'no branch control at $size');
            final box = tester.renderObject<RenderBox>(branch);
            final rect =
                box.localToGlobal(Offset.zero) & box.size;

            // Maximum-content fixture, actual card surfaces — not the rail
            // containers that hold them.
            final cards = _renderedCards(tester);
            expect(cards, isNotEmpty, reason: 'no cards rendered at $size');
            for (final card in cards) {
              expect(
                rect.overlaps(card),
                isFalse,
                reason: 'the branch control $rect covers card $card at $size',
              );
            }
            for (final content in _rects(tester, _protected)) {
              expect(
                rect.overlaps(content),
                isFalse,
                reason:
                    'the branch control $rect covers $content at $size',
              );
            }
          },
        );
      }
    }
  });

  group('the rendered HUD sits exactly where the collision map put it', () {
    for (final size in _shortSizes) {
      for (final strings in [AppStrings.english, AppStrings.arabic]) {
        testWidgets(
          '$size in ${strings.languageCode}',
          timeout: _slow,
          (tester) async {
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await _pumpShort(tester, size, strings);

            final decision = ReplayHudLayout.resolveFor(
              screen: size,
              safeInsets: EdgeInsets.zero,
            );
            final expected = decision.rails.permanent
                .map((r) => '${r.left},${r.top},${r.right},${r.bottom}')
                .toList()
              ..sort();
            final actual = _rects(tester, _permanentHud)
                .map((r) => '${r.left},${r.top},${r.right},${r.bottom}')
                .toList()
              ..sort();

            // One geometry input, one placement. If these ever disagree the
            // guard is clearing rectangles the HUD does not use.
            expect(actual, expected, reason: 'at $size');
          },
        );
      }
    }
  });

  group('the rails do not mirror, and the table does not either', () {
    for (final size in _shortSizes) {
      testWidgets('$size renders identical rects in EN and AR', timeout: _slow, (
        tester,
      ) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await _pumpShort(tester, size, AppStrings.english);
        final english = _rects(tester, _permanentHud).map((r) => r.toString())
          ..toList();

        await _pumpShort(tester, size, AppStrings.arabic);
        final arabic = _rects(tester, _permanentHud).map((r) => r.toString())
          ..toList();

        // The playfield anchors every seat with non-directional left/right, so
        // the stock stays in the bottom-left corner under RTL and the left
        // column is two slots short of the transport rail. Mirroring the rails
        // would put six controls in a four-slot column.
        expect(arabic.toList()..sort(), english.toList()..sort());
      });
    }
  });

  group('the table stays reachable underneath the HUD', () {
    for (final size in _shortSizes) {
      testWidgets(
        'discard and south hand are hit-testable at $size',
        timeout: _slow,
        (tester) async {
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await _pumpShort(tester, size, AppStrings.english);

          // Sprint 06's branch-and-play sandbox depends on exactly this: the
          // cards must still receive a touch with the HUD present, or the
          // sandbox has nothing to attach to.
          expect(
            _byTypeName('TableDiscardPile').hitTestable(),
            findsWidgets,
            reason: 'the discard pile is buried at $size',
          );
          expect(
            _byTypeName('SouthHandFan').hitTestable(),
            findsWidgets,
            reason: 'the south hand is buried at $size',
          );
        },
      );
    }
  });

  group('the expanded popover covers only what the owner released', () {
    for (final size in _shortSizes) {
      for (final strings in [AppStrings.english, AppStrings.arabic]) {
        testWidgets(
          '$size in ${strings.languageCode}',
          timeout: _slow,
          (tester) async {
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await _pumpShort(tester, size, strings);
            await tester.tap(find.byTooltip(strings.replayCoachTitle));
            await tester.pumpAndSettle();

            final card = tester.getRect(_byTypeName('ReviewAnalysisCard'));
            final decision = ReplayHudLayout.resolveFor(
              screen: size,
              safeInsets: EdgeInsets.zero,
            );

            // Opponent rail cards and the west meld lane are the whole of the
            // exception. Everything else stays inviolable while it is open.
            for (final blocked in decision.geometry.popoverBlockers) {
              expect(
                card.overlaps(blocked),
                isFalse,
                reason: 'the popover covers $blocked at $size',
              );
            }

            // And the permanent HUD is still where it was: opening the card
            // must not move a control onto something.
            for (final pod in _rects(tester, _permanentHud)) {
              for (final content in _rects(tester, _protected)) {
                expect(pod.overlaps(content), isFalse, reason: 'at $size');
              }
            }
          },
        );
      }
    }
  });

  group('the scrub target and the hand do not steal each other taps', () {
    testWidgets('a tap on the hand does not open the scrubber', timeout: _slow, (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpShort(tester, const Size(844, 390), AppStrings.english);

      final handCentre = tester.getCenter(_byTypeName('SouthHandFan'));
      await tester.tapAt(handCentre);
      await tester.pumpAndSettle();

      expect(
        find.byType(Slider),
        findsNothing,
        reason: 'the hand centre must reach the hand, not the scrub',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tap on the scrub target opens the scrubber', timeout: _slow, (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpShort(tester, const Size(844, 390), AppStrings.english);

      final target = _byTypeName('ReplayScrubTarget');
      expect(
        target,
        findsOneWidget,
        reason: 'the collision map promised exactly one usable segment',
      );

      await tester.tap(target);
      await tester.pumpAndSettle();

      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets(
      'Last and the scrub are distinct targets at their tightest separation',
      timeout: _slow,
      (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // 844x390 leaves 2 dp between them, which the owner accepted. Two
        // adjacent 44 dp targets that route to the same place would be the
        // real defect, so this taps each centre and checks they differ.
        await _pumpShort(tester, const Size(844, 390), AppStrings.english);

        await tester.tap(find.byTooltip(AppStrings.english.replayLast));
        await tester.pumpAndSettle();
        expect(
          find.byType(Slider),
          findsNothing,
          reason: 'Last must not open the scrubber',
        );

        await tester.tap(_byTypeName('ReplayScrubTarget'));
        await tester.pumpAndSettle();
        expect(find.byType(Slider), findsOneWidget);
      },
    );
  });
}
