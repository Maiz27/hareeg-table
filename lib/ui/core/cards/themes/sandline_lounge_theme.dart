import 'package:flutter/material.dart';

import '../card_asset_manifest.dart';
import '../../theme/lounge_tokens.dart';
import '../card_painting.dart';
import '../card_theme.dart';

/// First-party generated-art deck for the Warm Sudanese Lounge direction.
///
/// Uses medium-resolution lossless WebP assets to keep the internal theme
/// package small while preserving the generated sand-line artwork.
class SandlineLoungeCardTheme extends HareegCardTheme
    implements AssetManifestCardTheme {
  /// Creates the theme.
  const SandlineLoungeCardTheme();

  static const _assetRoot = 'assets/cards/sandline_lounge';
  static final CardAssetManifest _manifest = CardAssetManifest.standardDeck(
    assetRoot: _assetRoot,
    back: '$_assetRoot/back.webp',
    redJoker: '$_assetRoot/joker_red.webp',
    blackJoker: '$_assetRoot/joker_black.webp',
  );

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
  CardAssetManifest get assetManifest => _manifest;

  @override
  String? imageAssetFor(CardRenderRequest request) {
    return assetManifest.assetFor(request);
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
}
