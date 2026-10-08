import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/ui/core/cards/card_theme.dart';
import 'package:hareeg_table/ui/core/cards/card_view.dart';
import 'package:hareeg_table/ui/core/cards/themes/bundled_themes.dart';

Future<CustomPainter> _painterFor(
  WidgetTester tester,
  HareegCard card, {
  CardVariant variant = CardVariant.full,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: HareegCardView(
            theme: minimalSymbolsCardTheme,
            card: card,
            variant: variant,
            size: const Size(80, 116),
            jokerDisplay: JokerDisplay.assisted,
          ),
        ),
      ),
    ),
  );
  // Let a card swap's cross-fade finish so only the current face is painted.
  await tester.pumpAndSettle();
  final paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byType(HareegCardView),
      matching: find.byType(CustomPaint),
    ),
  );
  return paint.painter!;
}

void main() {
  testWidgets('a joker repaints when it takes on a represented identity', (
    tester,
  ) async {
    const bare = HareegCard.joker(deckIndex: 0, jokerIndex: 0);
    const assigned = HareegCard.joker(
      deckIndex: 0,
      jokerIndex: 0,
      representedIdentity: CardIdentity(
        rank: CardRank.seven,
        suit: CardSuit.hearts,
      ),
    );
    // Same physical card, so HareegCard == says they are equal.
    expect(bare, assigned);

    final before = await _painterFor(tester, bare);
    final after = await _painterFor(tester, assigned);

    expect(after.shouldRepaint(before), isTrue);
  });

  testWidgets('a different card or variant repaints; the same one does not', (
    tester,
  ) async {
    final seven = HareegCard.standard(
      rank: CardRank.seven,
      suit: CardSuit.hearts,
      deckIndex: 0,
    );
    final eight = HareegCard.standard(
      rank: CardRank.eight,
      suit: CardSuit.hearts,
      deckIndex: 0,
    );

    final first = await _painterFor(tester, seven);
    final same = await _painterFor(tester, seven);
    final other = await _painterFor(tester, eight);
    final compact = await _painterFor(
      tester,
      eight,
      variant: CardVariant.compact,
    );

    expect(same.shouldRepaint(first), isFalse);
    expect(other.shouldRepaint(same), isTrue);
    expect(compact.shouldRepaint(other), isTrue);
  });
}
