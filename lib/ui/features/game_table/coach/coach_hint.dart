import 'package:flutter/material.dart';

import '../../../../cpu/classic_hareeg/coaching/coaching_insight.dart';
import '../../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../../l10n/app_strings.dart';

/// Resolves a physical card id to its effective identity for hint copy.
///
/// Returns null when the id is unknown or the card has no resolved identity
/// (e.g. an unassigned joker); the presenter falls back to a generic noun.
typedef CoachIdentityLookup = CardIdentity? Function(String cardId);

/// Which zone of the table a hint is anchored to. The callout sits in the
/// zone; the coach ring on [CoachHint.ringCardIds] does the precise pointing.
enum CoachZone {
  /// The human hand (bottom of the table).
  hand,

  /// The central discard pile.
  discard,
}

/// How loudly a hint presents.
enum CoachIntensity {
  /// Persistent, low-key guidance with a dismiss affordance.
  quiet,

  /// An urgent moment (finish / Fifty) that scales in to centre stage.
  popIn,
}

/// Accent palette a callout uses. Teal is the default coach colour; finish is
/// a celebratory gold; Fifty is the reserved flame (the one heat exception).
enum CoachAccent { coach, finish, fifty }

/// A fully localized, presentation-ready coaching hint derived from one
/// [CoachingInsight]. The engine emits structured insights with no strings;
/// [CoachHintPresenter] turns the top insight into this UI model.
@immutable
class CoachHint {
  /// Creates a coach hint.
  const CoachHint({
    required this.category,
    required this.title,
    required this.body,
    required this.icon,
    required this.zone,
    required this.intensity,
    required this.accent,
    required this.ringCardIds,
    required this.situationKey,
    this.ringGroups = const [],
    this.discardRingCardIds = const [],
  });

  /// Source insight category (drives icon/zone/intensity and tests).
  final CoachingInsightCategory category;

  /// Short eyebrow-style headline.
  final String title;

  /// One-line explanation.
  final String body;

  /// Leading icon.
  final IconData icon;

  /// Zone the callout anchors to.
  final CoachZone zone;

  /// Presentation intensity.
  final CoachIntensity intensity;

  /// Accent palette for the callout.
  final CoachAccent accent;

  /// Card ids the table should ring with the coach highlight. May be empty
  /// (e.g. the Fifty insight, where the flame Fifty cue already marks the
  /// discard, so a second teal ring would clash).
  final List<String> ringCardIds;

  /// Stable identity for this hint's *situation*. The coach overlay keys its
  /// entrance animation on this so the callout re-animates only when the
  /// situation actually changes (and stays put while the same hint persists).
  /// Derived from the category plus the insight's highlight ids (not
  /// [ringCardIds], so the Fifty hint still has a stable key even though it
  /// rings nothing).
  final String situationKey;

  /// Hand-card ids grouped by the meld they form, so the table can ring each
  /// meld in a distinct coach hue. Empty when the hint has no meld grouping.
  final List<List<String>> ringGroups;

  /// Card ids the table should ring in the warm "let this go" discard hue,
  /// distinct from the cool keep rings. Used when a hint both shows what to keep
  /// and recommends a specific card to discard. Empty when there is none.
  final List<String> discardRingCardIds;
}

