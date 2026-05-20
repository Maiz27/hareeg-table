import 'package:flutter/material.dart';

import '../../../domain/classic_hareeg/models/playing_card.dart';
import 'card_state.dart';

/// Origin of a card theme's assets.
enum CardThemeAssetSource {
  /// Drawn entirely in Dart — no third-party assets.
  codeRendered,

  /// Bundled third-party assets (Kenney CC0, Wikimedia PD subset, etc.).
  bundledAssets,
}

/// Variant requested by a caller.
enum CardVariant {
  /// Full-size card (south seat hand, discard top, stock back).
  full,

  /// Compact meld card (opponent meld zones, fanned hands).
  compact,

  /// Picker card (legal meld combination picker).
  picker,

  /// Card back (stock pile, opponent hands).
  back,
}

/// Render mode for a joker.
enum JokerDisplay {
  /// Memory-aid: identity is briefly shown then quieted to the plain joker.
  memoryReveal,

  /// Default: represented identity is visible alongside the joker accent.
  assisted,

  /// Joker with no represented identity assigned yet.
  unassigned,
}

/// Optional badge drawn on top of the card face when the player should know
/// something extra about it (per-deck-copy distinction, joker memory aid).
enum CardBadge {
  /// No badge.
  none,

  /// Tiny pip in the corner that indicates which physical deck copy this
  /// card belongs to. Themes can choose to render it as a coloured dot.
  deckCopy,
}

/// Drawing request handed to a [CardTheme] paint method.
@immutable
class CardRenderRequest {
  /// Creates a render request.
  const CardRenderRequest({
    required this.card,
    required this.variant,
    required this.size,
    this.visualState = CardVisualState.normal,
    this.jokerDisplay = JokerDisplay.assisted,
    this.badge = CardBadge.none,
    this.faceDown = false,
  });

  /// Physical card being drawn (use [HareegCard.effectiveIdentity] for the
  /// face).
  final HareegCard card;

  /// Variant requested.
  final CardVariant variant;

  /// Render box size.
  final Size size;

  /// State overlay to apply.
  final CardVisualState visualState;

  /// How to render a joker's identity.
  final JokerDisplay jokerDisplay;

  /// Optional badge to draw on the face.
  final CardBadge badge;

  /// If true, draw the back regardless of [variant].
  final bool faceDown;
}

/// Contract every card theme implements.
///
/// One theme provides the painting for every variant (full / compact /
/// picker / back) plus a representation for jokers. State overlays are
/// applied generically — themes can override the overlay map if their
/// palette demands a different highlight set.
abstract class HareegCardTheme {
  /// Creates a card theme.
  const HareegCardTheme();

  /// Stable identifier persisted to preferences.
  String get id;

  /// Player-facing label.
  String get label;

  /// Short description shown in the theme picker.
  String get description;

  /// Whether the theme's assets are code-rendered or bundled.
  CardThemeAssetSource get source;

  /// Optional license attribution shown on Settings → About → Licenses.
  String? get licenseAttribution;

  /// Optional source URL shown on Settings → About → Licenses.
  String? get sourceUrl;

  /// Whether the compact/picker variants remain readable on the smallest
  /// supported Android landscape viewport.
  bool get readableOnCompactLayouts;

  /// Whether the theme is currently available to play with. Themes whose
  /// bundled assets are not yet sourced can ship disabled but still listed
  /// in the picker.
  bool get available => true;

  /// Disabled-reason copy used by the picker (e.g., "Asset bundle pending").
  String? get unavailableReason => null;

  /// Optional overlay map; themes that return null inherit
  /// [DefaultCardStateOverlays.map].
  CardStateOverlayMap? get overlayOverrides => null;

  /// Resolves the overlay style for a state, applying any theme override.
  CardStateOverlayStyle overlayFor(CardVisualState state) {
    final overrides = overlayOverrides;
    if (overrides != null && overrides.containsKey(state)) {
      return overrides[state]!;
    }
    return DefaultCardStateOverlays.map[state]!;
  }

  /// Optional bundled raster asset for this card.
  ///
  /// Code-rendered themes return null and paint everything on the canvas.
  /// Asset-backed themes return a path under `assets/` for faces/backs that
  /// should be composed by [HareegCardView] before the state overlay.
  String? imageAssetFor(CardRenderRequest request) => null;

  /// Paints the card for the given request.
  ///
  /// Themes are expected to draw the face / back inside the rect
  /// `Offset.zero & request.size`. The framework applies the state overlay
  /// afterwards using [overlayFor].
  void paint(Canvas canvas, CardRenderRequest request);
}
