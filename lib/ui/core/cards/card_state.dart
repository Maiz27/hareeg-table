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

  /// Coaching-tier hint highlight: the coach is pointing at this card as the
  /// reference of the current insight. Drawn as a reserved teal outline + glow
  /// ring (never a face tint) so it reads distinctly from every other state
  /// and stays legible across all card themes.
  coachHighlight,

  /// Illegal action attempted on or with this card (transient).
  invalid,
}

/// Painting recipe for a single card state.
///
/// Themes can override colours per-state if their palette needs a different
/// outline, but the defaults work for every code-rendered theme.
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
  static final CardStateOverlayMap map = {
    CardVisualState.normal: const CardStateOverlayStyle(
      outline: Colors.transparent,
      outlineWidth: 0,
    ),
    // Selected: a quiet sand ring with no halo glow. The card lift in
    // [_DraggableHandCard] does the heavy lifting for "selected" feedback;
    // the ring just confirms which cards are part of the current selection.
    CardVisualState.selected: const CardStateOverlayStyle(
      outline: LoungeTokens.stateSelected,
      outlineWidth: 2.5,
    ),
    CardVisualState.pending: CardStateOverlayStyle(
      outline: LoungeTokens.statePending,
      outlineWidth: 2.5,
      tint: LoungeTokens.statePending.withValues(alpha: 0.13),
    ),
    // Cover target: a legal drop on the table, so it shares the selection hue.
    CardVisualState.coverTarget: CardStateOverlayStyle(
      outline: LoungeTokens.stateSelected,
      tint: LoungeTokens.stateSelected.withValues(alpha: 0.1),
      outlineWidth: 2,
    ),
    // Coach highlight: teal outline + soft glow, no face tint. The glow makes
    // the ring read as "look here" without recolouring the card itself, so it
    // stays legible over every deck art and table surface.
    CardVisualState.coachHighlight: const CardStateOverlayStyle(
      outline: LoungeTokens.coachHighlight,
      outlineWidth: 3,
      glow: LoungeTokens.coachGlow,
    ),
    CardVisualState.invalid: const CardStateOverlayStyle(
      outline: LoungeTokens.stateInvalid,
      outlineWidth: 3,
      iconColor: LoungeTokens.stateInvalid,
    ),
  };
}

/// Stronger state overlays used by the high-contrast accessibility setting.
///
/// These are intentionally overlay-only: they sit above the selected card
/// theme so generated and bundled deck art stays unchanged.
abstract final class HighContrastCardStateOverlays {
  /// High-contrast overlay map.
  static const CardStateOverlayMap map = {
    CardVisualState.normal: CardStateOverlayStyle(
      outline: Colors.transparent,
      outlineWidth: 0,
    ),
    CardVisualState.selected: CardStateOverlayStyle(
      outline: LoungeTokens.highContrastSelected,
      outlineWidth: 4,
      glow: LoungeTokens.highContrastSelectedGlow,
    ),
    CardVisualState.pending: CardStateOverlayStyle(
      outline: LoungeTokens.highContrastPending,
      outlineWidth: 4,
      glow: LoungeTokens.highContrastPendingGlow,
      tint: LoungeTokens.highContrastPendingTint,
    ),
    CardVisualState.coverTarget: CardStateOverlayStyle(
      outline: LoungeTokens.highContrastCover,
      outlineWidth: 3.5,
      tint: LoungeTokens.highContrastCoverTint,
    ),
    CardVisualState.coachHighlight: CardStateOverlayStyle(
      outline: LoungeTokens.highContrastCoach,
      outlineWidth: 4,
      glow: LoungeTokens.highContrastCoachGlow,
    ),
    CardVisualState.invalid: CardStateOverlayStyle(
      outline: LoungeTokens.highContrastInvalid,
      outlineWidth: 4,
      iconColor: LoungeTokens.highContrastInvalid,
    ),
  };

  /// Resolves a high-contrast overlay while preserving normal unmarked cards.
  static CardStateOverlayStyle resolve(
    CardVisualState state,
    CardStateOverlayStyle fallback,
  ) {
    if (state == CardVisualState.normal) {
      return fallback;
    }
    return map[state] ?? fallback;
  }
}
