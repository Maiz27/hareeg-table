import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/ui/core/cards/card_theme.dart';
import 'package:hareeg_table/ui/core/cards/card_view.dart';
import 'package:hareeg_table/ui/core/cards/themes/bundled_themes.dart';

void main() {
  test('Iron Rose resolves bundled face, back, and joker artwork', () {
    const theme = ironRoseCardTheme;
    final queenDiamonds = HareegCard.standard(
      rank: CardRank.queen,
      suit: CardSuit.diamonds,
      deckIndex: 0,
    );

    final faceAsset = theme.imageAssetFor(
      CardRenderRequest(
        card: queenDiamonds,
        variant: CardVariant.full,
        size: const Size(64, 92),
      ),
    );
    expect(faceAsset, 'assets/cards/iron_rose/queen_diamonds.webp');

    final backAsset = theme.imageAssetFor(
      CardRenderRequest(
        card: queenDiamonds,
        variant: CardVariant.back,
        size: const Size(64, 92),
        faceDown: true,
      ),
    );
    expect(backAsset, 'assets/cards/iron_rose/back.webp');

    const redJoker = HareegCard.joker(deckIndex: 0, jokerIndex: 0);
    const blackJoker = HareegCard.joker(deckIndex: 0, jokerIndex: 1);
    expect(
      theme.imageAssetFor(
        CardRenderRequest(
          card: redJoker,
          variant: CardVariant.full,
          size: const Size(64, 92),
        ),
      ),
      'assets/cards/iron_rose/joker_red.webp',
    );
    expect(
      theme.imageAssetFor(
        CardRenderRequest(
          card: blackJoker,
          variant: CardVariant.full,
          size: const Size(64, 92),
        ),
      ),
      'assets/cards/iron_rose/joker_black.webp',
    );
  });

  testWidgets('Iron Rose renders face, back, and represented joker assets', (
    tester,
  ) async {
    const theme = ironRoseCardTheme;
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
              HareegCardView(theme: theme, card: ace, size: const Size(64, 92)),
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
  });
}
