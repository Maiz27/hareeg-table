import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/ui/core/panels/lounge_panel.dart';

LoungePanelAction _action(String label, LoungePanelActionTone tone) =>
    LoungePanelAction(
      icon: Icons.check,
      label: label,
      onTap: () {},
      tone: tone,
    );

Future<void> _pump(WidgetTester tester, LoungePanelActions actions) {
  return tester.pumpWidget(MaterialApp(home: Scaffold(body: actions)));
}

void main() {
  testWidgets('each action is styled by its tone, not its slot', (
    tester,
  ) async {
    await _pump(
      tester,
      LoungePanelActions(
        primary: _action('Leave', LoungePanelActionTone.neutral),
        secondary: _action('Resume', LoungePanelActionTone.primary),
        tertiary: _action('Delete', LoungePanelActionTone.danger),
      ),
    );

    expect(
      find.ancestor(
        of: find.text('Resume'),
        matching: find.byType(FilledButton),
      ),
      findsOneWidget,
    );
    for (final label in ['Leave', 'Delete']) {
      expect(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(FilledButton),
        ),
        findsNothing,
      );
      expect(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(OutlinedButton),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('the usual primary/secondary pairing is unchanged', (
    tester,
  ) async {
    await _pump(
      tester,
      LoungePanelActions(
        primary: _action('Resume', LoungePanelActionTone.primary),
        secondary: _action('Leave', LoungePanelActionTone.danger),
      ),
    );

    expect(
      find.ancestor(
        of: find.text('Resume'),
        matching: find.byType(FilledButton),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.text('Leave'),
        matching: find.byType(OutlinedButton),
      ),
      findsOneWidget,
    );
  });
}
