import 'package:flutter/material.dart';

import '../../theme/lounge_tokens.dart';
import '../card_painting.dart';
import '../card_theme.dart';

/// `const` value-object definitions for every bundled card theme.
///
/// Each [HareegCardTheme] here used to be its own subclass under
/// `themes/{name}_theme.dart`. The refactor in ADR-0002's 2026-05-25 update
/// collapsed those into data: palette + asset manifest + optional paint
/// extras. The `id` strings are persisted to preferences, so they MUST stay
/// stable — changing any of them orphans saved player preferences.

/// Generated first-party Warm Sudanese Lounge deck. WebP-backed faces, back,
/// and jokers.
const HareegCardTheme sandlineLoungeCardTheme = HareegCardTheme(
  id: 'sandline_lounge',
  label: 'Sandline Lounge',
  description:
      'Generated first-party deck with ivory faces, sand-line borders, and lounge court art.',
  source: CardThemeAssetSource.bundledAssets,
  licenseAttribution:
      'Original generated artwork for Hareeg Table. Internal prototype asset set.',
  readableOnCompactLayouts: true,
  palette: CardThemePalette(
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
  ),
  assetManifest: CardThemeAssetManifest(
    root: 'assets/cards/sandline_lounge',
    extension: 'webp',
  ),
);

/// Generated first-party deck with crimson courts, graphite suits, and sharp
/// silver borders. WebP-backed faces, back, and jokers.
const HareegCardTheme ironRoseCardTheme = HareegCardTheme(
  id: 'iron_rose',
  label: 'Iron Rose',
  description:
      'Generated first-party deck with crimson courts, graphite suits, and sharp silver borders.',
  source: CardThemeAssetSource.bundledAssets,
  licenseAttribution:
      'Original generated artwork for Hareeg Table. Internal prototype asset set.',
  readableOnCompactLayouts: true,
  palette: CardThemePalette(
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
  ),
  assetManifest: CardThemeAssetManifest(
    root: 'assets/cards/iron_rose',
    extension: 'webp',
  ),
);

/// Code-rendered theme with oversized rank glyph and a single small suit
/// pip. Designed to scan quickly from across the table.
const HareegCardTheme minimalSymbolsCardTheme = HareegCardTheme(
  id: 'minimal_symbols',
  label: 'Minimal Symbols',
  description:
      'Big rank glyphs and small suit pips. Easiest to scan from across the table.',
  source: CardThemeAssetSource.codeRendered,
  licenseAttribution: 'Original artwork for Hareeg Table. CC BY-NC 4.0.',
  sourceUrl: 'https://github.com/Maiz27/hareeg-table',
  readableOnCompactLayouts: true,
  palette: CardThemePalette(
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
  ),
);

/// Kenney.nl CC0 pixel-art deck. PNG-backed faces, jokers, and back.
///
/// The single bundled theme with a `paintExtras` callback: a faint
/// sand-line stroke runs across the middle of the painted face. Every
/// other bundled theme leaves `paintExtras` null and relies entirely on
/// the shared [CardPainting] helpers.
const HareegCardTheme kenneyClassicCardTheme = HareegCardTheme(
  id: 'kenney_classic',
  label: 'Kenney Classic',
  description:
      "Pixel-art classic deck from Kenney.nl's CC0 Playing Cards Pack.",
  source: CardThemeAssetSource.bundledAssets,
  licenseAttribution: 'Kenney.nl Playing Cards Pack - CC0 1.0 Universal.',
  sourceUrl: 'https://kenney.nl/assets/playing-cards-pack',
  readableOnCompactLayouts: true,
  palette: CardThemePalette(
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
  ),
  assetManifest: CardThemeAssetManifest(
    root: 'assets/cards/kenney_classic',
    extension: 'png',
  ),
  paintExtras: _paintKenneyFlourish,
);

/// Wikimedia Commons CC0 English-pattern face-card subset.
///
/// Bundled-asset theme that ships ONLY the standard rank/suit faces.
/// Joker and back artwork is intentionally absent — the manifest's
/// `hasBack: false` / `hasJokers: false` flags route those through the
/// code-rendered painter while still using the same palette.
const HareegCardTheme wikimediaPdCardTheme = HareegCardTheme(
  id: 'wikimedia_english_pattern',
  label: 'Wikimedia English',
  description:
      "English-pattern CC0 face cards from Dmitry Fomin's Wikimedia deck.",
  source: CardThemeAssetSource.bundledAssets,
  licenseAttribution:
      'English pattern playing cards deck.svg by Dmitry Fomin - CC0 1.0 Universal.',
  sourceUrl:
      'https://commons.wikimedia.org/wiki/File:English_pattern_playing_cards_deck.svg',
  readableOnCompactLayouts: true,
  palette: CardThemePalette(
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
  ),
  assetManifest: CardThemeAssetManifest(
    root: 'assets/cards/wikimedia_english',
    extension: 'png',
    hasBack: false,
    hasJokers: false,
  ),
);

/// Kenney Classic's one extra flourish: a faint sand-line stroke across the
/// painted face. Pulled out as a top-level function so it can sit inside
/// the `const` theme literal above. The framework only invokes paint extras
/// in the face branch, so no back/face-down guard is needed here.
void _paintKenneyFlourish(Canvas canvas, CardRenderRequest request) {
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
