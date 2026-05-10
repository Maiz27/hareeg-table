import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/app/hareeg_table_app.dart';

void main() {
  testWidgets('app shell presents Classic Hareeg foundation', (tester) async {
    await tester.pumpWidget(const HareegTableApp());

    expect(find.text('Hareeg Table'), findsOneWidget);
    expect(find.text('Classic Hareeg'), findsOneWidget);
    expect(find.text('51'), findsOneWidget);
    expect(find.text('Pure Dart rules core'), findsOneWidget);
  });
}
