import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Ratchet for the design contract's token rule (section 2): UI code uses
/// `LoungeTokens` rather than raw colours and durations.
///
/// The redesign migrated the literals that equal a token; the rest predate
/// the contract and still carry tuned values. Rather than rewrite them blind,
/// this test pins today's counts as a ceiling. A change may lower a count
/// (then lower the ceiling here in the same change) but never raise it: new
/// UI reaches for a token, or adds one to `lounge_tokens.dart` and the
/// contract.
///
/// Counts every occurrence (not lines) under `lib/ui/`, except the token file
/// itself, where these literals belong.
const _ceilings = <String, int>{
  r'Duration\(milliseconds:': 49,
  // What remains is artwork, not chrome: the per-theme card palettes under
  // `lib/ui/core/cards/themes/` and the wood / sapphire / clay table
  // materials in `table_background.dart`. Chrome paints with roles.
  r'Color\(0x': 121,
};

/// Hue-named tokens retired by the Lit card identity. They were deleted from
/// `LoungeTokens`; this keeps them from coming back under the same names.
const _retiredTokens = [
  'feltGreen',
  'coffeeCharcoal',
  'cardIvory',
  'sandLine',
  'goldAccent',
  'fiftyFlame',
  'deepRed',
  'indigoAccent',
  'offWhiteText',
  'mutedText',
  'feltRaised',
  'feltSpotlight',
  'overlayScrim',
  'selectedGlow',
  'pendingDiscard',
  'invalidAction',
  'surfaceL2',
  'edgeL2',
];

/// The theme layer: the raw palette and the role tokens. The only place a hex
/// value or a `BrandPalette` reference belongs.
const _themeDir = 'lib/ui/core/theme/';

void main() {
  final files = Directory('lib/ui')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.replaceAll(r'\', '/').startsWith(_themeDir))
      .toList(growable: false);

  test('the ratchet scans the UI tree', () {
    expect(files.length, greaterThan(50));
  });

  test('the raw palette is private to the theme layer', () {
    // Design contract section 2: feature code paints with roles from
    // `LoungeTokens`; the hues behind them are `BrandPalette`'s business. A
    // widget reaching for a hue by name would survive a palette change with
    // the wrong colour.
    final hits = <String>[];
    for (final file in [
      ...files,
      ...Directory('lib/app')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')),
    ]) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('BrandPalette')) {
          hits.add('${file.path}:${i + 1}');
        }
      }
    }
    expect(hits, isEmpty, reason: 'Use a LoungeTokens role instead.');
  });

  test('retired hue-named tokens stay retired', () {
    final pattern = RegExp('LoungeTokens\\.(${_retiredTokens.join('|')})\\b');
    final hits = <String>[];
    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (pattern.hasMatch(lines[i])) {
          hits.add('${file.path}:${i + 1}');
        }
      }
    }
    expect(
      hits,
      isEmpty,
      reason: 'Colours are roles, not hues (design contract section 2).',
    );
  });

  for (final entry in _ceilings.entries) {
    test('raw ${entry.key} literals in lib/ui stay at or below '
        '${entry.value}', () {
      final pattern = RegExp(entry.key);
      final hits = <String>[];
      for (final file in files) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          for (final _ in pattern.allMatches(lines[i])) {
            hits.add('${file.path}:${i + 1}');
          }
        }
      }
      expect(
        hits.length,
        lessThanOrEqualTo(entry.value),
        reason:
            'New raw literals in UI code; use LoungeTokens instead '
            '(docs/design/design-contract.md section 2). Occurrences:\n'
            '${hits.join('\n')}',
      );
    });
  }
}
