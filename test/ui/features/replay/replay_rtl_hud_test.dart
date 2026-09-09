import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/coaching/analysis_coach_settings.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_outcomes.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_replay_record.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_action_transcript.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/features/replay/replay_hud_layout.dart';
import 'package:hareeg_table/ui/features/replay/views/match_replay_screen.dart';
import 'package:hareeg_table/ui/features/replay/widgets/analysis_coach_panel.dart';
import 'package:hareeg_table/ui/features/replay/widgets/review_table_playfield.dart';

import '../../../support/completed_match_fixture.dart';
import '../../../support/max_content_table_fixture.dart';
import '../../../support/test_fixtures.dart';

const _matchId = 'm-screen-aaaaaaaa';
const _slow = Timeout(Duration(minutes: 5));
const _shortSizes = <Size>[Size(844, 390), Size(914, 411), Size(926, 428)];

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

/// The scrub target's tooltip, which carries the full position value.
Tooltip _scrubTooltip(WidgetTester tester) => tester.widget<Tooltip>(
  find
      .descendant(
        of: _byTypeName('ReplayScrubTarget'),
        matching: find.byType(Tooltip),
      )
      .first,
);

Future<void> _pump(
  WidgetTester tester,
  Size size,
  AppStrings strings, {
  bool longMatch = false,
}) async {
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
  );
  await tester.pumpAndSettle(const Duration(seconds: 1));
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

  group('glyph direction is a property of the action, not of the language', () {
    // The round-1 rejection: Material opts `first_page`, `last_page`,
    // `chevron_left` and `chevron_right` into `matchTextDirection`, so Arabic
    // reversed four of the seven timeline glyphs while the two `skip_*` ones
    // stayed put. Reading `IconData` alone cannot catch that — what matters is
    // the direction the glyph actually renders under the ambient
    // `Directionality`, which is what this computes.
    ({bool pointsRight, bool mirrored}) rendered(
      WidgetTester tester,
      String tooltip,
    ) {
      final iconFinder = find.descendant(
        of: find.byTooltip(tooltip),
        matching: find.byType(Icon),
      );
      expect(iconFinder, findsOneWidget, reason: tooltip);
      final icon = tester.widget<Icon>(iconFinder);
      final effective = Directionality.of(tester.element(iconFinder));
      final mirrored =
          (icon.icon!.matchTextDirection) && effective == TextDirection.rtl;
      // How the glyph is drawn before any mirroring.
      const pointsRightInLtr = <int, bool>{
        0xe092: false, // arrow_back
        0xe28b: false, // first_page
        0xe5be: false, // skip_previous
        0xe15e: false, // chevron_left
        0xe15f: true, // chevron_right
        0xe5bd: true, // skip_next
        0xe36b: true, // last_page
      };
      final base = pointsRightInLtr[icon.icon!.codePoint];
      expect(base, isNotNull, reason: 'unmapped glyph for $tooltip');
      return (pointsRight: base! != mirrored, mirrored: mirrored);
    }

    for (final size in _shortSizes) {
      for (final strings in [AppStrings.english, AppStrings.arabic]) {
        testWidgets(
          '$size in ${strings.languageCode}',
          timeout: _slow,
          (tester) async {
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await _pump(tester, size, strings);
            final rtl = strings.textDirection == TextDirection.rtl;

            // Timeline glyphs: physical and chronological in both locales.
            for (final entry in <String, bool>{
              strings.replayFirst: false,
              strings.replayPreviousRound: false,
              strings.replayPrevious: false,
              strings.replayNext: true,
              strings.replayNextRound: true,
              strings.replayLast: true,
            }.entries) {
              final r = rendered(tester, entry.key);
              expect(
                r.pointsRight,
                entry.value,
                reason:
                    '${entry.key} points the wrong way in '
                    '${strings.languageCode} at $size',
              );
              expect(
                r.mirrored,
                isFalse,
                reason: '${entry.key} mirrored with the locale',
              );
            }

            // Back is the one that *should* follow the locale.
            final back = rendered(tester, strings.replayBack);
            expect(
              back.pointsRight,
              rtl,
              reason: 'Back must point the way the reader came from',
            );
          },
        );
      }
    }

    testWidgets('the seam is on the timeline glyphs and not on Back', timeout:
        _slow, (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final strings = AppStrings.arabic;
      await _pump(tester, const Size(844, 390), strings);

      TextDirection dirAt(String tooltip) => Directionality.of(
        tester.element(
          find
              .descendant(
                of: find.byTooltip(tooltip),
                matching: find.byType(Icon),
              )
              .first,
        ),
      );

      // The seam pins the timeline glyphs to LTR even though the app is RTL.
      for (final tooltip in [
        strings.replayFirst,
        strings.replayPrevious,
        strings.replayNext,
        strings.replayLast,
      ]) {
        expect(dirAt(tooltip), TextDirection.ltr, reason: tooltip);
      }
      // And deliberately does not touch Back, or the branch control: both
      // are route navigation rather than moves along the timeline, so both
      // mirror with the language.
      expect(dirAt(strings.replayBack), TextDirection.rtl);
      expect(dirAt(strings.branchStart), TextDirection.rtl);
    });
  });

  group('visible chrome is inset inside an unchanged 44 dp target', () {
    for (final size in _shortSizes) {
      for (final strings in [AppStrings.english, AppStrings.arabic]) {
        testWidgets(
          '$size in ${strings.languageCode}',
          timeout: _slow,
          (tester) async {
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await _pump(tester, size, strings);

            final decision = ReplayHudLayout.resolveFor(
              screen: size,
              safeInsets: EdgeInsets.zero,
            );
            final accepted = decision.rails.permanent;

            // 1. The outer targets are still the exact accepted rectangles.
            final targets = <Element>[
              ..._byTypeName('ReplayRailButton').evaluate(),
              ..._byTypeName('ReplayScrubTarget').evaluate(),
            ].map((e) {
              final box = e.renderObject! as RenderBox;
              return box.localToGlobal(Offset.zero) & box.size;
            }).toList();
            expect(targets, hasLength(10), reason: '$size');
            for (final rect in targets) {
              expect(rect.width, 44, reason: '$size');
              expect(rect.height, 44, reason: '$size');
              expect(
                accepted.any(
                  (a) =>
                      (a.left - rect.left).abs() < 0.01 &&
                      (a.top - rect.top).abs() < 0.01,
                ),
                isTrue,
                reason: '$rect is not an accepted slot at $size',
              );
            }

            // 2. Each visible surface is centred, <=38x38, inset >=3 per side.
            final chromes = <Rect>[];
            for (final target in [
              ..._byTypeName('ReplayRailButton').evaluate(),
              ..._byTypeName('ReplayScrubTarget').evaluate(),
            ]) {
              final outer = (target.renderObject! as RenderBox);
              final outerRect =
                  outer.localToGlobal(Offset.zero) & outer.size;
              final painted = find
                  .descendant(
                    of: find.byWidget(target.widget),
                    matching: find.byType(Container),
                  )
                  .evaluate()
                  .map((e) => e.renderObject)
                  .whereType<RenderBox>()
                  .where((b) => b.hasSize && !b.size.isEmpty)
                  .map((b) => b.localToGlobal(Offset.zero) & b.size)
                  .toList();
              expect(painted, isNotEmpty, reason: 'no chrome at $outerRect');
              final chrome = painted.first;
              chromes.add(chrome);

              expect(chrome.width, lessThanOrEqualTo(38.01), reason: '$size');
              expect(chrome.height, lessThanOrEqualTo(38.01), reason: '$size');
              expect(
                chrome.left - outerRect.left,
                greaterThanOrEqualTo(2.99),
                reason: 'left inset at $size',
              );
              expect(
                outerRect.right - chrome.right,
                greaterThanOrEqualTo(2.99),
                reason: 'right inset at $size',
              );
              expect(
                chrome.top - outerRect.top,
                greaterThanOrEqualTo(2.99),
                reason: 'top inset at $size',
              );
              expect(
                outerRect.bottom - chrome.bottom,
                greaterThanOrEqualTo(2.99),
                reason: 'bottom inset at $size',
              );
              expect(
                chrome.center.dx - outerRect.center.dx,
                closeTo(0, 0.01),
                reason: 'not centred at $size',
              );
              expect(
                chrome.center.dy - outerRect.center.dy,
                closeTo(0, 0.01),
                reason: 'not centred at $size',
              );
            }

            // 3. Visible separation between neighbours in the same column.
            for (var i = 0; i < chromes.length; i++) {
              for (var j = i + 1; j < chromes.length; j++) {
                final a = chromes[i];
                final b = chromes[j];
                final sameColumn = (a.center.dx - b.center.dx).abs() < 1;
                if (!sameColumn) continue;
                final gap = a.top < b.top ? b.top - a.bottom : a.top - b.bottom;
                expect(
                  gap,
                  greaterThanOrEqualTo(5.99),
                  reason: 'only ${gap}dp of visible air at $size',
                );
              }
            }
          },
        );
      }
    }

    testWidgets('Last and the scrub show at least 8 dp at 844x390', timeout:
        _slow, (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // The tightest place in the whole layout: 2 dp of target clearance, and
      // the owner accepted that only on the understanding the chrome would
      // read as separate.
      await _pump(tester, const Size(844, 390), AppStrings.english);

      Rect chromeOf(Finder target) => find
          .descendant(of: target, matching: find.byType(Container))
          .evaluate()
          .map((e) => e.renderObject)
          .whereType<RenderBox>()
          .where((b) => b.hasSize && !b.size.isEmpty)
          .map((b) => b.localToGlobal(Offset.zero) & b.size)
          .first;

      final last = chromeOf(find.byTooltip(AppStrings.english.replayLast));
      final scrub = chromeOf(_byTypeName('ReplayScrubTarget'));
      expect(scrub.top - last.bottom, greaterThanOrEqualTo(7.99));
    });

    // The transparent ring is the whole point of the inset: the chrome shrank
    // but the target did not, so a finger landing in the 3 dp margin must
    // still work the control and must not fall through to the table. Proved
    // for a timeline control *and* the scrub target, at every short size in
    // both locales — the ruling names both, and they are built differently
    // (`ReplayRailButton` versus `ReplayScrubTarget`).
    for (final size in _shortSizes) {
      for (final strings in [AppStrings.english, AppStrings.arabic]) {
        testWidgets(
          'inset-edge taps reach the control at $size in ${strings.languageCode}',
          timeout: _slow,
          (tester) async {
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await _pump(tester, size, strings, longMatch: true);

            String position() => _scrubTooltip(tester).message!;

            Future<List<String>> tapInset(Rect target) async {
              final delivered = <String>[];
              final original = debugPrint;
              debugPrint = (String? message, {int? wrapWidth}) {
                if (message != null &&
                    message.startsWith(PassiveTableInteraction.traceTag)) {
                  delivered.add(message);
                }
              };
              try {
                // 1.5 dp in from the target's left edge: inside the 44 dp
                // target, well outside the 38 dp chrome.
                await tester.tapAt(
                  Offset(target.left + 1.5, target.center.dy),
                );
                await tester.pumpAndSettle();
              } finally {
                debugPrint = original;
              }
              return delivered;
            }

            // A representative enabled timeline control.
            final before = position();
            final stepDelivered = await tapInset(
              tester.getRect(find.byTooltip(strings.replayNext)),
            );
            expect(
              position(),
              isNot(before),
              reason: 'the inset tap on Next step did nothing at $size',
            );
            expect(
              stepDelivered,
              isEmpty,
              reason: 'the Next step inset tap fell through to the table',
            );

            // And the scrub target, which the ruling names separately.
            expect(find.byType(Slider), findsNothing);
            final scrubDelivered = await tapInset(
              tester.getRect(_byTypeName('ReplayScrubTarget')),
            );
            expect(
              find.byType(Slider),
              findsOneWidget,
              reason: 'the inset tap on the scrub target did not open it',
            );
            expect(
              scrubDelivered,
              isEmpty,
              reason: 'the scrub inset tap fell through to the table',
            );
          },
        );
      }
    }
  });

  group('every transport action moves the cursor the right way', () {
    // The owner's rejection was a direction defect, so direction is proved
    // behaviourally as well as visually: each control is driven and the
    // resulting cursor position read back, for all six actions, at every
    // short size, in both locales. A glyph pointing the right way while the
    // action ran backwards would pass the icon test and fail here.
    for (final size in _shortSizes) {
      for (final strings in [AppStrings.english, AppStrings.arabic]) {
        testWidgets(
          '$size in ${strings.languageCode}',
          timeout: _slow,
          (tester) async {
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await _pump(tester, size, strings, longMatch: true);

            /// The cursor index, read from the scrub control's position value.
            int cursor() {
              final message = _scrubTooltip(tester).message!;
              final digits = RegExp(r'\d+').allMatches(message).toList();
              expect(
                digits.length,
                greaterThanOrEqualTo(3),
                reason: 'no position in "$message"',
              );
              // round · step · length
              return int.parse(digits[1].group(0)!);
            }

            Future<int> press(String tooltip) async {
              await tester.tap(find.byTooltip(tooltip));
              await tester.pumpAndSettle();
              return cursor();
            }

            expect(cursor(), 1, reason: 'not at the start');

            final afterNextStep = await press(strings.replayNext);
            expect(afterNextStep, greaterThan(1), reason: 'next step');

            final afterNextRound = await press(strings.replayNextRound);
            expect(
              afterNextRound,
              greaterThan(afterNextStep),
              reason: 'next round did not move forward',
            );

            final afterLast = await press(strings.replayLast);
            expect(
              afterLast,
              greaterThan(afterNextRound),
              reason: 'Last did not reach the end',
            );

            final afterPrevStep = await press(strings.replayPrevious);
            expect(
              afterPrevStep,
              lessThan(afterLast),
              reason: 'previous step did not move backward',
            );

            final afterPrevRound = await press(strings.replayPreviousRound);
            expect(
              afterPrevRound,
              lessThan(afterPrevStep),
              reason: 'previous round did not move backward',
            );

            final afterFirst = await press(strings.replayFirst);
            expect(afterFirst, 1, reason: 'First did not reach the start');
          },
        );
      }
    }
  });

  group('the rails are anchored to physical edges and do not mirror', () {
    for (final size in _shortSizes) {
      testWidgets('$size puts every control in the same place in AR', timeout:
          _slow, (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Mirroring is withdrawn, and this is why: the playfield anchors every
        // seat with non-directional left/right, so the table does not mirror
        // either. The stock pile stays in the bottom-left corner, which leaves
        // the left column four collision-free slots against the transport
        // rail's six. A mirrored rail would have nowhere to go.
        final decision = ReplayHudLayout.resolveFor(
          screen: size,
          safeInsets: EdgeInsets.zero,
        );

        for (final strings in [AppStrings.english, AppStrings.arabic]) {
          await _pump(tester, size, strings);

          final back = tester.getRect(
            find.byTooltip(strings.replayBack),
          );
          final nextStep = tester.getRect(
            find.byTooltip(strings.replayNext),
          );
          final scrub = tester.getRect(_byTypeName('ReplayScrubTarget'));

          expect(back, decision.rails.leading[0], reason: '$size $strings');
          expect(nextStep, decision.rails.trailing[2], reason: '$size');
          expect(scrub, decision.rails.scrub, reason: '$size');
          expect(back.left, 0, reason: 'Back left the physical-left edge');
          expect(
            nextStep.right,
            size.width,
            reason: 'transport left the physical-right edge',
          );
        }
      });
    }
  });

  group('logical behaviour does not mirror with the language', () {
    testWidgets('next advances the timeline in Arabic too', timeout: _slow, (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final strings = AppStrings.arabic;
      await _pump(tester, const Size(844, 390), strings, longMatch: true);

      String position() => _scrubTooltip(tester).message!;

      final start = position();
      await tester.tap(find.byTooltip(strings.replayNext));
      await tester.pumpAndSettle();
      final afterNext = position();
      expect(afterNext, isNot(start));

      await tester.tap(find.byTooltip(strings.replayPrevious));
      await tester.pumpAndSettle();
      expect(position(), start, reason: 'previous did not undo next');
    });
  });

  group('every affordance is labelled in both languages', () {
    for (final strings in [AppStrings.english, AppStrings.arabic]) {
      testWidgets('${strings.languageCode} tooltips and semantics', timeout:
          _slow, (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final handle = tester.ensureSemantics();
        await _pump(tester, const Size(844, 390), strings);

        // A41: the rail is icon-only, so these are the only thing a screen
        // reader has. Every one is localized, and the eight labels are
        // distinct — two controls sharing a label would be unusable even
        // though both are technically "labelled".
        final labels = <String>[
          strings.replayBack,
          strings.replayFirst,
          strings.replayCoachTitle,
          // Appended by the branch control. It is icon-only like the rest, so
          // its label is the only thing a screen reader gets, and it has to be
          // distinct from the other eight for the rail to stay usable.
          strings.branchStart,
          strings.replayPreviousRound,
          strings.replayPrevious,
          strings.replayNext,
          strings.replayNextRound,
          strings.replayLast,
        ];
        expect(labels.toSet(), hasLength(9));

        for (final label in labels) {
          expect(find.byTooltip(label), findsOneWidget, reason: label);
          expect(
            find.bySemanticsLabel(label),
            findsWidgets,
            reason: 'no semantics for $label',
          );
        }

        // A45: the scrub carries the full position value, which is where the
        // withdrawn interactive readout's information went.
        final scrubTooltip = _scrubTooltip(tester);
        expect(scrubTooltip.message, contains(strings.replaySeek));
        expect(scrubTooltip.message!.length, greaterThan(
          strings.replaySeek.length,
        ));

        handle.dispose();
      });
    }

    // Finding a label proves the string is somewhere in the tree. It does not
    // prove the node a screen reader lands on is big enough to hit, or that a
    // disabled control announces itself as disabled. Both are checked at the
    // semantics node itself.
    for (final size in _shortSizes) {
      for (final strings in [AppStrings.english, AppStrings.arabic]) {
        testWidgets(
          'semantics nodes at $size in ${strings.languageCode}',
          timeout: _slow,
          (tester) async {
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            final handle = tester.ensureSemantics();
            // The long match, parked at the first frame: the timeline cannot
            // go back yet but can go forward, so the enabled flag has a real
            // mix to report rather than everything reading the same.
            await _pump(tester, size, strings, longMatch: true);

            // `SemanticsFlags` exposes some members as `bool` and others as
            // `Tristate` depending on the Flutter version, and the two are not
            // comparable. This reads "the flag is set" without depending on
            // which representation this SDK happens to use.
            bool isSet(Object? flag) =>
                flag == true || flag.toString().endsWith('isTrue');

            SemanticsNode nodeFor(String label) {
              final finder = find.bySemanticsLabel(label);
              expect(finder, findsWidgets, reason: 'no semantics for $label');
              return tester.getSemantics(finder.first);
            }

            const expectedEnabled = <String, bool>{
              'back': true,
              'analysis': true,
              // The first frame is mid-match, not decided, so branching is
              // offered. The refused case is asserted separately, against a
              // frame the match was actually won at.
              'branch': true,
              'first': false,
              'previousStep': false,
              'previousRound': false,
              'nextStep': true,
              'nextRound': true,
              'last': true,
            };
            final labels = <String, String>{
              'back': strings.replayBack,
              'analysis': strings.replayCoachTitle,
              'branch': strings.branchStart,
              'first': strings.replayFirst,
              'previousStep': strings.replayPrevious,
              'previousRound': strings.replayPreviousRound,
              'nextStep': strings.replayNext,
              'nextRound': strings.replayNextRound,
              'last': strings.replayLast,
            };

            for (final entry in labels.entries) {
              final node = nodeFor(entry.value);
              final rect = node.rect;

              // The node a screen reader or switch control targets must be at
              // least the 44 dp floor, not merely present.
              expect(
                rect.width,
                greaterThanOrEqualTo(44),
                reason: '${entry.value} semantics node is ${rect.width} wide',
              );
              expect(
                rect.height,
                greaterThanOrEqualTo(44),
                reason: '${entry.value} semantics node is ${rect.height} tall',
              );
              expect(
                isSet(node.flagsCollection.isButton),
                isTrue,
                reason: '${entry.value} is not announced as a button',
              );

              // Enabled state must track the action's real availability. A
              // control that looked greyed out but announced itself enabled
              // would send a screen-reader user at a dead affordance.
              final enabled = isSet(node.flagsCollection.isEnabled);
              expect(
                enabled,
                expectedEnabled[entry.key],
                reason:
                    '${entry.value} reports enabled=$enabled at the first '
                    'frame, where the timeline cannot go back',
              );
            }

            // And the flag has to *track* availability, not be a constant.
            // Stepping forward makes the backward actions reachable.
            await tester.tap(find.byTooltip(strings.replayNext));
            await tester.pumpAndSettle();
            for (final key in const ['first', 'previousStep', 'previousRound']) {
              expect(
                isSet(nodeFor(labels[key]!).flagsCollection.isEnabled),
                isTrue,
                reason:
                    '${labels[key]} still reports disabled after stepping '
                    'forward, so the flag is not tracking availability',
              );
            }

            // The scrub target gets the same three checks as the eight
            // permanent actions — localized label, >=44 bounds, and announced
            // state. It is the one control that is always available, so its
            // enabled flag is asserted true unconditionally rather than
            // against the timeline's position.
            final scrubFinder = find.bySemanticsLabel(
              RegExp(RegExp.escape(strings.replaySeek)),
            );
            expect(
              scrubFinder,
              findsWidgets,
              reason: 'no localized semantics on the scrub target',
            );
            final scrub = tester.getSemantics(scrubFinder.first);

            expect(
              scrub.label,
              contains(strings.replaySeek),
              reason: 'the scrub node lost its localized label',
            );
            expect(
              scrub.label.length,
              greaterThan(strings.replaySeek.length),
              reason: 'the scrub node dropped the position value (A45)',
            );
            expect(
              scrub.rect.width,
              greaterThanOrEqualTo(44),
              reason: 'scrub semantics node is ${scrub.rect.width} wide',
            );
            expect(
              scrub.rect.height,
              greaterThanOrEqualTo(44),
              reason: 'scrub semantics node is ${scrub.rect.height} tall',
            );
            expect(
              isSet(scrub.flagsCollection.isButton),
              isTrue,
              reason: 'the scrub target is not announced as a button',
            );
            expect(
              isSet(scrub.flagsCollection.isEnabled),
              isTrue,
              reason:
                  'the scrub target announced itself disabled; it is the one '
                  'control that is always available',
            );

            handle.dispose();
          },
        );
      }
    }
  });

  group('focus order is explicit, not incidental', () {
    testWidgets('tab walks the leading rail, the trailing rail, then scrub',
        timeout: _slow, (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const size = Size(844, 390);
      // The long match, stepped forward: a disabled IconButton is not
      // focusable, so a single-frame fixture would leave First and Previous
      // out of the traversal and the order would look right for the wrong
      // reason.
      await _pump(tester, size, AppStrings.english, longMatch: true);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byTooltip(AppStrings.english.replayNext));
        await tester.pumpAndSettle();
      }

      final decision = ReplayHudLayout.resolveFor(
        screen: size,
        safeInsets: EdgeInsets.zero,
      );
      final expected = <Rect>[
        ...decision.rails.leading,
        ...decision.rails.trailing,
        decision.rails.scrub!,
      ];

      // Walked with the real focus system rather than read off tree order: an
      // OrderedTraversalPolicy that was never applied would still leave the
      // widgets in the right order in the tree.
      final seen = <Rect>[];
      for (var i = 0; i < 24 && seen.length < expected.length; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        final rect = primaryFocus?.rect;
        if (rect == null) continue;
        if (expected.contains(rect) && !seen.contains(rect)) {
          seen.add(rect);
        }
      }

      expect(seen, expected, reason: 'focus order');
    });
  });

  group('long Arabic copy fits the popover at every short size', () {
    for (final size in _shortSizes) {
      testWidgets('$size renders the card with no clipped glyph', timeout:
          _slow, (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final strings = AppStrings.arabic;
        await _pump(tester, size, strings, longMatch: true);

        // Onto a played move so the coach has real sentences to lay out.
        for (var i = 0; i < 6; i++) {
          await tester.tap(find.byTooltip(strings.replayNext));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byTooltip(strings.replayCoachTitle));
        await tester.pumpAndSettle();
        expect(find.byType(AnalysisCoachPanel), findsOneWidget);

        // A46: measured with TextPainter rather than asserted through
        // find.text. A string that rendered but was clipped to one line would
        // satisfy find.text and still have lost the sentence.
        final texts = find.descendant(
          of: find.byType(AnalysisCoachPanel),
          matching: find.byType(Text),
        );
        expect(texts, findsWidgets);

        for (final element in texts.evaluate()) {
          final data = (element.widget as Text).data;
          if (data == null || data.isEmpty) continue;
          final paragraph = element.renderObject;
          // The resolved span, not the widget's own style: the rendered text
          // inherits from DefaultTextStyle, and re-measuring with only the
          // widget's partial style measures a different string.
          if (paragraph is! RenderParagraph) continue;
          if (!paragraph.hasSize || paragraph.size.isEmpty) continue;

          final painter = TextPainter(
            text: paragraph.text,
            textDirection: paragraph.textDirection,
            maxLines: paragraph.maxLines,
            ellipsis: paragraph.overflow == TextOverflow.ellipsis ? '…' : null,
            textScaler: paragraph.textScaler,
            strutStyle: paragraph.strutStyle,
            textAlign: paragraph.textAlign,
          )..layout(maxWidth: paragraph.size.width);

          expect(
            painter.didExceedMaxLines &&
                paragraph.overflow != TextOverflow.ellipsis,
            isFalse,
            reason: 'clipped: "$data" at $size',
          );
          expect(
            painter.height,
            lessThanOrEqualTo(paragraph.size.height + 0.5),
            reason: 'overflowed: "$data" at $size',
          );
          painter.dispose();
        }

        expect(tester.takeException(), isNull);
      });
    }
  });
}
