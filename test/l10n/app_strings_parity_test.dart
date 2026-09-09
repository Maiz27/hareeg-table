import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Lint test: the English and Arabic catalogs hold the same keys.
///
/// `AppStrings._v` falls back to `_englishValues[key]!` when a key is missing
/// from the active catalog. That fallback is a good runtime safety net and a
/// terrible review signal: an untranslated string ships looking fine in
/// English and nothing fails. This test turns the omission into a test
/// failure at the moment the key is added.
///
/// The catalogs are private consts, so this scans the source the way
/// `no_orphan_widgets_test.dart` already does rather than reflecting on them.
void main() {
  late final Map<String, List<String>> catalogs;

  setUpAll(() {
    final source = File(
      '${_projectRoot().path}/lib/l10n/app_strings.dart',
    ).readAsStringSync();

    catalogs = {
      'english': _keysOf(source, '_englishValues'),
      'arabic': _keysOf(source, '_arabicValues'),
    };
  });

  test('both catalogs were found and are non-trivial', () {
    // Guards against a rename turning every assertion below into a comparison
    // of two empty lists.
    expect(catalogs['english'], isNotEmpty);
    expect(catalogs['arabic'], isNotEmpty);
  });

  test('no catalog declares the same key twice', () {
    for (final entry in catalogs.entries) {
      final duplicates = <String>{};
      final seen = <String>{};
      for (final key in entry.value) {
        if (!seen.add(key)) {
          duplicates.add(key);
        }
      }
      expect(
        duplicates,
        isEmpty,
        reason:
            'Duplicate keys in ${entry.key}: the later value silently wins. '
            '${duplicates.join(', ')}',
      );
    }
  });

  test('English and Arabic hold identical key sets', () {
    final english = catalogs['english']!.toSet();
    final arabic = catalogs['arabic']!.toSet();

    expect(
      english.difference(arabic),
      isEmpty,
      reason:
          'These keys have no Arabic value, so they would silently render in '
          'English for an Arabic player.',
    );
    expect(
      arabic.difference(english),
      isEmpty,
      reason:
          'These Arabic keys have no English counterpart, so nothing reads '
          'them and they are dead weight.',
    );
  });
}

List<String> _keysOf(String source, String catalog) {
  final start = source.indexOf('const $catalog = {');
  expect(start, isNot(-1), reason: 'Could not find $catalog.');

  final end = source.indexOf('\n};', start);
  expect(end, isNot(-1), reason: 'Could not find the end of $catalog.');

  final body = source.substring(start, end);
  return [
    for (final match in RegExp(
      "^  '([^']+)':",
      multiLine: true,
    ).allMatches(body))
      match.group(1)!,
  ];
}

Directory _projectRoot() {
  var directory = Directory.current;
  while (!File('${directory.path}/pubspec.yaml').existsSync()) {
    final parent = directory.parent;
    if (parent.path == directory.path) {
      fail('Could not locate the project root from ${Directory.current.path}');
    }
    directory = parent;
  }
  return directory;
}
