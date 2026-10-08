import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/ui/core/motion/celebration.dart';

class _Probe extends StatefulWidget {
  const _Probe();

  static int inits = 0;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    _Probe.inits++;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

void main() {
  testWidgets('a strike shakes the table without rebuilding its state', (
    tester,
  ) async {
    // The shake wraps the whole table; if it changed shape per strike, every
    // table widget's state (joker memory cues, expanded meld lanes) would be
    // thrown away and rebuilt on each Fifty.
    _Probe.inits = 0;
    Widget at(int serial) => Directionality(
      textDirection: TextDirection.ltr,
      child: ImpactShake(serial: serial, child: const _Probe()),
    );

    await tester.pumpWidget(at(0));
    await tester.pumpWidget(at(1));
    await tester.pump(const Duration(milliseconds: 350));
    final moved = tester.widget<Transform>(find.byType(Transform).first);
    expect(moved.transform.getTranslation().x, isNot(0));
    await tester.pumpAndSettle();
    await tester.pumpWidget(at(2));
    await tester.pumpAndSettle();

    expect(_Probe.inits, 1);
    final rest = tester.widget<Transform>(find.byType(Transform).first);
    expect(rest.transform.getTranslation().x, 0);
  });
}
