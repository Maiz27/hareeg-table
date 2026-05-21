import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/ui/core/cards/card_theme.dart';
import 'package:hareeg_table/ui/core/cards/card_view.dart';
import 'package:hareeg_table/ui/core/cards/themes/high_contrast_theme.dart';
import 'package:hareeg_table/ui/core/cards/themes/minimal_symbols_theme.dart';
import 'package:hareeg_table/ui/core/cards/themes/wikimedia_pd_theme.dart';

/// Code-rendered themes that route jokers through the shared
/// [CardPainting.paintJokerFace]. Kenney Classic is excluded because it
/// returns a bundled PNG for jokers, so the painter's corner indices do not
/// apply.
const _sharedJokerThemes = <(String, HareegCardTheme)>[
  ('High Contrast', HighContrastCardTheme()),
  ('Minimal Symbols', MinimalSymbolsCardTheme()),
  ('Wikimedia PD', WikimediaPdCardTheme()),
];

const _sizesByVariant = <(String, CardVariant, Size)>[
  ('picker', CardVariant.picker, Size(48, 70)),
  ('compact', CardVariant.compact, Size(56, 84)),
  ('full', CardVariant.full, Size(80, 116)),
];

Future<void> _pumpJoker(
  WidgetTester tester, {
  required HareegCardTheme theme,
  required CardVariant variant,
  required Size size,
  HareegCard? card,
  JokerDisplay? jokerDisplay,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: HareegCardView(
            theme: theme,
            card: card ?? const HareegCard.joker(deckIndex: 0, jokerIndex: 0),
            variant: variant,
            size: size,
            jokerDisplay: jokerDisplay ?? JokerDisplay.assisted,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Joker face draws corner indices without errors', () {
    for (final (themeName, theme) in _sharedJokerThemes) {
      for (final (variantName, variant, size) in _sizesByVariant) {
        testWidgets('$themeName / $variantName variant', (tester) async {
          await _pumpJoker(tester, theme: theme, variant: variant, size: size);

          expect(tester.takeException(), isNull);
          expect(find.bySemanticsLabel('Joker'), findsOneWidget);
        });
      }
    }
  });

  testWidgets('joker corners stay drawn when the joker carries a represented '
      'identity', (tester) async {
    const card = HareegCard.joker(
      deckIndex: 0,
      jokerIndex: 0,
      representedIdentity: CardIdentity(
        rank: CardRank.king,
        suit: CardSuit.hearts,
      ),
    );

    await _pumpJoker(
      tester,
      theme: const MinimalSymbolsCardTheme(),
      variant: CardVariant.full,
      size: const Size(80, 116),
      card: card,
    );

    expect(tester.takeException(), isNull);
    expect(
      find.bySemanticsLabel('Joker representing King of Hearts'),
      findsOneWidget,
    );
  });

  testWidgets(
    'unassigned-joker display keeps the corner indices on the plain face',
    (tester) async {
      await _pumpJoker(
        tester,
        theme: const MinimalSymbolsCardTheme(),
        variant: CardVariant.full,
        size: const Size(80, 116),
        jokerDisplay: JokerDisplay.unassigned,
      );

      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel('Joker'), findsOneWidget);
    },
  );
}
