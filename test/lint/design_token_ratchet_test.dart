import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Ratchet for the design contract's token rule (section 2): feature code
/// uses `LoungeTokens` rather than raw colours and durations.
///
/// The redesign migrated the literals that equal a token; the rest predate
/// the contract and still carry tuned values. Rather than rewrite them blind,
/// this test pins today's counts as a ceiling. A change may lower a count
/// (then lower the ceiling here in the same change) but never raise it: new
/// UI reaches for a token, or adds one to `lounge_tokens.dart` and the
/// contract.
const _ceilings = <String, int>{
  r'Duration\(milliseconds:': 23,
  r'Color\(0x': 63,
};

void main() {
  final features = Directory('lib/ui/features');
  final files = features
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList(growable: false);

  for (final entry in _ceilings.entries) {
    test('raw ${entry.key} literals in lib/ui/features stay at or below '
        '${entry.value}', () {
      final pattern = RegExp(entry.key);
      final hits = <String>[];
      for (final file in files) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (pattern.hasMatch(lines[i])) {
            hits.add('${file.path}:${i + 1}');
          }
        }
      }
      expect(
        hits.length,
        lessThanOrEqualTo(entry.value),
        reason:
            'New raw literals in feature code; use LoungeTokens instead '
            '(docs/design/design-contract.md section 2). Occurrences:\n'
            '${hits.join('\n')}',
      );
    });
  }
}
