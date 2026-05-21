import 'package:flutter/material.dart';

import '../../../../domain/classic_hareeg/models/playing_card.dart';
import '../../theme/lounge_tokens.dart';
import '../card_painting.dart';
import '../card_theme.dart';

/// First-party generated-art deck for the Warm Sudanese Lounge direction.
///
/// Uses medium-resolution lossless WebP assets to keep the internal theme
/// package small while preserving the generated sand-line artwork.
class SandlineLoungeCardTheme extends HareegCardTheme {
  /// Creates the theme.
  const SandlineLoungeCardTheme();

  static const _assetRoot = 'assets/cards/sandline_lounge';

  static const _palette = CardThemePalette(
    faceBackground: LoungeTokens.cardIvory,
    faceBorder: LoungeTokens.sandLine,
    faceShadow: Color(0x33000000),
    redSuit: LoungeTokens.deepRed,
    blackSuit: LoungeTokens.coffeeCharcoal,
    jokerAccent: LoungeTokens.fiftyFlame,
    backPrimary: LoungeTokens.coffeeCharcoal,
    backSecondary: LoungeTokens.feltGreen,
    backOrnament: LoungeTokens.sandLine,
    faceText: LoungeTokens.coffeeCharcoal,
  );

  @override
  String get id => 'sandline_lounge';

  @override
  String get label => 'Sandline Lounge';

  @override
  String get description =>
      'Generated first-party deck with ivory faces, sand-line borders, and lounge court art.';

  @override
  CardThemeAssetSource get source => CardThemeAssetSource.bundledAssets;

  @override
  String? get licenseAttribution =>
      'Original generated artwork for Hareeg Table. Internal prototype asset set.';

  @override
  String? get sourceUrl => null;

  @override
  bool get readableOnCompactLayouts => true;

  @override
  String? imageAssetFor(CardRenderRequest request) {
    if (request.faceDown || request.variant == CardVariant.back) {
      return '$_assetRoot/back.webp';
    }

    if (request.card.isJoker) {
      final suffix = (request.card.jokerIndex ?? 0).isEven ? 'red' : 'black';
      return '$_assetRoot/joker_$suffix.webp';
    }

    final identity = request.card.identity ?? request.card.representedIdentity;
    if (identity == null) {
      return null;
    }

    return '$_assetRoot/${_rankSlug(identity.rank)}_${identity.suit.name}.webp';
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
