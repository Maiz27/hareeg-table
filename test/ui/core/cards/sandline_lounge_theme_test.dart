import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/ui/core/cards/card_theme.dart';
import 'package:hareeg_table/ui/core/cards/card_view.dart';
import 'package:hareeg_table/ui/core/cards/themes/sandline_lounge_theme.dart';

void main() {
  testWidgets(
    'Sandline Lounge renders face, back, and represented joker assets',
    (tester) async {
      const theme = SandlineLoungeCardTheme();
      final ace = HareegCard.standard(
        rank: CardRank.ace,
        suit: CardSuit.spades,
        deckIndex: 0,
      );
      const joker = HareegCard.joker(
        deckIndex: 0,
        jokerIndex: 0,
        representedIdentity: CardIdentity(
          rank: CardRank.king,
          suit: CardSuit.hearts,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                HareegCardView(
                  theme: theme,
                  card: ace,
                  size: const Size(64, 92),
                ),
                HareegCardView(
                  theme: theme,
                  card: ace,
                  variant: CardVariant.back,
                  faceDown: true,
                  size: const Size(64, 92),
                ),
                HareegCardView(
                  theme: theme,
                  card: joker,
                  size: const Size(64, 92),
                  jokerDisplay: JokerDisplay.assisted,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(Image), findsNWidgets(3));
      expect(find.bySemanticsLabel('Ace of Spades'), findsOneWidget);
      expect(find.bySemanticsLabel('Face-down card'), findsOneWidget);
      expect(find.text('K'), findsOneWidget);
    },
  );
}
