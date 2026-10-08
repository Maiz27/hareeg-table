import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/data/persistence/preferences_repository.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_outcomes.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_replay_record.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_action_transcript.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/features/game_table/table_session_config.dart';
import 'package:hareeg_table/ui/features/game_table/views/game_table_screen.dart';
import 'package:hareeg_table/ui/features/game_table/widgets/coach_overlay.dart';
import 'package:hareeg_table/ui/features/game_table/widgets/physical_table_playfield.dart';
import 'package:hareeg_table/ui/features/game_table/widgets/table_background.dart';
import 'package:hareeg_table/ui/features/game_table/widgets/table_hud_capsule.dart';
import 'package:hareeg_table/ui/features/replay/replay_card_layout.dart';
import 'package:hareeg_table/ui/features/replay/views/match_replay_screen.dart';
import 'package:hareeg_table/ui/features/replay/widgets/analysis_coach_panel.dart';
import 'package:hareeg_table/ui/features/replay/widgets/replay_card.dart';
import 'package:hareeg_table/ui/features/replay/widgets/replay_transport.dart';

import '../../../support/completed_match_fixture.dart';
import '../../../support/max_content_table_fixture.dart';
import '../../../support/test_fixtures.dart';

/// The replay's presentation contract (design contract 7.6).
///
/// The replay is the live table plus replay chrome: the same inset table with
/// its stock at the centre and its seat plates, one HUD capsule in the top-end
/// corner (Analysis | Branch | Exit), and one card docked where the live coach
/// card docks, holding the position, the event line, the scrubber, the one
/// transport row and — when switched on — the analysis. Everything here is
/// measured on the rendered tree, on the most crowded table the playfield can
/// draw, so a drift in the card's projection of the table fails here rather
/// than quietly covering a seat.

const _matchId = 'm-layout-aaaaaaaa';
const _slow = Timeout(Duration(minutes: 5));

/// Every contracted size. The last is portrait.
const _landscape = <Size>[
  Size(844, 390),
  Size(640, 360),
  Size(915, 412),
  Size(1280, 800),
  Size(1024, 768),
];
const _portrait = Size(390, 844);

late MatchActionTranscript _crowded;
late MatchActionTranscript _played;

class _History extends MemoryMatchHistoryRepository {
  _History(this._transcript);

  final MatchActionTranscript _transcript;

  @override
  Future<MatchReplayOpenOutcome> openReplay(String matchId) async =>
      MatchReplayOpened(
        MatchReplayRecord(matchId: matchId, transcript: _transcript),
      );
}

Widget _localized(
  Widget home,
  AppStrings strings, {
  double textScale = 1,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: disableAnimations,
      ),
      child: AppStringsScope(
        strings: strings,
        child: Directionality(
          textDirection: strings.textDirection,
          child: child!,
        ),
      ),
    ),
    home: home,
  );
}

Future<void> _pump(
  WidgetTester tester,
  Size size, {
  AppStrings strings = AppStrings.english,
  double textScale = 1,
  bool disableAnimations = false,
  MatchActionTranscript? transcript,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    _localized(
      MatchReplayScreen(
        summary: historySummary(matchId: _matchId),
        historyRepository: _History(transcript ?? _crowded),
        analysisCoach: const AnalysisCoachSettings(
          verbosity: AnalysisVerbosity.narrateAll,
          cardDeathWarnings: true,
        ),
      ),
      strings,
      textScale: textScale,
      disableAnimations: disableAnimations,
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 1));
}

Finder _named(String type) =>
    find.byWidgetPredicate((w) => w.runtimeType.toString() == type);

List<Rect> _rects(WidgetTester tester, Finder finder) =>
    finder.evaluate().map((e) {
      final box = e.renderObject! as RenderBox;
      return box.localToGlobal(Offset.zero) & box.size;
    }).toList();

Rect _rect(WidgetTester tester, Finder finder) => tester.getRect(finder);

