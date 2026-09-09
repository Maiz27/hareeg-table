import '../../../domain/classic_hareeg/models/player_seat.dart';

/// How much weight one review insight carries.
enum ReviewSeverity {
  /// Routine colour: what happened, without a judgement.
  narration,

  /// Worth stopping on.
  notable,

  /// The observable evidence marks this as a clear error.
  mistake,
}

/// What one review insight is about.
///
/// Each value declares its own [severity], so the verbosity filter reads one
/// table instead of a switch that can drift out of step with the categories.
enum ReviewInsightCategory {
  /// South kept a developing group whose every completion is already dead.
  deadDevelopmentKept(ReviewSeverity.mistake),

  /// South took a card into a group that can no longer complete.
  deadPickup(ReviewSeverity.mistake),

  /// South's discard carries public evidence of helping the next seat.
  feedRiskDiscard(ReviewSeverity.notable),

  /// South's discard carries no such evidence.
  safeDiscard(ReviewSeverity.narration),

  /// South discarded while holding a card that was legally playable onto a
  /// meld already on the table.
  missedCover(ReviewSeverity.notable),

  /// An opponent's pickup fits what they have publicly been collecting.
  opponentCollectingTell(ReviewSeverity.notable),

  /// An opponent opened on this action.
  opponentOpened(ReviewSeverity.narration),

  /// A Fifty window was open when this action was taken.
  fiftyWindowOpen(ReviewSeverity.narration);

  const ReviewInsightCategory(this.severity);

  /// Weight this category carries.
  final ReviewSeverity severity;

  /// Whether this category is a dead-card warning, which the player can
  /// silence independently of verbosity.
  bool get isCardDeathWarning =>
      this == deadDevelopmentKept || this == deadPickup;
}

/// The kind of observable fact backing an insight.
///
/// Every value names something anyone at the table could see. There is
/// deliberately no kind for another seat's hand or for the stock's contents:
/// an insight that wanted to cite one would have nothing to cite it with.
enum ReviewEvidenceKind {
  /// Every copy of an identity is already accounted for.
  deadIdentity,

  /// A card publicly taken from the discard pile.
  discardPilePickup,

  /// A meld face up on the table.
  visibleMeld,

  /// How many cards a seat is holding.
  handCount,

  /// Whether a seat had opened.
  openingState,

  /// The state of a Fifty window.
  fiftyWindow,

  /// A match score.
  score,

  /// The reviewing seat's own hand.
  ownHand,

  /// A seat has shown nothing publicly that the card in question serves.
  ///
  /// This is a claim about *absence*, and it needs its own kind: a seat's hand
  /// count is a true observable fact but says nothing about whether a card
  /// helps them, and using it as support would be evidence in name only.
  noPublicTell,
}

/// One observable fact an insight rests on.
class ReviewEvidence {
  /// Creates evidence.
  ReviewEvidence({
    required this.kind,
    this.seat,
    List<String> cardIds = const [],
    this.rankLabel,
    this.suitLabel,
    this.value,
  }) : cardIds = List.unmodifiable(cardIds);

  /// What kind of fact this is.
  final ReviewEvidenceKind kind;

  /// Seat the fact is about, when it is about one.
  final PlayerSeat? seat;

  /// Cards the fact names.
  final List<String> cardIds;

  /// Rank name for an identity-shaped fact, for localized rendering.
  final String? rankLabel;

  /// Suit name for an identity-shaped fact, for localized rendering.
  final String? suitLabel;

  /// A count or score the fact carries.
  final int? value;
}

/// One structured, localization-free conclusion about an applied action.
///
/// Like [CoachingInsight] in live play, this never carries a sentence: the UI
/// stage composes English or Arabic from the category and the evidence.
class ReviewInsight {
  /// Creates an insight.
  ///
  /// Rejects an insight with no evidence. "No observable evidence means no
  /// claim" is the rule the whole review rests on, so the type refuses to
  /// represent a violation rather than relying on every construction site to
  /// remember it.
  ReviewInsight({
    required this.category,
    required List<ReviewEvidence> evidence,
    this.subjectSeat,
    List<String> cardIds = const [],
  }) : evidence = List.unmodifiable(evidence),
       cardIds = List.unmodifiable(cardIds) {
    if (evidence.isEmpty) {
      throw ArgumentError.value(
        evidence,
        'evidence',
        'A review insight must cite at least one observable fact.',
      );
    }
  }

  /// What this insight is about.
  final ReviewInsightCategory category;

  /// Weight, taken from the category so the two cannot disagree.
  ReviewSeverity get severity => category.severity;

  /// Seat the insight concerns.
  final PlayerSeat? subjectSeat;

  /// Cards the insight highlights.
  final List<String> cardIds;

  /// Observable facts this rests on. Never empty.
  final List<ReviewEvidence> evidence;

  /// Every card this insight refers to, top level and nested.
  ///
  /// Provenance is checked over this, not just [cardIds], so evidence cannot
  /// smuggle in a reference the top-level list would not have allowed.
  Set<String> get allReferencedCardIds => {
    ...cardIds,
    for (final item in evidence) ...item.cardIds,
  };
}