/// Maps a structured [CoachingInsight] to a localized [CoachHint].
abstract final class CoachHintPresenter {
  /// Builds a presentation hint for [insight], or null when it cannot be
  /// rendered. [topDiscardIdentity] is the effective identity of the current
  /// top discard, used by the Fifty and pickup hints.
  static CoachHint present({
    required CoachingInsight insight,
    required AppStrings strings,
    required CoachIdentityLookup identityForCardId,
    required CardIdentity? topDiscardIdentity,
  }) {
    final key = _situationKey(insight);
    switch (insight.category) {
      case CoachingInsightCategory.finishAvailable:
        return CoachHint(
          category: insight.category,
          title: strings.coachFinishTitle,
          // Finish-by-cover (covering empties the hand) gets its own body so the
          // player knows to cover the rings rather than discard; a normal finish
          // keeps the generic "empty your hand to win" copy.
          body: insight.coverFinishes
              ? strings.coachCoverFinishBody
              : strings.coachFinishBody,
          icon: Icons.emoji_events_outlined,
          zone: CoachZone.hand,
          intensity: CoachIntensity.popIn,
          accent: CoachAccent.finish,
          ringCardIds: insight.highlightCardIds,
          ringGroups: insight.meldGroups,
          situationKey: key,
        );
      case CoachingInsightCategory.fiftyAvailable:
        return CoachHint(
          category: insight.category,
          title: strings.coachFiftyTitle,
          body: strings.coachFiftyBody(topDiscardIdentity),
          icon: Icons.local_fire_department,
          zone: CoachZone.discard,
          intensity: CoachIntensity.popIn,
          accent: CoachAccent.fifty,
          // The flame Fifty cue already rings the discard; leave it to that.
          ringCardIds: const [],
          situationKey: key,
        );
      case CoachingInsightCategory.openNow:
        return CoachHint(
          category: insight.category,
          title: strings.coachOpenNowTitle,
          body: strings.coachOpenNowBody,
          icon: Icons.lock_open_outlined,
          zone: CoachZone.hand,
          intensity: CoachIntensity.quiet,
          accent: CoachAccent.coach,
          ringCardIds: insight.highlightCardIds,
          ringGroups: insight.meldGroups,
          situationKey: key,
        );
      case CoachingInsightCategory.openingProgress:
        final requirement = insight.openingRequirement ?? 0;
        final best = insight.openingBestValue ?? 0;
        final shortfall = insight.openingShortfall ?? requirement;
        final progress = best <= 0
            ? strings.coachOpeningProgressNoMeldBody(requirement)
            : strings.coachOpeningProgressBody(
                requirement: requirement,
                best: best,
                shortfall: shortfall,
              );
        // Combine the keep guidance with the discard so a single hint says both
        // "build toward N (keep these)" and "throw this one" — the keep cards
        // ring teal/grouped, the discard card rings the warm discard hue. A
        // hold-back warning (the obvious throw is dangerous) rides along too.
        final openDiscardId = insight.discardCardId;
        var body = openDiscardId == null
            ? progress
            : '$progress ${strings.coachDiscardToBuildSuffix(
                identityForCardId(openDiscardId),
              )}';
        final openAvoid = _avoidSuffix(insight, strings, identityForCardId);
        if (openAvoid != null) {
          body = '$body $openAvoid';
        }
        return CoachHint(
          category: insight.category,
          title: strings.coachOpeningProgressTitle,
          body: body,
          icon: Icons.trending_up,
          zone: CoachZone.hand,
          intensity: CoachIntensity.quiet,
          accent: CoachAccent.coach,
          // The hold-back card rings in the cool keep hue: the message is
          // "this one stays in your hand for now".
          ringCardIds: [
            ...insight.highlightCardIds,
            if (insight.avoidCardId != null) insight.avoidCardId!,
          ],
          ringGroups: insight.meldGroups,
          discardRingCardIds: [?openDiscardId],
          situationKey: key,
        );
      case CoachingInsightCategory.playMeld:
        // Combine an available lay-off cover into the same hint (its card + meld
        // ring as a second group via meldGroups), so "play this meld" and "lay
        // off that card" surface together instead of the meld alone.
        final meldCoverId = insight.coverCardId;
        final meldBody = meldCoverId == null
            ? strings.coachPlayMeldBody
            : '${strings.coachPlayMeldBody} '
                  '${strings.coachPlayMeldAlsoCoverSuffix(
                identityForCardId(meldCoverId),
              )}';
        return CoachHint(
          category: insight.category,
          title: strings.coachPlayMeldTitle,
          body: meldBody,
          icon: Icons.style_outlined,
          zone: CoachZone.hand,
          intensity: CoachIntensity.quiet,
          accent: CoachAccent.coach,
          ringCardIds: insight.highlightCardIds,
          ringGroups: insight.meldGroups,
          situationKey: key,
        );
      case CoachingInsightCategory.pickupCompletesMeld:
        return CoachHint(
          category: insight.category,
          title: strings.coachPickupTitle,
          body: strings.coachPickupBody(topDiscardIdentity),
          icon: Icons.download_outlined,
          zone: CoachZone.discard,
          intensity: CoachIntensity.quiet,
          accent: CoachAccent.coach,
          ringCardIds: insight.highlightCardIds,
          situationKey: key,
        );
      case CoachingInsightCategory.playCover:
        final cardId = insight.coverCardId;
        return CoachHint(
          category: insight.category,
          title: strings.coachPlayCoverTitle,
          // When several independent covers exist, frame it as a choice; the
          // rings (grouped via meldGroups) show each option.
          body: insight.coverIsChoice
              ? strings.coachCoverChoiceBody
              : strings.coachPlayCoverBody(
                  cardId == null ? null : identityForCardId(cardId),
                ),
          icon: Icons.playlist_add,
          zone: CoachZone.hand,
          intensity: CoachIntensity.quiet,
          accent: CoachAccent.coach,
          ringCardIds: insight.highlightCardIds,
          ringGroups: insight.meldGroups,
          situationKey: key,
        );
      case CoachingInsightCategory.jokerAdvice:
        final cardId = insight.jokerCardId;
        return CoachHint(
          category: insight.category,
          title: strings.coachJokerTitle,
          body: strings.coachJokerBody(
            cardId == null ? null : identityForCardId(cardId),
          ),
          icon: Icons.swap_horiz,
          zone: CoachZone.hand,
          intensity: CoachIntensity.quiet,
          accent: CoachAccent.coach,
          ringCardIds: insight.highlightCardIds,
          situationKey: key,
        );
      case CoachingInsightCategory.discardSuggestion:
        final cardId = insight.discardCardId;
        var discardBody = strings.coachDiscardBody(
          cardId == null ? null : identityForCardId(cardId),
        );
        final discardAvoid = _avoidSuffix(insight, strings, identityForCardId);
        if (discardAvoid != null) {
          discardBody = '$discardBody $discardAvoid';
        }
        return CoachHint(
          category: insight.category,
          title: strings.coachDiscardTitle,
          body: discardBody,
          icon: Icons.upload_outlined,
          zone: CoachZone.hand,
          intensity: CoachIntensity.quiet,
          accent: CoachAccent.coach,
          // "Discard this" rings in the warm discard hue, not the teal keep
          // hue; the hold-back card (if any) rings cool — it stays in hand.
          ringCardIds: [?insight.avoidCardId],
          discardRingCardIds: [?cardId],
          situationKey: key,
        );
      case CoachingInsightCategory.takeAndFinish:
        return CoachHint(
          category: insight.category,
          title: strings.coachTakeAndFinishTitle,
          body: strings.coachTakeAndFinishBody(topDiscardIdentity),
          icon: Icons.emoji_events_outlined,
          zone: CoachZone.discard,
          intensity: CoachIntensity.popIn,
          accent: CoachAccent.finish,
          ringCardIds: insight.highlightCardIds,
          situationKey: key,
        );
      case CoachingInsightCategory.fiftyHold:
        return CoachHint(
          category: insight.category,
          title: strings.coachFiftyHoldTitle,
          body: insight.subjectIsSelf
              ? strings.coachFiftyHoldSelfBody(insight.subjectValue ?? 0)
              : strings.coachFiftyHoldTargetBody(
                  opponent: insight.subjectSeat!,
                  score: insight.subjectValue ?? 0,
                ),
          icon: Icons.local_fire_department,
          zone: CoachZone.hand,
          intensity: CoachIntensity.quiet,
          accent: CoachAccent.fifty,
          ringCardIds: insight.highlightCardIds,
          ringGroups: insight.meldGroups,
          situationKey: key,
        );
      case CoachingInsightCategory.scorePosture:
        return CoachHint(
          category: insight.category,
          title: insight.subjectIsSelf
              ? strings.coachScoreSelfTitle
              : strings.coachScoreTargetTitle,
          body: insight.subjectIsSelf
              ? strings.coachScoreSelfBody(
                  score: insight.subjectValue ?? 0,
                  threshold: insight.subjectThreshold ?? 31,
                )
              : strings.coachScoreTargetBody(
                  opponent: insight.subjectSeat!,
                  score: insight.subjectValue ?? 0,
                ),
          icon: Icons.leaderboard_outlined,
          zone: CoachZone.hand,
          intensity: CoachIntensity.quiet,
          accent: CoachAccent.coach,
          ringCardIds: const [],
          situationKey: key,
        );
      case CoachingInsightCategory.endgameStockLow:
        return CoachHint(
          category: insight.category,
          title: strings.coachStockLowTitle,
          body: strings.coachStockLowBody(insight.subjectValue ?? 0),
          icon: Icons.hourglass_bottom,
          zone: CoachZone.discard,
          intensity: CoachIntensity.quiet,
          accent: CoachAccent.coach,
          ringCardIds: const [],
          situationKey: key,
        );
      case CoachingInsightCategory.opponentCloseToFinish:
        return CoachHint(
          category: insight.category,
          title: strings.coachOpponentCloseTitle,
          body: strings.coachOpponentCloseBody(
            opponent: insight.subjectSeat!,
            count: insight.subjectValue ?? 0,
          ),
          icon: Icons.timer_outlined,
          zone: CoachZone.hand,
          intensity: CoachIntensity.quiet,
          accent: CoachAccent.coach,
          ringCardIds: const [],
          situationKey: key,
        );
      case CoachingInsightCategory.benchmarkAlert:
        return CoachHint(
          category: insight.category,
          title: strings.coachBenchmarkTitle,
          body: strings.coachBenchmarkBody(
            owner: insight.subjectSeat!,
            requirement: insight.openingRequirement ?? 0,
          ),
          icon: Icons.vertical_align_top,
          zone: CoachZone.hand,
          intensity: CoachIntensity.quiet,
          accent: CoachAccent.coach,
          ringCardIds: const [],
          situationKey: key,
        );
      case CoachingInsightCategory.baitDiscard:
        return CoachHint(
          category: insight.category,
          title: strings.coachBaitTitle,
          body: strings.coachBaitBody(topDiscardIdentity),
          icon: Icons.visibility_off_outlined,
          zone: CoachZone.discard,
          intensity: CoachIntensity.quiet,
          accent: CoachAccent.coach,
          ringCardIds: insight.highlightCardIds,
          situationKey: key,
        );
      case CoachingInsightCategory.drawStock:
        // An unopened seat carries its opening progress here (folded in by the
        // advisor) so the draw hint shows the shortfall instead of dropping it.
        final drawBest = insight.openingBestValue;
        final drawShortfall = insight.openingShortfall;
        final drawBody = (drawBest != null && drawBest > 0 && drawShortfall != null)
            ? strings.coachDrawBodyWithProgress(
                best: drawBest,
                shortfall: drawShortfall,
              )
            : strings.coachDrawBody;
        return CoachHint(
          category: insight.category,
          title: strings.coachDrawTitle,
          body: drawBody,
          icon: Icons.layers_outlined,
          zone: CoachZone.discard,
          intensity: CoachIntensity.quiet,
          accent: CoachAccent.coach,
          // Ring the in-hand cards that make up the best meld-in-progress (the
          // stock is highlighted separately via the drawStock category) so an
          // unopened seat still sees which cards feed its opening value.
          ringCardIds: insight.highlightCardIds,
          ringGroups: insight.meldGroups,
          situationKey: key,
        );
    }
  }

  // The hold-back warning line riding on a discard-carrying hint, or null
  // when the insight carries none.
  static String? _avoidSuffix(
    CoachingInsight insight,
    AppStrings strings,
    CoachIdentityLookup identityForCardId,
  ) {
    final avoidId = insight.avoidCardId;
    final opponent = insight.avoidOpponent;
    if (avoidId == null || opponent == null) {
      return null;
    }
    final identity = identityForCardId(avoidId);
    return switch (insight.avoidReason) {
      CoachAvoidReason.runEnd => strings.coachAvoidRunEndSuffix(
        card: identity,
        opponent: opponent,
      ),
      CoachAvoidReason.collecting || null => strings.coachAvoidCollectingSuffix(
        card: identity,
        opponent: opponent,
        rank: insight.avoidRank,
        suit: insight.avoidSuit,
      ),
    };
  }

  static String _situationKey(CoachingInsight insight) {
    final ids = [...insight.highlightCardIds]..sort();
    // Subject/avoid params re-animate the callout when the message materially
    // changes even though the ringed cards did not (e.g. the hold-back card
    // changes, or a banner's number moves).
    final extras = [
      if (insight.avoidCardId != null) 'a:${insight.avoidCardId}',
      if (insight.subjectSeat != null) 's:${insight.subjectSeat!.name}',
      if (insight.subjectValue != null) 'v:${insight.subjectValue}',
    ].join(',');
    return '${insight.category.name}:${ids.join(',')}:$extras';
  }
}
