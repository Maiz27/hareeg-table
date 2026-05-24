import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Lint test: every public widget under `lib/ui/features/game_table/widgets/`
/// must be referenced from somewhere outside its defining file.
///
/// A recent refactor stripped a UI widget from the screen but left the widget
/// file behind. The orphan compiled and analyzed cleanly — only a grep
/// uncovered it. This test makes orphan widget files a hard test failure so
/// future refactors can't leave dead code stranded under `widgets/`.
///
/// Strategy
/// --------
/// 1. Walk every non-test `.dart` file under the widgets dir.
/// 2. Pull out public widget class names with a regex that matches classes
///    extending `StatelessWidget`, `StatefulWidget`, or any `Consumer*Widget`
///    (Riverpod). Private (`_Foo`) classes are scoped to their file and are
///    skipped.
/// 3. Skip any widget tagged `@visibleForTesting` immediately before its
///    declaration — those are wired up by tests, not by `lib/`.
/// 4. For each remaining widget, scan every other `.dart` file under `lib/`
///    for `WidgetName(` (constructor / extension) or `WidgetName.` (static
///    access / named ctor). Zero hits => the widget has no callers and the
///    test fails with an actionable message.
///
/// A regex is sufficient — Dart widget declarations follow a uniform shape
/// and we don't need full AST resolution to spot orphans.
void main() {
  test('no orphan widgets under lib/ui/features/game_table/widgets/', () {
    final projectRoot = _projectRoot();
    final widgetsDir = Directory(
      '${projectRoot.path}/lib/ui/features/game_table/widgets',
    );
    expect(
      widgetsDir.existsSync(),
      isTrue,
      reason: 'Expected widgets dir at ${widgetsDir.path}',
    );

    final libDir = Directory('${projectRoot.path}/lib');
    final libDartFiles = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('_test.dart'))
        .toList(growable: false);

    final widgetFiles = widgetsDir
        .listSync(recursive: false)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('_test.dart'))
        .toList(growable: false);

    final orphans = <_Orphan>[];
    for (final widgetFile in widgetFiles) {
      final source = widgetFile.readAsStringSync();
      final declared = _publicWidgetClasses(source);
      for (final name in declared) {
        if (_hasExternalReference(
          name: name,
          definingFile: widgetFile,
          libFiles: libDartFiles,
        )) {
          continue;
        }
        orphans.add(_Orphan(name: name, path: widgetFile.path));
      }
    }

    expect(
      orphans,
      isEmpty,
      reason: orphans
          .map(
            (o) =>
                'Widget ${o.name} in ${_relativeToProject(o.path, projectRoot)} '
                'has no callers in lib/. Either reference it from a screen, '
                'mark @visibleForTesting, or delete it.',
          )
          .join('\n'),
    );
  });
}

/// Captures public widget class names — anything `extends StatelessWidget`,
/// `extends StatefulWidget`, or `extends Consumer*Widget` (Riverpod variants
/// like ConsumerWidget / ConsumerStatefulWidget). Group 1 is the class name.
final RegExp _publicWidgetClassPattern = RegExp(
  r'class\s+([A-Z]\w*)\s+extends\s+(?:StatelessWidget|StatefulWidget|Consumer\w*Widget)\b',
);

/// Captures `@visibleForTesting` immediately preceding a class declaration.
/// We pull the annotation + class header in one match so we can exempt the
/// class from the orphan check.
final RegExp _visibleForTestingClassPattern = RegExp(
  r'@visibleForTesting\s*(?://[^\n]*\n\s*|/\*[\s\S]*?\*/\s*)*class\s+([A-Z]\w*)',
);

List<String> _publicWidgetClasses(String source) {
  final visibleForTesting = _visibleForTestingClassPattern
      .allMatches(source)
      .map((m) => m.group(1)!)
      .toSet();
  return _publicWidgetClassPattern
      .allMatches(source)
      .map((m) => m.group(1)!)
      .where((name) => !visibleForTesting.contains(name))
      .toList(growable: false);
}

bool _hasExternalReference({
  required String name,
  required File definingFile,
  required List<File> libFiles,
}) {
  // Match `Name(` (constructor / extension call) or `Name.` (named ctor or
  // static access). Word boundary ensures `_Name` and `NameSuffix` don't
  // count as references.
  final pattern = RegExp(r'\b' + RegExp.escape(name) + r'(?:\(|\.)');
  for (final file in libFiles) {
    if (_samePath(file.path, definingFile.path)) {
      continue;
    }
    if (pattern.hasMatch(file.readAsStringSync())) {
      return true;
    }
  }
  return false;
}

bool _samePath(String a, String b) {
  return _normalize(a) == _normalize(b);
}

String _normalize(String path) => path.replaceAll(r'\', '/').toLowerCase();

String _relativeToProject(String path, Directory projectRoot) {
  final normalizedPath = path.replaceAll(r'\', '/');
  final normalizedRoot = projectRoot.path.replaceAll(r'\', '/');
  if (normalizedPath.startsWith('$normalizedRoot/')) {
    return normalizedPath.substring(normalizedRoot.length + 1);
  }
  return normalizedPath;
}

/// Locates the package root by walking up from the test file until a
/// `pubspec.yaml` is found. The Flutter test runner cwd is normally the
/// package root, but walking up keeps the test robust if the runner ever
/// invokes it from a sub-directory.
Directory _projectRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('Could not locate pubspec.yaml from ${Directory.current.path}');
}

class _Orphan {
  _Orphan({required this.name, required this.path});
  final String name;
  final String path;
}
