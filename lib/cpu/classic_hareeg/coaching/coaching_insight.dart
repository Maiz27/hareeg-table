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
///
/// The ladder has three bands:
/// - WIN/WINDOW moments (1000–860): finishes and Fifty decisions.
/// - PLAYS (800–550): the concrete move the Expert brain would make now.
/// - STAGE banners (380–360): once-per-round posture teaching, surfaced through
///   [CoachInsightFlow] so each shows for a single turn per round and never
///   shadows the per-turn floors permanently.
/// - FLOORS (350–200): the guidance that keeps every turn non-silent.
enum CoachingInsightCategory {
  /// The seat can empty its hand and finish the round this turn.
  finishAvailable(1000),

  /// The seat owns a valid Fifty/Khamsin claim on the current top discard.
  fiftyAvailable(900),

  /// No Fifty window is open for the seat, but taking the top discard still
  /// finishes the hand for the normal −1 — the claim-vs-take distinction that
  /// confused real players. Outranks the plain pickup hint.
  takeAndFinish(880),

  /// The seat CAN finish, but the Expert brain would hold the finish to chase
  /// a Fifty (deep stock, heavy hand, someone at high-risk score). Replaces
  /// [finishAvailable] in that posture so the coach explains the hold instead
  /// of silently contradicting it with a discard suggestion.
  fiftyHold(860),

  /// An unopened seat whose best partition already meets the opening
  /// requirement — it can open this turn.
  openNow(800),

  /// A table joker the seat can replace with the real card it holds. Above
  /// [playMeld] because the swap is a FREE action that must come first: the
  /// meld may consume the very card the swap needs (playtest: three natural
  /// 8s got melded, burning the 8♣ that could have reclaimed the joker),
  /// while swapping first keeps the same meld playable via the freed joker.
  jokerAdvice(750),

  /// An opened seat that has a legal meld it can play from hand right now.
  playMeld(700),

  /// Taking the top discard would complete or improve a meld.
  pickupCompletesMeld(600),

  /// The seat should lay a hand card off as a cover onto a meld on the table
  /// (its own or an opponent's) this turn — the Expert brain's chosen play.
  playCover(550),

  /// Stage banner: the score situation changes correct play — the seat itself
  /// is near elimination (finish fast, stay light), or an opponent is one bad
  /// round from elimination (finishing now hurts them most).
  scorePosture(380),

  /// Stage banner: the stock is thin — stop building, shed into the table;
  /// an exhausted stock with no finish is a drawn round.
  endgameStockLow(375),

  /// Stage banner: an opened opponent is down to a few cards — every card
  /// still in the seat's hand is a point if they finish.
  opponentCloseToFinish(370),

  /// Stage banner: a benchmark owner has raised the opening requirement past
  /// the seat's best openable value.
  benchmarkAlert(365),

  /// Stage banner: the top discard fits the seat's hand but cannot reach the
  /// opening requirement — taking it only reveals the seat's plan (the
  /// bait-discard lesson, live).
  baitDiscard(360),

  /// The seat owes a discard to end the turn and has no productive play left:
  /// the coach recommends a specific, safe card to throw. The action-phase
  /// counterpart to [drawStock] — it keeps the hand-by-hand guidance moving.
  /// May carry a hold-back warning ([CoachingInsight.avoidCardId]) when the
  /// obvious throw is materially dangerous and the recommendation dodges it.
  discardSuggestion(350),

  /// Nothing better is available this turn: drawing from the stock is the
  /// sensible default. Sits above [openingProgress] so that in the draw phase an
  /// unopened seat is told to "draw a card" (the actionable instruction) rather
  /// than only shown its opening shortfall; the progress numbers are folded into
  /// the draw hint so they are not lost.
  drawStock(250),

  /// An unopened seat whose best partition falls short of the requirement.
  /// Surfaces in the action phase, where a draw is no longer owed. May carry a
  /// hold-back warning like [discardSuggestion].
  openingProgress(200);

  const CoachingInsightCategory(this.priority);

  /// Authoritative surfacing rank — higher is shown first. Declared on the
  /// category so the ordering lives in one readable table instead of scattered
  /// band constants at each call site.
  final int priority;

  /// Whether this category is a once-per-round STAGE banner (deduplicated by
  /// the UI's insight flow) rather than per-turn guidance.
  bool get isStageBanner => switch (this) {
    scorePosture ||
    endgameStockLow ||
    opponentCloseToFinish ||
    benchmarkAlert ||
    baitDiscard => true,
    _ => false,
  };
}

/// Why the Expert brain is HOLDING a legal cover in hand this turn — narrated
/// on the discard hint so a freshly drawn (or visible) lay-off is acknowledged
/// the moment it exists, even when playing it would be the wrong move.
/// Mirrors the brain's `CoverHoldReason` (the insight model stays decoupled
/// from the planner, like [CoachAvoidReason] mirrors the threat kinds).
enum CoachCoverHoldReason {
  /// The cover card is a joker — never burn it on a non-finishing cover.
  jokerGuard,

