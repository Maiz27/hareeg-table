import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/coaching/analysis_coach_settings.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_history_outcomes.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_replay_record.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_action_transcript.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/features/replay/views/match_replay_screen.dart';
import 'package:hareeg_table/ui/features/replay/widgets/analysis_coach_panel.dart';

import '../../../support/completed_match_fixture.dart';
import '../../../support/test_fixtures.dart';

const _matchId = 'm-screen-aaaaaaaa';
const _slow = Timeout(Duration(minutes: 5));

const _oraclePath = 'test/ui/features/replay/docked_layout_oracle.json';
const _panelPath =
    'lib/ui/features/replay/widgets/analysis_coach_panel.dart';

/// The digest of the pre-edit oracle, fixed by Amendment 01.
///
/// This is the one value that makes the whole comparison meaningful: the
/// failure being guarded against is the fixture being regenerated from repaired
/// code, which leaves the path, the size and `git status` all looking correct.
const _oracleSha =
    '4b99a5e895c6912f9f44eed9a29c341f270aed0896b7d30d98fb445d4e61a1a8';

const _trackedTypes = <String>{
  'ReviewTablePlayfield',
  'ReplayReviewControls',
  'ReviewAnalysisRegion',
  'PhysicalTablePlayfield',
  'SouthHandFan',
  'SouthSideControls',
  'TableDiscardPile',
  'TableStockPile',
  'OpponentHandRail',
  'OpponentSideRail',
  'SeatMeldLane',
  'AppBar',
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

double _round(double value) => (value * 100).roundToDouble() / 100;

bool _isCardKey(String key) => key.contains('-deck-');

/// Renders the replay screen at [size] in [strings]' language, on a tree that
/// has never rendered at another size.
///
/// The fresh tree is load-bearing, not tidiness. `RenderFlex` reports a given
/// overflow only once per render-object instance, so reusing one tree across
/// sizes makes every size after the first look clean. That defect produced a
/// false "320x568 is clean" reading while the oracle was being generated, and
/// it would silently defeat this whole file.
Future<void> _pumpAt(
  WidgetTester tester,
  Size size, {
  AppStrings? strings,
  AnalysisCoachSettings? settings,
}) async {
  final language = strings ?? AppStrings.english;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();

  await tester.pumpWidget(
    MaterialApp(
      home: AppStringsScope(
        strings: language,
        child: Directionality(
          textDirection: language.textDirection,
          child: MatchReplayScreen(
            summary: historySummary(matchId: _matchId),
            historyRepository: _StaticHistoryRepository(_transcript),
            analysisCoach: settings ?? AnalysisCoachSettings.defaults(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 1));
}

List<Map<String, Object?>> _anchors(WidgetTester tester) {
  final anchors = <Map<String, Object?>>[];
  for (final element in tester.allElements) {
    final widget = element.widget;
    final key = widget.key;
    final keyLabel = key is ValueKey<String> ? key.value : null;
    final typeName = widget.runtimeType.toString();
    final tracked = _trackedTypes.contains(typeName);

    if (keyLabel == null && !tracked) {
      continue;
    }
    if (keyLabel != null && _isCardKey(keyLabel) && !tracked) {
      continue;
    }

    final renderObject = element.renderObject;
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      continue;
    }
    final origin = renderObject.localToGlobal(Offset.zero);
    final boxSize = renderObject.size;
    anchors.add({
      'type': typeName,
      if (keyLabel != null && !_isCardKey(keyLabel)) 'key': keyLabel,
      'left': _round(origin.dx),
      'top': _round(origin.dy),
      'width': _round(boxSize.width),
      'height': _round(boxSize.height),
    });
  }
  return anchors;
}

/// Drains every overflow the last pump produced.
List<String> _overflows(WidgetTester tester) {
  final found = <String>[];
  for (var attempt = 0; attempt < 64; attempt++) {
    final error = tester.takeException();
    if (error == null) {
      break;
    }
    found.add(error.toString().split('\n').first.trim());
  }
  return found;
}

/// Compares rendered anchors against the frozen ones with A36b's single named
/// exception applied.
///
/// The exception is *asserted*, not tolerated. The frozen tree must contain
/// exactly one `SouthSideControls` anchor and the rendered tree none, so its
/// absence is proven to be A38's deliberate hiding of the replay-only Meld
/// control. A comparison that merely skipped missing geometry would go on
/// passing if the table quietly lost an opponent rail.
void _expectMatchesOracle(
  List<Map<String, Object?>> actual,
  List<Map<String, Object?>> frozen,
  String label,
) {
  expect(
    frozen.where((a) => a['type'] == 'SouthSideControls'),
    hasLength(1),
    reason: 'the frozen oracle at $label must contain the pre-edit control',
  );
  expect(
    actual.where((a) => a['type'] == 'SouthSideControls'),
    isEmpty,
    reason: 'A38 hides the replay-only Meld control at $label',
  );

  final expected =
      frozen.where((a) => a['type'] != 'SouthSideControls').toList();
  expect(actual.length, expected.length, reason: label);
  for (var i = 0; i < expected.length; i++) {
    expect(actual[i], expected[i], reason: 'anchor $i at $label');
  }
}

Map<String, Object?> _oracleSize(String label) {
  final decoded =
      jsonDecode(File(_oraclePath).readAsStringSync()) as Map<String, Object?>;
  final sizes = decoded['sizes']! as Map<String, Object?>;
  return sizes[label]! as Map<String, Object?>;
}

void main() {
  setUpAll(() {
    final state = buildCompletedMatch(seed: 13).recorderState;
    _transcript = MatchActionTranscript(
      initialSnapshot: state.initialSnapshot!,
      entries: state.entries,
    );
  });

  group('oracle integrity', () {
    test('the digest routine itself is correct', () {
      // Checked against the published SHA-256 vectors first, so a bug in this
      // file is distinguishable from a tampered fixture. Without this, both
      // failures look identical and the wrong one gets investigated.
      expect(
        sha256Hex(utf8.encode('abc')),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      expect(
        sha256Hex(const <int>[]),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('the frozen oracle is byte-for-byte unchanged', () {
      final file = File(_oraclePath);
      expect(file.existsSync(), isTrue, reason: _oraclePath);
      expect(
        sha256Hex(file.readAsBytesSync()),
        _oracleSha,
        reason:
            'The pre-edit oracle has changed. It is generated once from '
            'pre-edit code and never regenerated — regenerating it from '
            'repaired code would make every comparison below assert that the '
            'new code matches itself.',
      );
    });
  });

  group('narrow docked repair', () {
    for (final size in const [Size(320, 568), Size(390, 844)]) {
      final label = '${size.width.toInt()}x${size.height.toInt()}';

      for (final language in [AppStrings.english, AppStrings.arabic]) {
        testWidgets('$label renders without overflow in '
            '${language.languageCode}', timeout: _slow, (tester) async {
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await _pumpAt(tester, size, strings: language);

          expect(
            _overflows(tester),
            isEmpty,
            reason: 'pre-repair this overflowed: 89 px at 320, 19 px at 390',
          );
        });
      }

      testWidgets('$label keeps every frozen anchor', timeout: _slow, (
        tester,
      ) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await _pumpAt(tester, size);
        _overflows(tester);

        final frozen = (_oracleSize(label)['anchors']! as List<Object?>)
            .cast<Map<String, Object?>>();
        final actual = _anchors(tester);

        // The oracle holds no anchor inside AnalysisCoachPanel, so the repair
        // must leave all 22 untouched — which is what makes it height-neutral.
        _expectMatchesOracle(actual, frozen, label);
      });
    }

    testWidgets('the analysis region keeps its frozen height', timeout: _slow, (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final entry in const {
        '320x568': Size(320, 568),
        '390x844': Size(390, 844),
      }.entries) {
        await _pumpAt(tester, entry.value);
        _overflows(tester);

        final frozen = (_oracleSize(entry.key)['anchors']! as List<Object?>)
            .cast<Map<String, Object?>>()
            .firstWhere((a) => a['type'] == 'ReviewAnalysisRegion');
        final actual = _anchors(tester)
            .firstWhere((a) => a['type'] == 'ReviewAnalysisRegion');

        expect(
          actual['height'],
          frozen['height'],
          reason:
              'a reflow that grew the panel would move a protected rect at '
              '${entry.key}',
        );
      }
    });
  });

  group('wide sizes are untouched', () {
    for (final entry in const {
      '1024x768': Size(1024, 768),
      '1280x800': Size(1280, 800),
      '834x1112': Size(834, 1112),
    }.entries) {
      testWidgets('${entry.key} matches the oracle exactly', timeout: _slow, (
        tester,
      ) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await _pumpAt(tester, entry.value);
        expect(_overflows(tester), isEmpty);

        final frozen = (_oracleSize(entry.key)['anchors']! as List<Object?>)
            .cast<Map<String, Object?>>();
        final actual = _anchors(tester);

        _expectMatchesOracle(actual, frozen, entry.key);
      });
    }
  });

  group('controls still work after reflowing', () {
    for (final size in const [Size(320, 568), Size(390, 844)]) {
      final label = '${size.width.toInt()}x${size.height.toInt()}';

      for (final language in [AppStrings.english, AppStrings.arabic]) {
        testWidgets(
          '$label ${language.languageCode}: the card-death switch reports a '
          'change',
          timeout: _slow,
          (tester) async {
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await _pumpAt(tester, size, strings: language);
            _overflows(tester);

            final before = tester
                .widget<Switch>(find.byType(Switch))
                .value;

            // Exercised, not merely measured. A control that reflowed into
            // something visible, correctly sized and inert passes every
            // geometry assertion in this file.
            await tester.tap(find.byType(Switch), warnIfMissed: false);
            await tester.pumpAndSettle();

            expect(
              tester.widget<Switch>(find.byType(Switch)).value,
              isNot(before),
              reason: 'tapping the switch must change the setting',
            );
          },
        );

        testWidgets(
          '$label ${language.languageCode}: the verbosity control opens and '
          'applies a level',
          timeout: _slow,
          (tester) async {
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await _pumpAt(tester, size, strings: language);
            _overflows(tester);

            final menu = find.byType(DropdownButton<AnalysisVerbosity>);
            expect(menu, findsOneWidget);

            await tester.tap(menu, warnIfMissed: false);
            await tester.pumpAndSettle();

            final target = verbosityLabel(
              language,
              AnalysisVerbosity.narrateAll,
            );
            await tester.tap(find.text(target).last);
            await tester.pumpAndSettle();

            expect(
              tester
                  .widget<DropdownButton<AnalysisVerbosity>>(menu)
                  .value,
              AnalysisVerbosity.narrateAll,
            );
          },
        );
      }
    }
  });

  group('fit comes from constraints, not a width literal', () {
    testWidgets('a sweep across the fit transition never overflows',
        timeout: const Timeout(Duration(minutes: 10)), (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Spans the measured transition rather than probing two points, so a
      // presentation that happens to fit at 320 and 390 but breaks between
      // them cannot pass.
      //
      // The floor is 320 because that is the narrowest width the product
      // supports and the narrowest the contract names. Below it the verbosity
      // control's own intrinsic width no longer fits at all — 300 wide still
      // overflows by 12 px — and shrinking that control would change its
      // presentation at every size, which is wider than the repair the owner
      // authorized. Recorded rather than silently excluded.
      for (final language in [AppStrings.english, AppStrings.arabic]) {
        for (var width = 320.0; width <= 460.0; width += 20.0) {
          await _pumpAt(tester, Size(width, 844), strings: language);
          expect(
            _overflows(tester),
            isEmpty,
            reason: '${width.toInt()} wide, ${language.languageCode}',
          );
        }
      }
    });

    test('the panel selects no presentation from a hard-coded width', () {
      final source = File(_panelPath).readAsStringSync();

      // The interpolated ~409 dp figure explains the two measured overflows;
      // it is not a verified threshold, and encoding it — or any other width
      // literal — would reintroduce exactly the magic-width branching the
      // owner's ruling prohibited for the HUD.
      expect(source.contains('409'), isFalse);
      expect(
        RegExp(r'(maxWidth|minWidth|\.width)\s*[<>]=?\s*[0-9]').hasMatch(source),
        isFalse,
        reason: 'width-literal branch selection in $_panelPath',
      );
      expect(
        RegExp(r'[0-9]+(\.[0-9]+)?\s*[<>]=?\s*(constraints|size)\.')
            .hasMatch(source),
        isFalse,
        reason: 'width-literal branch selection in $_panelPath',
      );
    });
  });
}

/// SHA-256 over [data].
///
/// Written out rather than taken from `package:crypto`, which this project does
/// not depend on and which Amendment 01's scope forbids adding.
String sha256Hex(List<int> data) {
  const k = <int>[
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, //
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  final h = <int>[
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, //
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ];

  int rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xffffffff;

  final message = List<int>.from(data)..add(0x80);
  while (message.length % 64 != 56) {
    message.add(0);
  }
  final bitLength = data.length * 8;
  for (var i = 7; i >= 0; i--) {
    message.add((bitLength >> (8 * i)) & 0xff);
  }

  final w = List<int>.filled(64, 0);
  for (var chunk = 0; chunk < message.length; chunk += 64) {
    for (var i = 0; i < 16; i++) {
      final j = chunk + i * 4;
      w[i] = (message[j] << 24) |
          (message[j + 1] << 16) |
          (message[j + 2] << 8) |
          message[j + 3];
    }
    for (var i = 16; i < 64; i++) {
      final s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
    }

    var a = h[0];
    var b = h[1];
    var c = h[2];
    var d = h[3];
    var e = h[4];
    var f = h[5];
    var g = h[6];
    var hh = h[7];

    for (var i = 0; i < 64; i++) {
      final s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      final ch = (e & f) ^ ((~e & 0xffffffff) & g);
      final t1 = (hh + s1 + ch + k[i] + w[i]) & 0xffffffff;
      final s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + maj) & 0xffffffff;

      hh = g;
      g = f;
      f = e;
      e = (d + t1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & 0xffffffff;
    }

    h[0] = (h[0] + a) & 0xffffffff;
    h[1] = (h[1] + b) & 0xffffffff;
    h[2] = (h[2] + c) & 0xffffffff;
    h[3] = (h[3] + d) & 0xffffffff;
    h[4] = (h[4] + e) & 0xffffffff;
    h[5] = (h[5] + f) & 0xffffffff;
    h[6] = (h[6] + g) & 0xffffffff;
    h[7] = (h[7] + hh) & 0xffffffff;
  }

  return h.map((v) => v.toRadixString(16).padLeft(8, '0')).join();
}
