import 'package:flutter/material.dart';

import '../../theme/lounge_tokens.dart';
import '../card_asset_manifest.dart';
import '../card_painting.dart';
import '../card_theme.dart';

/// Bundled Kenney.nl CC0 pixel-art card theme.
class KenneyClassicCardTheme extends HareegCardTheme
    implements AssetManifestCardTheme {
  /// Creates the theme.
  const KenneyClassicCardTheme();

  static const _assetRoot = 'assets/cards/kenney_classic';
  static final CardAssetManifest _manifest = CardAssetManifest.standardDeck(
    assetRoot: _assetRoot,
    back: '$_assetRoot/back.png',
    redJoker: '$_assetRoot/joker_red.png',
    blackJoker: '$_assetRoot/joker_black.png',
    extension: 'png',
  );

  static const _palette = CardThemePalette(
    faceBackground: Color(0xFFF6EFE0),
    faceBorder: Color(0xFF5A4938),
    faceShadow: Color(0x33000000),
    redSuit: Color(0xFFB23A2A),
    blackSuit: Color(0xFF1F1A14),
    jokerAccent: Color(0xFFD27A1F),
    backPrimary: Color(0xFF7D2A24),
    backSecondary: Color(0xFF4A1812),
    backOrnament: Color(0xFFE7C685),
    faceText: Color(0xFF1F1A14),
    faceBorderWidth: 1.4,
  );

  @override
  String get id => 'kenney_classic';

  @override
  String get label => 'Kenney Classic';

  @override
  String get description =>
      'Pixel-art classic deck from Kenney.nl\'s CC0 Playing Cards Pack.';

  @override
  CardThemeAssetSource get source => CardThemeAssetSource.bundledAssets;

  @override
  String? get licenseAttribution =>
      'Kenney.nl Playing Cards Pack - CC0 1.0 Universal.';

  @override
  String? get sourceUrl => 'https://kenney.nl/assets/playing-cards-pack';

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
    _paintFlourish(canvas, request);
  }

  void _paintFlourish(Canvas canvas, CardRenderRequest request) {
    final size = request.size;
    final paint = Paint()
      ..color = LoungeTokens.sandLine.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawLine(
      Offset(size.width * 0.18, size.height * 0.5),
      Offset(size.width * 0.82, size.height * 0.5),
      paint,
    );
  }
}
