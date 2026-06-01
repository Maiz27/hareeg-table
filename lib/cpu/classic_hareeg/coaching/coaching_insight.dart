import '../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../domain/classic_hareeg/models/playing_card.dart';

/// Category of one structured coaching insight.
///
/// Each value is a pure analytical classification — the UI stage maps it to a
/// localized (EN/AR) sentence. The engine never emits user-facing strings.
///
/// Each value declares its own [priority] — the authoritative surfacing rank
/// ([ClassicHareegCoachingAdvisor] sorts insights by it, highest first). The
/// values are declared in descending priority order so this list reads as the
/// single, readable priority ladder; no band integer is restated anywhere else.
/// The relative order is load-bearing (many playtest fixes were "category X must
/// outrank category Y"), so a test asserts this ladder stays strictly
/// descending.
enum CoachingInsightCategory {
  /// The seat can empty its hand and finish the round this turn.
  finishAvailable(1000),

  /// The seat owns a valid Fifty/Khamsin claim on the current top discard.
  fiftyAvailable(900),

  /// An unopened seat whose best partition already meets the opening
  /// requirement — it can open this turn.
  openNow(800),

  /// An opened seat that has a legal meld it can play from hand right now.
  playMeld(700),

  /// Taking the top discard would complete or improve a meld.
  pickupCompletesMeld(600),

  /// The seat should lay a hand card off as a cover onto a meld on the table
  /// (its own or an opponent's) this turn — the Expert brain's chosen play.
  /// Distinct from [coverKeep], which only says a card is worth holding.
  playCover(550),

  /// A hand card covers/extends one of the seat's own table melds, framed as a
  /// positive KEEP/teaching insight. No longer emitted by the advisor: cover
  /// advice is now driven by the Expert plan's chosen move ([playCover] /
  /// finish-by-cover), so the coach never re-derives a bespoke "keep" cover that
  /// could diverge from the brain. The value (and its presenter copy) is retained
  /// for the priority ladder and any future plan-sourced keep framing.
  coverKeep(500),

  /// A joker the seat could replace on the table, or hold for a bigger meld.
  jokerAdvice(400),

  /// The seat owes a discard to end the turn and has no productive play left:
  /// the coach recommends a specific, safe card to throw. The action-phase
  /// counterpart to [drawStock] — it keeps the hand-by-hand guidance moving.
  discardSuggestion(350),

  /// A legal discard whose rank/suit an opponent is visibly collecting.
  defensiveDiscard(300),

  /// Nothing better is available this turn: drawing from the stock is the
  /// sensible default. Sits above [openingProgress] so that in the draw phase an
  /// unopened seat is told to "draw a card" (the actionable instruction) rather
  /// than only shown its opening shortfall; the progress numbers are folded into
  /// the draw hint so they are not lost.
  drawStock(250),

  /// An unopened seat whose best partition falls short of the requirement.
  /// Surfaces in the action phase, where a draw is no longer owed.
  openingProgress(200);

  const CoachingInsightCategory(this.priority);

  /// Authoritative surfacing rank — higher is shown first. Declared on the
  /// category so the ordering lives in one readable table instead of scattered
  /// band constants at each call site.
  final int priority;
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
    this.coverFinishes = false,
    this.coverIsChoice = false,
    this.highlightCardIds = const [],
    this.meldGroups = const [],
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

  /// For [CoachingInsightCategory.finishAvailable] surfaced as a finish-by-cover:
  /// covering every [highlightCardIds] card (grouped by [meldGroups]) empties the
  /// hand and wins. Lets the presenter pick "cover these to win" copy instead of
  /// the generic finish body.
  final bool coverFinishes;

  /// For [CoachingInsightCategory.playCover]: more than one independent cover is
  /// available, so the player may lay one off and still play or discard the
  /// other. Lets the presenter pick the "either works" copy.
  final bool coverIsChoice;

  /// Card ids the UI should visually highlight for this insight.
  final List<String> highlightCardIds;

  /// Card ids partitioned into the distinct melds they form, in the same order
  /// as the recommended play. The UI rings each group in its own coach hue so
  /// the player can tell which cards belong to which meld (a flat single-colour
  /// highlight cannot convey the grouping). A subset of [highlightCardIds];
  /// empty when the insight has no meld structure to convey.
  final List<List<String>> meldGroups;
}
