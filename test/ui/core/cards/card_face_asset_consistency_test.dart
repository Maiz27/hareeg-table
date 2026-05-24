import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/ui/core/cards/card_theme.dart';
import 'package:hareeg_table/ui/core/cards/card_theme_registry.dart';

/// Slug used in bundled asset filenames for each rank.
const Map<CardRank, String> _rankSlugs = {
  CardRank.ace: 'ace',
  CardRank.two: 'two',
  CardRank.three: 'three',
  CardRank.four: 'four',
  CardRank.five: 'five',
  CardRank.six: 'six',
  CardRank.seven: 'seven',
  CardRank.eight: 'eight',
  CardRank.nine: 'nine',
  CardRank.ten: 'ten',
  CardRank.jack: 'jack',
  CardRank.queen: 'queen',
  CardRank.king: 'king',
};

/// Identities whose bundled face artwork is currently misaligned with the
/// (rank, suit) the game treats them as. The theme must route these through
/// the code-rendered painter instead of pointing at the broken asset.
///
/// J of Diamonds in Sandline Lounge: the shipped `jack_diamonds.webp` is a
/// duplicate of `jack_hearts.webp` (a red Jack with a heart pip in both
/// corners). Until corrected court art ships, the theme must fall back to the
/// code-rendered painter so the rank+pip drawn on screen match the card's
/// identity.
const Set<String> _knownBadAssets = {
  'sandline_lounge:jack:diamonds',
};

void main() {
  final allIdentities = <CardIdentity>[
    for (final rank in CardRank.values)
      for (final suit in CardSuit.values) CardIdentity(rank: rank, suit: suit),
  ];

  for (final theme in CardThemeRegistry.all()) {
    group('${theme.label} (${theme.id})', () {
      for (final identity in allIdentities) {
        test(
          'face asset for ${identity.rank.name} of ${identity.suit.name} '
          'is either bypassed or names its rank and suit',
          () {
            final card = HareegCard.standard(
              rank: identity.rank,
              suit: identity.suit,
              deckIndex: 0,
            );
            final request = CardRenderRequest(
              card: card,
              variant: CardVariant.full,
              size: const Size(64, 92),
            );
            final assetPath = theme.imageAssetFor(request);

            final key = '${theme.id}:${identity.rank.name}:'
                '${identity.suit.name}';

            if (_knownBadAssets.contains(key)) {
              // Known-bad assets MUST be bypassed so the code-rendered
              // painter takes over and draws the correct identity.
              expect(
                assetPath,
                isNull,
                reason: '$key is on the known-bad list - the theme must '
                    'return null so the code-rendered fallback paints the '
                    'correct identity. Got "$assetPath".',
              );
              return;
            }

            if (assetPath == null) {
              // A theme is allowed to return null for any identity (it falls
              // back to the painter). Nothing more to check.
              return;
            }

            final rankSlug = _rankSlugs[identity.rank]!;
            final suitSlug = identity.suit.name;
            expect(
              assetPath.contains(rankSlug),
              isTrue,
              reason: '$key returned "$assetPath" which does not contain '
                  'rank slug "$rankSlug".',
            );
            expect(
              assetPath.contains(suitSlug),
              isTrue,
              reason: '$key returned "$assetPath" which does not contain '
                  'suit slug "$suitSlug".',
            );
          },
        );
      }
    });
  }
}
