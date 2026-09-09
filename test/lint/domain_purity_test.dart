import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Lint test: `lib/domain/` stays pure Dart, per ADR 0001.
///
/// Two properties, because one without the other is not worth much:
///
/// 1. No domain file imports `package:flutter`.
/// 2. No domain file imports anything under `lib/ui`, `lib/app`, or
///    `lib/l10n` — checked **after resolving** the import against the
///    importing file's directory, so a relative `../../ui/...` is caught as
///    well as a `package:hareeg_table/ui/...` form.
/// 3. No domain file imports anything under `lib/cpu`.
///
/// Without the second, a domain file could import a widget-layer helper and
/// reach Flutter transitively while the first check stayed green.
///
/// The third keeps the shared analysis shared. `lib/domain/.../analysis/`
/// computes signals that both a CPU planner and a replay coach read, and the
/// moment it reaches back into `lib/cpu` for a scoring helper it stops being
/// reusable and starts being a planner detail. The dependency runs one way:
/// the CPU layer passes what it needs in.
///
/// All three properties hold today. This test is what keeps them holding.
void main() {
  final root = _projectRoot();
  final domainFiles = Directory('${root.path}/lib/domain')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList(growable: false);

  test('lib/domain exists and has files to check', () {
    // A guard against the whole suite silently passing because the directory
    // moved and every loop below iterated over nothing.
    expect(domainFiles, isNotEmpty);
  });

  test('no domain file imports package:flutter', () {
    final offenders = <String>[];

    for (final file in domainFiles) {
      for (final import in _importsOf(file.readAsStringSync())) {
        if (import.startsWith('package:flutter')) {
          offenders.add('${_relative(file.path, root)} -> $import');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'ADR 0001 keeps the rules engine testable without Flutter. Move the '
          'widget-facing part into lib/ui instead:\n${offenders.join('\n')}',
    );
  });

  test('no domain file imports lib/ui, lib/app, or lib/l10n', () {
    const forbidden = ['ui', 'app', 'l10n'];
    final offenders = <String>[];

    for (final file in domainFiles) {
      for (final import in _importsOf(file.readAsStringSync())) {
        final target = _resolveToLibPath(
          import: import,
          fromFile: file,
          root: root,
        );
        if (target == null) {
          continue;
        }
        if (forbidden.any((dir) => target.startsWith('lib/$dir/'))) {
          offenders.add('${_relative(file.path, root)} -> $target');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'A domain file that imports the UI layer reaches Flutter '
          'transitively, so the package:flutter check alone would not catch '
          'it. Dependencies point inward:\n${offenders.join('\n')}',
    );
  });

  test('no domain file imports lib/cpu', () {
    final offenders = <String>[];

    for (final file in domainFiles) {
      for (final import in _importsOf(file.readAsStringSync())) {
        final target = _resolveToLibPath(
          import: import,
          fromFile: file,
          root: root,
        );
        if (target == null) {
          continue;
        }
        if (target.startsWith('lib/cpu/')) {
          offenders.add('${_relative(file.path, root)} -> $target');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'The shared table-reading analysis is consumed by CPU planners AND '
          'by the replay coach. A domain file that imports lib/cpu turns that '
          'shared computation into a planner detail and makes the coach depend '
          'on the CPU ladder. Pass the CPU-side model in as an argument '
          'instead:\n${offenders.join('\n')}',
    );
  });
}

/// Every import URI in [source], single- or double-quoted.
List<String> _importsOf(String source) {
  final expression = RegExp(
    '''^\\s*(?:import|export)\\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );
  return [
    for (final match in expression.allMatches(source)) match.group(1)!,
  ];
}

/// Resolves [import] to a repo-relative `lib/...` path, or null when it does
/// not name a file inside this package.
String? _resolveToLibPath({
  required String import,
  required File fromFile,
  required Directory root,
}) {
  const packagePrefix = 'package:hareeg_table/';
  if (import.startsWith(packagePrefix)) {
    return 'lib/${import.substring(packagePrefix.length)}';
  }
  if (import.startsWith('dart:') || import.startsWith('package:')) {
    return null;
  }

  // Relative: resolve against the importing file's own directory, which is the
  // step that turns "../../ui/core/theme/x.dart" into a comparable path.
  final resolved = Uri.file(
    fromFile.path.replaceAll(r'\', '/'),
  ).resolve(import).toFilePath();
  return _relative(resolved, root);
}

String _relative(String path, Directory root) {
  final normalizedRoot = '${root.path.replaceAll(r'\', '/')}/';
  final normalized = path.replaceAll(r'\', '/');
  return normalized.startsWith(normalizedRoot)
      ? normalized.substring(normalizedRoot.length)
      : normalized;
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
