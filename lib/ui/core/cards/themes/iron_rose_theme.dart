import 'package:flutter/material.dart';

import '../card_asset_manifest.dart';
import '../card_painting.dart';
import '../card_theme.dart';

/// Iron Rose first-party generated-art deck for Hareeg Table.
///
/// Uses compressed WebP assets converted from the Iron Rose source folder.
class IronRoseCardTheme extends HareegCardTheme
    implements AssetManifestCardTheme {
  /// Creates the theme.
  const IronRoseCardTheme();

  static const _assetRoot = 'assets/cards/iron_rose';
  static final CardAssetManifest _manifest = CardAssetManifest.standardDeck(
    assetRoot: _assetRoot,
    back: '$_assetRoot/back.webp',
    redJoker: '$_assetRoot/joker_red.webp',
    blackJoker: '$_assetRoot/joker_black.webp',
  );

  static const _palette = CardThemePalette(
    faceBackground: Color(0xFF2B3338),
    faceBorder: Color(0xFF9FA6A9),
    faceShadow: Color(0x55000000),
    redSuit: Color(0xFF8E1E21),
    blackSuit: Color(0xFF101417),
    jokerAccent: Color(0xFFB83A30),
    backPrimary: Color(0xFF202428),
    backSecondary: Color(0xFF7C1C1E),
    backOrnament: Color(0xFFC1B5A3),
    faceText: Color(0xFFEFE8DD),
    faceBorderWidth: 1.2,
  );

  @override
  String get id => 'iron_rose';

  @override
  String get label => 'Iron Rose';

  @override
  String get description =>
      'Generated first-party deck with crimson courts, graphite suits, and sharp silver borders.';

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
