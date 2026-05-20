import 'package:flutter/material.dart';

import '../theme/lounge_tokens.dart';

/// Visual state a card can be in at the table.
///
/// Themes paint the card face and back, and the framework layers a
/// state-specific overlay on top using [CardStateOverlayStyle]. Keeping
/// states enum-led means a future theme cannot accidentally drop a state and
/// silently leave illegal targets uncoloured.
enum CardVisualState {
  /// Default — no overlay.
  normal,

  /// Selected for meld assembly.
  selected,

  /// Pending discard (just taken from the discard pile, must be used or
  /// returned this turn).
  pending,

  /// Drag-target highlight when the card is a legal cover target.
  coverTarget,

  /// Drag-target highlight when the card is a legal joker replacement.
  jokerReplaceTarget,

  /// Illegal action attempted on or with this card (transient).
  invalid,

  /// Card is owned by an eliminated seat (or for some reason cannot be
  /// played right now).
  disabled,
}

/// Painting recipe for a single card state.
///
/// Themes can override colours per-state if their palette needs a different
/// outline (for example, the High Contrast theme uses pure black/yellow), but
/// the defaults work for every code-rendered theme.
@immutable
class CardStateOverlayStyle {
  /// Creates an overlay style.
  const CardStateOverlayStyle({
    required this.outline,
    this.outlineWidth = 2.5,
    this.glow,
    this.tint,
    this.iconColor,
  });

  /// Outline colour painted around the card edge.
  final Color outline;

  /// Outline stroke width.
  final double outlineWidth;

  /// Optional soft glow drawn outside the outline.
  final Color? glow;

  /// Optional translucent tint laid over the card face.
  final Color? tint;

  /// Optional icon colour used by the framework where state needs a glyph
  /// (e.g., a small `!` for invalid).
  final Color? iconColor;
}

/// Lookup table mapping [CardVisualState] -> [CardStateOverlayStyle].
typedef CardStateOverlayMap = Map<CardVisualState, CardStateOverlayStyle>;

/// Default state overlays used by every code-rendered theme unless they
/// override on a per-state basis.
abstract final class DefaultCardStateOverlays {
  /// Default overlay map.
  static const CardStateOverlayMap map = {
    CardVisualState.normal: CardStateOverlayStyle(
      outline: Colors.transparent,
      outlineWidth: 0,
    ),
    // Selected: a quiet gold ring with no halo glow. The card lift in
    // [_DraggableHandCard] does the heavy lifting for "selected" feedback;
    // the ring just confirms which cards are part of the current selection.
    CardVisualState.selected: CardStateOverlayStyle(
      outline: LoungeTokens.goldAccent,
      outlineWidth: 2.5,
    ),
    CardVisualState.pending: CardStateOverlayStyle(
      outline: LoungeTokens.pendingDiscard,
      outlineWidth: 2.5,
      tint: Color(0x22E0A848),
    ),
    CardVisualState.coverTarget: CardStateOverlayStyle(
      outline: LoungeTokens.goldAccent,
      tint: Color(0x1AD69B35),
      outlineWidth: 2,
    ),
    CardVisualState.jokerReplaceTarget: CardStateOverlayStyle(
      outline: LoungeTokens.fiftyFlame,
      tint: Color(0x22EF5A24),
      outlineWidth: 2.5,
    ),
    CardVisualState.invalid: CardStateOverlayStyle(
      outline: LoungeTokens.invalidAction,
      outlineWidth: 3,
      iconColor: LoungeTokens.invalidAction,
    ),
    CardVisualState.disabled: CardStateOverlayStyle(
      outline: Colors.transparent,
      tint: LoungeTokens.eliminatedDim,
      outlineWidth: 0,
    ),
  };
}
