import 'package:flutter/material.dart';

import '../card_painting.dart';
import '../card_state.dart';
import '../card_theme.dart';

/// Accessibility-first theme tuned for AAA contrast (7:1 text, 4.5:1 UI).
///
/// Card face is near-white, suit colours are pure black / strong red, and
/// outlines use bright cyan / yellow so colour-blind users have clear state
/// markers in addition to shape/icon.
class HighContrastCardTheme extends HareegCardTheme {
  /// Creates the theme.
  const HighContrastCardTheme();

  static const _palette = CardThemePalette(
    faceBackground: Color(0xFFFAFAF7),
    faceBorder: Color(0xFF111111),
    faceShadow: Color(0x66000000),
    redSuit: Color(0xFFC00000),
    blackSuit: Color(0xFF000000),
    jokerAccent: Color(0xFFC4A800),
    backPrimary: Color(0xFF000000),
    backSecondary: Color(0xFF1A1A1A),
    backOrnament: Color(0xFFE8C700),
    faceText: Color(0xFF000000),
    faceBorderWidth: 1.6,
  );

  @override
  String get id => 'high_contrast';

  @override
  String get label => 'High Contrast';

  @override
  String get description =>
      'AAA contrast palette. Bigger borders, denser glyphs, brighter state markers.';

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
  CardStateOverlayMap? get overlayOverrides => const {
    CardVisualState.selected: CardStateOverlayStyle(
      outline: Color(0xFFFFD400),
      outlineWidth: 4,
      glow: Color(0xCCFFD400),
    ),
    CardVisualState.pending: CardStateOverlayStyle(
      outline: Color(0xFFFF6F00),
      outlineWidth: 4,
      glow: Color(0xCCFF6F00),
      tint: Color(0x33FF6F00),
    ),
    CardVisualState.coverTarget: CardStateOverlayStyle(
      outline: Color(0xFF00B7D4),
      outlineWidth: 3.5,
      tint: Color(0x3300B7D4),
    ),
    CardVisualState.jokerReplaceTarget: CardStateOverlayStyle(
      outline: Color(0xFFC4A800),
      outlineWidth: 3.5,
      tint: Color(0x44C4A800),
    ),
    CardVisualState.invalid: CardStateOverlayStyle(
      outline: Color(0xFFC00000),
      outlineWidth: 4,
      iconColor: Color(0xFFC00000),
    ),
    CardVisualState.disabled: CardStateOverlayStyle(
      outline: Colors.transparent,
      outlineWidth: 0,
      tint: Color(0xCC000000),
    ),
  };

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