  /// Few cards + deep stock + a developing hand: covering sheds the Fifty.
  fiftyDevelopment,

  /// The card extends the seat's own run at an end; no rush to lay it off.
  ownRunExtension,
}

/// Why a hold-back ([CoachingInsight.avoidCardId]) warning fired.
enum CoachAvoidReason {
  /// The card slots directly onto an opponent's visible run on the table.
  runEnd,

  /// An opponent has been deliberately picking up matching cards from the
  /// discard pile (rank match, or same suit at adjacent rank).
  collecting,
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
    this.coverCardId,
    this.coverMeldOwner,
    this.coverMeldIndex,
    this.holdCoverReason,
    this.meldActionId,
    this.jokerCardId,
    this.jokerReplacementActionId,
    this.discardCardId,
    this.avoidCardId,
    this.avoidOpponent,
    this.avoidReason,
    this.avoidRank,
    this.avoidSuit,
    this.subjectSeat,
    this.subjectIsSelf = false,
    this.subjectValue,
    this.subjectThreshold,
    this.coverFinishes = false,
    this.bypassesOpening = false,
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

  /// For opening insights and [CoachingInsightCategory.benchmarkAlert]: the
  /// current opening requirement.
  final int? openingRequirement;

  /// For [CoachingInsightCategory.playCover] (and the play-meld combine): the
  /// hand card id that covers.
  final String? coverCardId;

  /// For cover-carrying insights: owner of the extended meld.
  final PlayerSeat? coverMeldOwner;

  /// For cover-carrying insights: index of the extended meld.
  final int? coverMeldIndex;

  /// For [CoachingInsightCategory.discardSuggestion]: the Expert brain is
  /// deliberately HOLDING the legal cover named by [coverCardId] (extending
  /// [coverMeldOwner]/[coverMeldIndex]) and this is why. The presenter folds
  /// a "you could lay that off, but hold it because…" line into the discard
  /// hint so a drawn cover is acknowledged the moment it appears. Null when
  /// no held cover applies — the common case.
  final CoachCoverHoldReason? holdCoverReason;

  /// For [CoachingInsightCategory.openNow], [CoachingInsightCategory.playMeld]:
  /// the play-meld action id to invoke.
  final String? meldActionId;

  /// For [CoachingInsightCategory.jokerAdvice]: the hand joker card id.
  final String? jokerCardId;

  /// For [CoachingInsightCategory.jokerAdvice]: a replace-joker action id, when
  /// the seat can swap a real card in for a represented table joker.
  final String? jokerReplacementActionId;

  /// For discard-carrying insights: the recommended card id to throw.
  final String? discardCardId;

  /// Hold-back warning: a hand card the player would plausibly throw (lowest
  /// keep-score) that is materially dangerous, while [discardCardId] is a safe
  /// alternative. Null when no warning applies — the common case.
  final String? avoidCardId;

  /// Hold-back warning: the threatened-by opponent.
  final PlayerSeat? avoidOpponent;

  /// Hold-back warning: why the card is dangerous.
  final CoachAvoidReason? avoidReason;

  /// Hold-back warning ([CoachAvoidReason.collecting]): the collected rank.
  final CardRank? avoidRank;

  /// Hold-back warning ([CoachAvoidReason.collecting]): the collected suit.
  final CardSuit? avoidSuit;

  /// Stage banners and [CoachingInsightCategory.fiftyHold]: the seat the
  /// message is about (the near-elimination opponent, the nearly-finished
  /// opponent, the benchmark owner, the Fifty-hold target).
  final PlayerSeat? subjectSeat;

  /// Whether [subjectSeat] is the coached seat itself (the presenter cannot
  /// infer this — it has no seat context).
  final bool subjectIsSelf;

  /// Stage banners: the number the message is about — a score
  /// ([CoachingInsightCategory.scorePosture], [CoachingInsightCategory.fiftyHold]),
  /// the stock size ([CoachingInsightCategory.endgameStockLow]), or an opponent
  /// hand count ([CoachingInsightCategory.opponentCloseToFinish]).
  final int? subjectValue;

  /// For [CoachingInsightCategory.scorePosture] (self variant): the score at
  /// which a seat is eliminated, for "31 eliminates you" copy.
  final int? subjectThreshold;

  /// For [CoachingInsightCategory.finishAvailable] surfaced as a finish-by-cover:
  /// covering every [highlightCardIds] card (grouped by [meldGroups]) empties the
  /// hand and wins. Lets the presenter pick "cover these to win" copy instead of
  /// the generic finish body.
  final bool coverFinishes;

  /// For [CoachingInsightCategory.finishAvailable]: the seat has not opened, so
  /// this full-hand finish doubles as its opening — either the perfect-hand
  /// bypass (melds-only, exempt from the requirement) or fresh melds that clear
  /// it. Lets the presenter add the "this also opens you" teaching.
  final bool bypassesOpening;

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
