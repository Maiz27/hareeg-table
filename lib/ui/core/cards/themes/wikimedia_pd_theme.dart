import 'package:flutter/material.dart';

import '../../../../domain/classic_hareeg/models/playing_card.dart';
import '../card_painting.dart';
import '../card_theme.dart';

/// Bundled Wikimedia Commons English-pattern face-card theme.
class WikimediaPdCardTheme extends HareegCardTheme {
  /// Creates the theme.
  const WikimediaPdCardTheme();

  static const _palette = CardThemePalette(
    faceBackground: Color(0xFFFBFBF6),
    faceBorder: Color(0xFF35332E),
    faceShadow: Color(0x33000000),
    redSuit: Color(0xFFC32232),
    blackSuit: Color(0xFF1B1916),
    jokerAccent: Color(0xFF2F6F8B),
    backPrimary: Color(0xFF1F4A6B),
    backSecondary: Color(0xFF0D2538),
    backOrnament: Color(0xFFE0E6EE),
    faceText: Color(0xFF1B1916),
    faceBorderWidth: 1.3,
  );

  @override
  String get id => 'wikimedia_english_pattern';

  @override
  String get label => 'Wikimedia English';

  @override
  String get description =>
      'English-pattern CC0 face cards from Dmitry Fomin\'s Wikimedia deck.';

  @override
  CardThemeAssetSource get source => CardThemeAssetSource.bundledAssets;

  @override
  String? get licenseAttribution =>
      'English pattern playing cards deck.svg by Dmitry Fomin - CC0 1.0 Universal.';

  @override
  String? get sourceUrl =>
      'https://commons.wikimedia.org/wiki/File:English_pattern_playing_cards_deck.svg';

  @override
  bool get readableOnCompactLayouts => true;

  @override
  String? imageAssetFor(CardRenderRequest request) {
    if (request.faceDown ||
        request.variant == CardVariant.back ||
        request.card.isJoker) {
      return null;
    }

    final identity = request.card.identity ?? request.card.representedIdentity;
    if (identity == null) {
      return null;
    }
    return 'assets/cards/wikimedia_english/'
        '${_rankSlug(identity.rank)}_${identity.suit.name}.png';
  }

  @override
  void paint(Canvas canvas, CardRenderRequest request) {
    if (request.faceDown || request.variant == CardVariant.back) {
      CardPainting.paintBack(canvas, request, _palette);
      return;
    }
    CardPainting.paintBody(canvas, request, _palette);
    if (request.card.isJoker) {
      CardPainting.paintJokerFace(canvas, request, _palette);
    } else {
      CardPainting.paintStandardFace(canvas, request, _palette);
    }
  }

  static String _rankSlug(CardRank rank) {
    return switch (rank) {
      CardRank.ace => 'ace',
      CardRank.two => 'two',
      CardRank.three => 'three',
      CardRank.four => 'four',
      CardRank.five => 'five',
      CardRank.six => 'six',
      CardRank.seven => 'seven',
      CardRank.eight => 'eight',
      CardRank.nine => 'nine',
      CardRank.ten => 'ten',
      CardRank.jack => 'jack',
      CardRank.queen => 'queen',
      CardRank.king => 'king',
    };
  }
}
