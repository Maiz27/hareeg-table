import '../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../domain/classic_hareeg/models/playing_card.dart';

/// Category of one structured coaching insight.
///
/// Each value is a pure analytical classification — the UI stage maps it to a
/// localized (EN/AR) sentence. The engine never emits user-facing strings.
///
/// Values are ordered high-priority first for readability, but the numeric
/// priority a [CoachingInsight] carries is the authoritative sort key.
enum CoachingInsightCategory {
  /// The seat can empty its hand and finish the round this turn.
  finishAvailable,

  /// The seat owns a valid Fifty/Khamsin claim on the current top discard.
  fiftyAvailable,

  /// An unopened seat whose best partition already meets the opening
  /// requirement — it can open this turn.
  openNow,

  /// An opened seat that has a legal meld it can play from hand right now.
  playMeld,

  /// Taking the top discard would complete or improve a meld.
  pickupCompletesMeld,

  /// A hand card covers/extends one of the seat's own table melds. Framed as a
  /// positive KEEP/teaching insight, never as a prohibition.
  coverKeep,

  /// A joker the seat could replace on the table, or hold for a bigger meld.
  jokerAdvice,

  /// A legal discard whose rank/suit an opponent is visibly collecting.
  defensiveDiscard,

  /// An unopened seat whose best partition falls short of the requirement.
  openingProgress,
}

/// One structured, localization-free coaching insight.
///
/// A [CoachingInsight] never carries a sentence. It carries a [category], a
/// numeric [priority] (higher = surfaced first), and the structured params each
/// category needs so the UI stage can compose the message itself.
class CoachingInsight {
  /// Creates a coaching insight.
  const CoachingInsight({
    required this.category,
    required this.priority,
    this.openingShortfall,
    this.openingBestValue,
    this.openingRequirement,
    this.hotSuit,
    this.hotRank,
    this.hotOpponent,
    this.coverCardId,
    this.coverMeldOwner,
    this.coverMeldIndex,
    this.meldActionId,
    this.jokerCardId,
    this.jokerReplacementActionId,
    this.discardCardId,
    this.highlightCardIds = const [],
  });

  /// Structured classification of this insight.
  final CoachingInsightCategory category;

  /// Sort key; higher values surface first. Callers may show only the top one.
  final int priority;

  /// For [CoachingInsightCategory.openingProgress]: `requirement - bestValue`.
  final int? openingShortfall;

  /// For opening insights: the best openable partition value found.
  final int? openingBestValue;

  /// For opening insights: the current opening requirement.
  final int? openingRequirement;

  /// For [CoachingInsightCategory.defensiveDiscard]: the suit being collected.
  final CardSuit? hotSuit;

  /// For [CoachingInsightCategory.defensiveDiscard]: the rank being collected.
  final CardRank? hotRank;

  /// For [CoachingInsightCategory.defensiveDiscard]: the collecting opponent.
  final PlayerSeat? hotOpponent;

  /// For [CoachingInsightCategory.coverKeep]: the hand card id that covers.
  final String? coverCardId;

  /// For [CoachingInsightCategory.coverKeep]: owner of the extended meld.
  final PlayerSeat? coverMeldOwner;

  /// For [CoachingInsightCategory.coverKeep]: index of the extended meld.
  final int? coverMeldIndex;

  /// For [CoachingInsightCategory.openNow], [CoachingInsightCategory.playMeld]:
  /// the play-meld action id to invoke.
  final String? meldActionId;

  /// For [CoachingInsightCategory.jokerAdvice]: the hand joker card id.
  final String? jokerCardId;

  /// For [CoachingInsightCategory.jokerAdvice]: a replace-joker action id, when
  /// the seat can swap a real card in for a represented table joker.
  final String? jokerReplacementActionId;

  /// For [CoachingInsightCategory.defensiveDiscard]: the risky hand card id.
  final String? discardCardId;

  /// Card ids the UI should visually highlight for this insight.
  final List<String> highlightCardIds;
}
