import 'package:flutter/material.dart';

import '../../theme/lounge_tokens.dart';
import '../card_painting.dart';
import '../card_theme.dart';

/// Minimal Symbols theme — oversized rank glyph, deemphasized suit pip.
///
/// Designed for quick scanning when the table is busy. The corner indices
/// still carry the suit symbol for full rule clarity; the centre face shows
/// the rank only, with a single small suit pip below it.
class MinimalSymbolsCardTheme extends HareegCardTheme {
  /// Creates the theme.
  const MinimalSymbolsCardTheme();

  static const _palette = CardThemePalette(
    faceBackground: LoungeTokens.cardIvory,
    faceBorder: LoungeTokens.sandLine,
    faceShadow: Color(0x33000000),
    redSuit: LoungeTokens.deepRed,
    blackSuit: LoungeTokens.coffeeCharcoal,
    jokerAccent: LoungeTokens.fiftyFlame,
    backPrimary: LoungeTokens.feltGreen,
    backSecondary: LoungeTokens.coffeeCharcoal,
    backOrnament: LoungeTokens.goldAccent,
    faceText: LoungeTokens.coffeeCharcoal,
    minimalGlyph: true,
  );

  @override
  String get id => 'minimal_symbols';

  @override
  String get label => 'Minimal Symbols';

  @override
  String get description =>
      'Big rank glyphs and small suit pips. Easiest to scan from across the table.';

  @override
  CardThemeAssetSource get source => CardThemeAssetSource.codeRendered;

  @override
  String? get licenseAttribution =>
      'Original artwork for Hareeg Table. CC BY-NC 4.0.';

  @override
  String? get sourceUrl => 'https://github.com/Maiz27/hareeg-table';

  @override
  bool get readableOnCompactLayouts => true;

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
