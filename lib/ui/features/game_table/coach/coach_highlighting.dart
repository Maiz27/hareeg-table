import 'package:flutter/material.dart';

import '../../../../cpu/classic_hareeg/coaching/coaching_insight.dart';
import '../../../core/theme/lounge_tokens.dart';
import 'coach_hint.dart';

/// Bundles the coach-highlight state a [CoachHint] projects onto the table into
/// one immutable value-object, and owns the ring-colour resolution that used to
/// live inline in the south hand fan.
///
/// A hint decomposes into four parallel facts about which cards (and the stock)
/// the coach is pointing at:
///
/// - [highlightIds]: cards ringed in the default teal "keep" hue.
/// - [groupOf]: hand-card id -> meld-group index, so each distinct meld a hint
///   points at rings in its own cool hue ([LoungeTokens.coachRingPalette]).
/// - [discardIds]: the single card a hint recommends letting go, ringed in the
///   warm rose discard hue.
/// - [highlightStock]: whether the stock pile should ring (the draw hint).
///
/// Build one with [CoachHighlighting.fromHint]; pass the single object down the
/// playfield instead of the four collections individually.
@immutable
class CoachHighlighting {
  /// Creates a highlighting bundle directly.
  const CoachHighlighting({
    this.highlightIds = const {},
    this.groupOf = const {},
    this.discardIds = const {},
    this.highlightStock = false,
  });

  /// Empty highlighting — nothing rings. Used when there is no active hint.
  static const none = CoachHighlighting();

  /// Builds the highlighting projection for [hint], or [none] when null.
  ///
  /// Flattens [CoachHint.ringGroups] into a card-id -> group-index map so the
  /// table can ring each meld in its own hue, and lifts the draw hint's stock
  /// pointer into [highlightStock].
  factory CoachHighlighting.fromHint(CoachHint? hint) {
    if (hint == null) return none;
    final groups = <String, int>{};
    for (var group = 0; group < hint.ringGroups.length; group += 1) {
      for (final id in hint.ringGroups[group]) {
        groups[id] = group;
      }
    }
    return CoachHighlighting(
      highlightIds: hint.ringCardIds.toSet(),
      groupOf: groups,
      discardIds: hint.discardRingCardIds.toSet(),
      highlightStock: hint.category == CoachingInsightCategory.drawStock,
    );
  }

  /// Card ids ringed in the default teal "keep" hue.
  final Set<String> highlightIds;

  /// Hand-card id -> meld-group index, so each meld a hint points at rings in
  /// its own cool hue. Cards highlighted without a group fall back to teal.
  final Map<String, int> groupOf;

  /// Card ids the coaching tier recommends discarding (warm rose ring).
  final Set<String> discardIds;

  /// True when the coaching tier is pointing at the stock pile (draw hint).
  final bool highlightStock;

  /// Whether [cardId] should ring at all (in any coach hue).
  bool highlights(String cardId) =>
      discardIds.contains(cardId) ||
      groupOf.containsKey(cardId) ||
      highlightIds.contains(cardId);

  /// Resolves the override ring colour for [cardId], following the table's
  /// fixed precedence:
  ///
  /// 1. a discard-ring card wins the warm rose [LoungeTokens.coachDiscard];
  /// 2. else a grouped card takes its palette hue
  ///    ([LoungeTokens.coachRingPalette] indexed by group, group 0 being teal);
  /// 3. else a plainly-highlighted card returns null, meaning "use the default
  ///    teal coach overlay" (which keeps its theme-defined glow and the
  ///    high-contrast outline);
  /// 4. a card that isn't highlighted at all also returns null.
  ///
  /// Pair with [highlights] to tell case 3 apart from case 4 — null here means
  /// "no colour override", not "not highlighted".
  Color? ringColorFor(String cardId) {
    if (discardIds.contains(cardId)) {
      return LoungeTokens.coachDiscard;
    }
    final group = groupOf[cardId];
    if (group != null) {
      return LoungeTokens
          .coachRingPalette[group % LoungeTokens.coachRingPalette.length];
    }
    return null;
  }
}