/// The surfaces the card may never cover: every seat plate, every opponent
/// rail's cue frame and rail box, the reviewer's hand, and the capsule.
Map<String, List<Rect>> _reserved(WidgetTester tester) => {
  'seat plate': _rects(tester, _named('SeatPlate')),
  'opponent cue frame': _rects(tester, _named('_TurnCueFrame')),
  'side rail': _rects(tester, _named('OpponentSideRail')),
  'south hand': _rects(tester, _named('SouthHandFan')),
  'HUD capsule': _rects(tester, find.byType(TableHudCapsule)),
};

/// Rects that touch only along an edge do not cover each other.
bool _covers(Rect a, Rect b) =>
    a.intersect(b).width > 0.01 && a.intersect(b).height > 0.01;

String _label(Size size, AppStrings strings, double scale) =>
    '${size.width.toInt()}x${size.height.toInt()} '
    '${strings.languageCode} x$scale';

void main() {
  setUpAll(() {
    _crowded = MatchActionTranscript(
      initialSnapshot: maximumContentSnapshot(),
      entries: const [],
    );
    final state = buildCompletedMatch(seed: 13).recorderState;
    _played = MatchActionTranscript(
      initialSnapshot: state.initialSnapshot!,
      entries: state.entries,
    );
  });

  group('the replay table is the live table', () {
    for (final size in _landscape) {
      testWidgets(
        '${size.width.toInt()}x${size.height.toInt()} lays out '
        'inside the rail with the stock at the centre',
        timeout: _slow,
        (tester) async {
          await _pump(tester, size);

          final background = tester.widget<TableBackground>(
            find.byType(TableBackground),
          );
          expect(background.insetChild, isTrue);

          final playfield = tester.widget<PhysicalTablePlayfield>(
            find.byType(PhysicalTablePlayfield),
          );
          expect(playfield.centerStock, isTrue);
          expect(playfield.seatScores, isNotEmpty);

          // Exactly inside the rail, as the live table lays it out.
          final insets = TableBackground.railInsets(size);
          expect(
            _rect(tester, find.byType(PhysicalTablePlayfield)),
            insets.deflateRect(Offset.zero & size),
          );

          // The stock sits beside the discard at the table's centre — not in
          // the bottom-start corner the replay used to keep it in.
          final stock = _rect(tester, _named('TableStockPile'));
          final discard = _rect(tester, _named('TableDiscardPile'));
          expect(stock.center.dy, closeTo(discard.center.dy, 1));
          expect(stock.right, lessThanOrEqualTo(discard.right));
          expect(stock.center.dx, greaterThan(size.width * 0.25));

          // All three opponent plates are on the table.
          expect(_named('SeatPlate'), findsNWidgets(3));
        },
      );
    }

    for (final size in const [Size(844, 390), Size(1280, 800)]) {
      testWidgets(
        '${size.width.toInt()}x${size.height.toInt()} puts every '
        'seat exactly where the live table does',
        timeout: _slow,
        (tester) async {
          // The same position on both surfaces. Equal rectangles are what "the
          // replay looks like the game" means in numbers.
          final snapshot = maximumContentSnapshot();
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            MaterialApp(
              home: GameTableScreen(
                setup: snapshot.setup,
                session: TableSessionConfig.live(
                  matchRepository: MemoryMatchRepository(),
                  historyRepository: MemoryMatchHistoryRepository(),
                ),
                preferences: GamePreferences.defaults(),
                onPreferencesChanged: (_) {},
                initialSnapshot: snapshot,
              ),
            ),
          );
          await tester.pump(const Duration(seconds: 1));
          final live = {
            for (final type in [
              'PhysicalTablePlayfield',
              'SeatPlate',
              'OpponentHandRail',
              'OpponentSideRail',
              'SouthHandFan',
              'TableStockPile',
              'TableDiscardPile',
            ])
              type: _rects(tester, _named(type)),
          };
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 30));

          await _pump(tester, size);
          for (final entry in live.entries) {
            expect(
              _rects(tester, _named(entry.key)),
              entry.value,
              reason:
                  '${entry.key} moved between the live table and the replay',
            );
          }
        },
      );
    }
  });

  group('the HUD capsule', () {
    for (final strings in [AppStrings.english, AppStrings.arabic]) {
      for (final size in [..._landscape, _portrait]) {
        testWidgets(
          '${_label(size, strings, 1)} holds Analysis, Branch and '
          'Exit in the top-end corner',
          timeout: _slow,
          (tester) async {
            await _pump(tester, size, strings: strings);

            final capsule = find.byKey(const ValueKey('replay-hud-capsule'));
            expect(capsule, findsOneWidget);
            expect(tester.widget(capsule), isA<TableHudCapsule>());
            final segments = find.descendant(
              of: capsule,
              matching: find.byType(TableChromeButton),
            );
            expect(segments, findsNWidgets(3));

            // Reading order: Analysis, Branch, Exit.
            final keys = tester
                .widgetList<TableChromeButton>(segments)
                .map((b) => (b.key! as ValueKey<String>).value)
                .toList();
            expect(keys, [
              'replay-analysis-toggle',
              'replay-branch-control',
              'replay-exit',
            ]);
            final xs = [
              for (final key in keys) _rect(tester, find.byKey(ValueKey(key))),
            ].map((r) => r.center.dx).toList();
            final rtl = strings.textDirection == TextDirection.rtl;
            expect(
              rtl
                  ? xs[0] > xs[1] && xs[1] > xs[2]
                  : xs[0] < xs[1] && xs[1] < xs[2],
              isTrue,
              reason: 'segments out of reading order: $xs',
            );

            // Every segment is a full 44 dp target.
            for (final key in keys) {
              final r = _rect(tester, find.byKey(ValueKey(key)));
              expect(r.width, greaterThanOrEqualTo(44 - 1e-6), reason: key);
              expect(r.height, greaterThanOrEqualTo(44 - 1e-6), reason: key);
            }

            // Top-end corner, direction-aware.
            final box = _rect(tester, capsule);
            expect(box.top, lessThan(size.height * 0.15));
            if (rtl) {
              expect(box.left, lessThan(size.width * 0.25));
            } else {
              expect(box.right, greaterThan(size.width * 0.75));
            }
          },
        );
      }
    }

    testWidgets('is the live capsule, segment for segment', timeout: _slow, (
      tester,
    ) async {
      await _pump(tester, const Size(1280, 800));
      final capsule = _rect(
        tester,
        find.byKey(const ValueKey('replay-hud-capsule')),
      );
      final table = _rect(tester, find.byType(PhysicalTablePlayfield));
      final metrics = TableHudMetrics.forViewport(table.width, floor: 44);
      expect(capsule.width, metrics.capsuleWidth(3));
      expect(capsule.height, metrics.buttonSize);
      expect(capsule.top - table.top, metrics.edgeInset);
      expect(table.right - capsule.right, metrics.edgeInset);
    });

    testWidgets(
      'names each segment once, and reports the Analysis switch',
      timeout: _slow,
      (tester) async {
        final handle = tester.ensureSemantics();
        final strings = AppStrings.english;
        await _pump(tester, const Size(844, 390));

        SemanticsData data(String key) =>
            tester.getSemantics(find.byKey(ValueKey(key))).getSemanticsData();

        final analysis = data('replay-analysis-toggle');
        expect(analysis.label, strings.replayCoachTitle);
        expect(analysis.tooltip, isEmpty);
        expect(analysis.flagsCollection.isButton, isTrue);
        expect(analysis.flagsCollection.isToggled, ui.Tristate.isFalse);

        expect(data('replay-branch-control').label, strings.branchStart);
        expect(data('replay-exit').label, strings.replayBack);

        await tester.tap(find.byKey(const ValueKey('replay-analysis-toggle')));
        await tester.pumpAndSettle();
        expect(
          data('replay-analysis-toggle').flagsCollection.isToggled,
          ui.Tristate.isTrue,
        );
        handle.dispose();
      },
    );

    testWidgets('Exit leaves the replay', timeout: _slow, (tester) async {
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MatchReplayScreen(
                    summary: historySummary(matchId: _matchId),
                    historyRepository: _History(_crowded),
                    analysisCoach: AnalysisCoachSettings.defaults(),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.byType(MatchReplayScreen), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('replay-exit')));
      await tester.pumpAndSettle();
      expect(find.byType(MatchReplayScreen), findsNothing);
    });
  });

  group('the card keeps clear of every seat and the hand', () {
    for (final size in _landscape) {
      for (final strings in [AppStrings.english, AppStrings.arabic]) {
        for (final scale in const [1.0, 2.0]) {
          testWidgets(
            '${_label(size, strings, scale)}, analysis closed and '
            'open',
            timeout: _slow,
            (tester) async {
              await _pump(tester, size, strings: strings, textScale: scale);

              for (final open in [false, true]) {
                if (open) {
                  await tester.tap(
                    find.byKey(const ValueKey('replay-analysis-toggle')),
                  );
                  await tester.pumpAndSettle();
                }
                final state = open ? 'open' : 'closed';
                expect(tester.takeException(), isNull, reason: state);

                final card = _rect(
                  tester,
                  find.byKey(const ValueKey('replay-card')),
                );
                final table = _rect(
                  tester,
                  find.byType(PhysicalTablePlayfield),
                );
                expect(
                  table.inflate(0.01).contains(card.topLeft) &&
                      table.inflate(0.01).contains(card.bottomRight),
                  isTrue,
                  reason: 'the card left the playing surface ($state): $card',
                );
                for (final entry in _reserved(tester).entries) {
                  for (final zone in entry.value) {
                    expect(
                      _covers(card, zone),
                      isFalse,
                      reason:
                          'the card ($state) covers a ${entry.key}: '
                          '$card over $zone',
                    );
                  }
                }

                // Transport is always there, whole, at 44 dp, inside the card.
                final buttons = find.byType(ReplayTransportButton);
                expect(buttons, findsNWidgets(6), reason: state);
                for (final button in _rects(tester, buttons)) {
                  expect(button.width, greaterThanOrEqualTo(44 - 1e-6));
                  expect(button.height, greaterThanOrEqualTo(44 - 1e-6));
                  expect(
                    card.inflate(0.01).contains(button.topLeft) &&
                        card.inflate(0.01).contains(button.bottomRight),
                    isTrue,
                    reason: 'a transport control is clipped ($state)',
                  );
                }
                expect(find.byType(Slider), findsOneWidget, reason: state);
                expect(
                  find.byKey(const ValueKey('replay-card-position')),
                  findsOneWidget,
                );
              }
            },
          );
        }
      }
    }

    for (final strings in [AppStrings.english, AppStrings.arabic]) {
      testWidgets(
        'the corner card docks exactly where the coach card does, '
        '${strings.languageCode}',
        timeout: _slow,
        (tester) async {
          const size = Size(1280, 800);
          await _pump(tester, size, strings: strings);
          final table = _rect(tester, find.byType(PhysicalTablePlayfield));
          final card = _rect(tester, find.byKey(const ValueKey('replay-card')));
          final coachStart = CoachOverlay.dockedStartFor(table.size);
          final placement = ReplayCardPlacement.resolve(
            table: table.size,
            direction: strings.textDirection,
            textScaler: TextScaler.noScaling,
          );
          expect(placement.arrangement, ReplayCardArrangement.corner);
          expect(card.top - table.top, CoachOverlay.dockedTopFor(table.size));
          final startInset = strings.textDirection == TextDirection.rtl
              ? table.right - card.right
              : card.left - table.left;
          expect(startInset, greaterThanOrEqualTo(coachStart));
          expect(card.width, lessThanOrEqualTo(CoachOverlay.maxDockedWidth));
        },
      );
    }

    testWidgets(
      'at rest the card keeps off the pot where the table leaves '
      'room',
      timeout: _slow,
      (tester) async {
        for (final size in _landscape) {
          for (final strings in [AppStrings.english, AppStrings.arabic]) {
            await _pump(tester, size, strings: strings);
            final card = _rect(
              tester,
              find.byKey(const ValueKey('replay-card')),
            );
            // The discard's visible cards, not its wider drop zone.
            final discard = _rects(
              tester,
              find.descendant(
                of: _named('TableDiscardPile'),
                matching: _named('HareegCardView'),
              ),
            ).reduce((a, b) => a.expandToInclude(b));
            for (final pile in [
              _rect(tester, _named('TableStockPile')),
              discard,
            ]) {
              expect(
                _covers(card, pile),
                isFalse,
                reason: '${_label(size, strings, 1)} covers the pot at rest',
              );
            }
          }
        }
      },
    );
  });

  group('the transport row', () {
    for (final strings in [AppStrings.english, AppStrings.arabic]) {
      for (final size in [const Size(844, 390), const Size(640, 360)]) {
        testWidgets(
          '${_label(size, strings, 1)} runs start to end, left to '
          'right, with the step pair lit',
          timeout: _slow,
          (tester) async {
            await _pump(tester, size, strings: strings);
            final order = [
              strings.replayFirst,
              strings.replayPreviousRound,
              strings.replayPrevious,
              strings.replayNext,
              strings.replayNextRound,
              strings.replayLast,
            ];
            final xs = [
              for (final label in order)
                _rect(tester, find.byTooltip(label)).center.dx,
            ];
            for (var i = 1; i < xs.length; i++) {
              expect(xs[i], greaterThan(xs[i - 1]), reason: order[i]);
            }
            final buttons = tester
                .widgetList<ReplayTransportButton>(
                  find.byType(ReplayTransportButton),
                )
                .toList();
            expect(buttons.map((b) => b.label), order);
            expect(buttons.map((b) => b.emphasized), [
              false,
              false,
              true,
              true,
              false,
              false,
            ]);

            // The timeline glyphs point the way the timeline runs in both
            // languages.
            for (final glyph in tester.widgetList<ReplayTimelineGlyph>(
              find.byType(ReplayTimelineGlyph),
            )) {
              final element = find
                  .descendant(
                    of: find.byWidget(glyph),
                    matching: find.byType(Icon),
                  )
                  .evaluate()
                  .single;
              expect(Directionality.of(element), TextDirection.ltr);
            }
          },
        );
      }
    }

    testWidgets(
      'every control is labelled and hit where it renders, in both '
      'languages',
      timeout: _slow,
      (tester) async {
        for (final strings in [AppStrings.english, AppStrings.arabic]) {
          final handle = tester.ensureSemantics();
          await _pump(
            tester,
            const Size(844, 390),
            strings: strings,
            transcript: _played,
          );
          for (final label in [
            strings.replayFirst,
            strings.replayPreviousRound,
            strings.replayPrevious,
            strings.replayNext,
            strings.replayNextRound,
            strings.replayLast,
          ]) {
            final button = find.ancestor(
              of: find.byTooltip(label),
              matching: find.byType(ReplayTransportButton),
            );
            expect(button, findsOneWidget, reason: label);
            final data = tester
                .getSemantics(
                  find.descendant(
                    of: button,
                    matching: find.byType(MergeSemantics),
                  ),
                )
                .getSemanticsData();
            expect(data.label, label);
            expect(data.flagsCollection.isButton, isTrue);

            // Nothing sits over the control: a hit at its centre lands in it.
            final center = tester.getCenter(button);
            final result = HitTestResult();
            tester.binding.hitTestInView(result, center, tester.view.viewId);
            final target = button.evaluate().single.renderObject!;
            expect(
              result.path.any((entry) => entry.target == target),
              isTrue,
              reason: '$label is covered',
            );
          }
          expect(find.bySemanticsLabel(strings.replaySeek), findsOneWidget);
          handle.dispose();
        }
      },
    );
  });

  group('analysis opens inside the card', () {
    for (final size in [..._landscape, _portrait]) {
      testWidgets(
        '${size.width.toInt()}x${size.height.toInt()}: one card, '
        'no popover',
        timeout: _slow,
        (tester) async {
          await _pump(tester, size);
          expect(find.byType(AnalysisCoachPanel), findsNothing);
          expect(find.byType(ReplayCard), findsOneWidget);

          final transportBefore = _rects(
            tester,
            find.byType(ReplayTransportButton),
          );
          await tester.tap(
            find.byKey(const ValueKey('replay-analysis-toggle')),
          );
          await tester.pumpAndSettle();

          expect(find.byType(ReplayCard), findsOneWidget);
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('replay-card')),
              matching: find.byType(AnalysisCoachPanel),
            ),
            findsOneWidget,
          );
          expect(find.byType(AnalysisCoachPanel), findsOneWidget);
          // Opening the section never moves a control.
          if (size != _portrait) {
            expect(
              _rects(tester, find.byType(ReplayTransportButton)),
              transportBefore,
            );
          }

          await tester.tap(
            find.byKey(const ValueKey('replay-analysis-toggle')),
          );
          await tester.pumpAndSettle();
          expect(find.byType(AnalysisCoachPanel), findsNothing);
        },
      );
    }

    testWidgets('reduced motion opens it in place', timeout: _slow, (
      tester,
    ) async {
      await _pump(tester, const Size(844, 390), disableAnimations: true);
      expect(
        find.descendant(
          of: find.byType(ReplayCard),
          matching: find.byType(AnimatedSize),
        ),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('replay-analysis-toggle')));
      await tester.pump();
      expect(find.byType(AnalysisCoachPanel), findsOneWidget);
    });
  });

  group('when room runs short', () {
    ReplayCardSections sections(double maxHeight, {bool open = true}) =>
        ReplayCard.sectionsFor(
          arrangement: ReplayCardArrangement.corner,
          width: 300,
          maxHeight: maxHeight,
          narration:
              'A long event line that certainly needs two lines of the card '
              'to say what happened on this move',
          analysisOpen: open,
          textScaler: TextScaler.noScaling,
          textDirection: TextDirection.ltr,
        );

    test('analysis goes first, then the event line, never the transport', () {
      const scaler = TextScaler.noScaling;
      final line = ReplayCardMetrics.narrationLineHeight(scaler);
      final fixed = ReplayCardMetrics.cornerRestingMin(scaler) - line;

      final roomy = sections(fixed + 2 * line + 200);
      expect(roomy.analysis, isTrue);
      expect(roomy.narrationLines, 2);

      // An open section may take the event line's second line...
      final trimmed = sections(
        fixed + line + ReplayCardMetrics.minAnalysisHeight + 1,
      );
      expect(trimmed.analysis, isTrue);
      expect(trimmed.narrationLines, 1);

      // ...but never the whole event line: below that, the section goes.
      final tight = sections(fixed + 2 * line + 10);
      expect(tight.analysis, isFalse, reason: 'analysis collapses first');
      expect(tight.narrationLines, 2);

      final tighter = sections(fixed + line + 1);
      expect(tighter.analysis, isFalse);
      expect(tighter.narrationLines, 1);

      final tightest = sections(fixed);
      expect(tightest.narrationLines, 0);

      // Closed analysis is never shown, however much room there is.
      expect(sections(2000, open: false).analysis, isFalse);
    });

    test('every contracted size places the card clear of the reserved '
        'zones, with the transport row in it', () {
      for (final size in _landscape) {
        for (final direction in TextDirection.values) {
          for (final scale in const [1.0, 2.0]) {
            final table = TableBackground.railInsets(size).deflateSize(size);
            final scaler = TextScaler.linear(scale);
            final placement = ReplayCardPlacement.resolve(
              table: table,
              direction: direction,
              textScaler: scaler,
            );
            final zones = ReplayTableZones.project(table);
            final reason = '$size $direction x$scale';
            for (final zone in [...zones.reserved, placement.capsule]) {
              expect(
                _covers(placement.expandedBounds, zone),
                isFalse,
                reason: '$reason covers $zone',
              );
            }
            expect(
              placement.width,
              greaterThanOrEqualTo(ReplayCardMetrics.rowWidth),
              reason: reason,
            );
            final minimum = placement.arrangement == ReplayCardArrangement.band
                ? ReplayCardMetrics.bandRestingMin(scaler)
                : ReplayCardMetrics.cornerRestingMin(scaler);
            expect(
              placement.restingMaxHeight,
              greaterThanOrEqualTo(minimum),
              reason: reason,
            );
          }
        }
      }
    });

    test('the corner dock is used wherever the row fits beside the north '
        'seat', () {
      ReplayCardArrangement at(Size size) => ReplayCardPlacement.resolve(
        table: TableBackground.railInsets(size).deflateSize(size),
        direction: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      ).arrangement;

      expect(at(const Size(844, 390)), ReplayCardArrangement.corner);
      expect(at(const Size(1024, 768)), ReplayCardArrangement.corner);
      expect(at(const Size(1280, 800)), ReplayCardArrangement.corner);
      // Too little room beside the north seat for six 44 dp targets.
      expect(at(const Size(640, 360)), ReplayCardArrangement.band);
      expect(at(const Size(915, 412)), ReplayCardArrangement.band);
    });
  });

  group('portrait', () {
    for (final strings in [AppStrings.english, AppStrings.arabic]) {
      for (final scale in const [1.0, 2.0]) {
        testWidgets(
          '${_label(_portrait, strings, scale)} docks the card full '
          'width under the table',
          timeout: _slow,
          (tester) async {
            await _pump(tester, _portrait, strings: strings, textScale: scale);
            expect(tester.takeException(), isNull);

            final background = _rect(tester, find.byType(TableBackground));
            final card = _rect(
              tester,
              find.byKey(const ValueKey('replay-card')),
            );
            final capsule = _rect(
              tester,
              find.byKey(const ValueKey('replay-hud-capsule')),
            );
            expect(
              tester
                  .widget<TableBackground>(find.byType(TableBackground))
                  .insetChild,
              isTrue,
            );
            expect(card.top, greaterThanOrEqualTo(background.bottom));
            expect(card.width, greaterThanOrEqualTo(_portrait.width - 16.01));
            expect(capsule.bottom, lessThanOrEqualTo(background.top));
            expect(find.byType(ReplayTransportButton), findsNWidgets(6));
            for (final button in _rects(
              tester,
              find.byType(ReplayTransportButton),
            )) {
              expect(button.width, greaterThanOrEqualTo(44 - 1e-6));
              expect(card.contains(button.center), isTrue);
            }
          },
        );
      }
    }
  });

  group('every action moves the timeline the right way', () {
    for (final strings in [AppStrings.english, AppStrings.arabic]) {
      for (final size in [const Size(844, 390), const Size(640, 360)]) {
        testWidgets(_label(size, strings, 1), timeout: _slow, (tester) async {
          await _pump(tester, size, strings: strings, transcript: _played);

          int position() {
            final text = tester
                .widget<Text>(
                  find.byKey(const ValueKey('replay-card-position')),
                )
                .data!;
            // "Round r · s of n": the step is the second number.
            return int.parse(RegExp(r'\d+').allMatches(text).elementAt(1)[0]!);
          }

          Future<void> press(String label) async {
            await tester.tap(find.byTooltip(label));
            await tester.pumpAndSettle();
          }

          expect(position(), 1);
          await press(strings.replayNext);
          expect(position(), 2);
          await press(strings.replayNext);
          expect(position(), 3);
          await press(strings.replayPrevious);
          expect(position(), 2);
          await press(strings.replayNextRound);
          final roundStart = position();
          expect(roundStart, greaterThan(2));
          await press(strings.replayPreviousRound);
          expect(position(), lessThan(roundStart));
          await press(strings.replayLast);
          final last = position();
          expect(last, greaterThan(roundStart));
          await press(strings.replayFirst);
          expect(position(), 1);

          // Dragging the scrubber to its far end reaches the end too.
          await tester.drag(find.byType(Slider), const Offset(2000, 0));
          await tester.pumpAndSettle();
          expect(position(), last);
        });
      }
    }
  });
}
