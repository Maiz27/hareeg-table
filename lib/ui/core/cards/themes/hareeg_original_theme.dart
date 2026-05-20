import 'package:flutter/material.dart';

import '../../theme/lounge_tokens.dart';
import '../card_painting.dart';
import '../card_theme.dart';

/// Default card theme — palette-native, code-rendered, with the shared
/// geometric motif on the back.
class HareegOriginalCardTheme extends HareegCardTheme {
  /// Creates the theme.
  const HareegOriginalCardTheme();

  static const _palette = CardThemePalette(
    faceBackground: LoungeTokens.cardIvory,
    faceBorder: LoungeTokens.sandLine,
    faceShadow: Color(0x33000000),
    redSuit: LoungeTokens.deepRed,
    blackSuit: LoungeTokens.coffeeCharcoal,
    jokerAccent: LoungeTokens.fiftyFlame,
    backPrimary: LoungeTokens.indigoAccent,
    backSecondary: LoungeTokens.coffeeCharcoal,
    backOrnament: LoungeTokens.sandLine,
    faceText: LoungeTokens.coffeeCharcoal,
  );

  @override
  String get id => 'hareeg_original';

  @override
  String get label => 'Hareeg Original';

  @override
  String get description =>
      'Warm Sudanese lounge palette, code-rendered. Designed for this app.';

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
