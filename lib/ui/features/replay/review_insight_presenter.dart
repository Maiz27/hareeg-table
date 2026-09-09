import '../../../cpu/classic_hareeg/coaching/review_insight.dart';
import '../../../domain/classic_hareeg/game/classic_hareeg_action.dart';
import '../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../domain/classic_hareeg/replay/match_replay_timeline.dart';
import '../../../domain/classic_hareeg/replay/review_observation.dart';
import '../../../l10n/app_strings.dart';
import 'replay_viewer_view_state.dart';

/// Turns structured review data into the sentences a player reads.
///
/// The coach and the timeline never produce text; this is the only place a
/// card, an action or a conclusion becomes words. Card ids never reach the
/// screen — every reference is resolved to a localized rank-and-suit name, or
/// dropped if it cannot be resolved, because "deck-0-ace-hearts" is a storage
/// detail and reads as a bug to a player.
class ReviewInsightPresenter {
  /// Creates a presenter over [strings], resolving card ids through [cards].
  ReviewInsightPresenter({
    required this.strings,
    required Map<String, HareegCard> cards,
    HareegCard? takenCard,
  }) : _cards = cards,
       _takenCard = takenCard;

  /// Builds a presenter that can name every card visible at [frame].
  ///
  /// The lookup is drawn from the position itself, so a card the player could
  /// not see is also a card the presenter cannot name.
  factory ReviewInsightPresenter.forFrame({
    required AppStrings strings,
    required ReplayFrame frame,
    ReplayFrame? previous,
  }) {
    final snapshot = frame.snapshot;
    final cards = <String, HareegCard>{};
    void add(Iterable<HareegCard> source) {
      for (final card in source) {
        cards[card.id] = card;
      }
    }

    add(snapshot.hands[reviewPerspectiveSeat] ?? const []);
    add(snapshot.discardPile);
    for (final melds in snapshot.tableMelds.values) {
      for (final meld in melds) {
        add(meld.cards);
      }
    }
    final pending = snapshot.pendingDiscard;
    if (pending != null) {
      cards[pending.id] = pending;
    }
    for (final event in snapshot.discardHistoryEvents) {
      cards[event.card.id] = event.card;
    }

    // A card taken from the pile is no longer in it, so the position AFTER the
    // action cannot name it. The pre-action pile can, and it was face up for
    // everyone to see.
    final before = previous?.snapshot;
    if (before != null) {
      add(before.discardPile);
      final pending = before.pendingDiscard;
      if (pending != null) {
        cards[pending.id] = pending;
      }
    }

    return ReviewInsightPresenter(
      strings: strings,
      cards: cards,
      takenCard: _takenCardOf(frame, previous),
    );
  }

  /// Localized copy.
  final AppStrings strings;

  final Map<String, HareegCard> _cards;

  /// The card this frame's action took from the pile, when it took one.
  ///
  /// `take-discard` carries no card id — the action is "take whatever is on
  /// top" — so the card has to come from the position it was taken from.
  final HareegCard? _takenCard;

  /// Resolves the card a pickup action actually took, from the visible
  /// pre-action position.
  static HareegCard? _takenCardOf(ReplayFrame frame, ReplayFrame? previous) {
    final entry = frame.appliedEntry;
    final before = previous?.snapshot;
    if (entry == null || before == null) {
      return null;
    }
    return switch (ClassicHareegActionIds.describe(entry.actionId).kind) {
      ClassicHareegActionKind.takeDiscard =>
        before.discardPile.isEmpty ? null : before.discardPile.last,
      ClassicHareegActionKind.usePendingDiscard => before.pendingDiscard,
      _ => null,
    };
  }

  /// Localized name for a card id, or null when it cannot be resolved.
  String? cardName(String id) {
    final card = _cards[id];
    if (card == null) {
      return null;
    }
    final identity = card.identity;
    return identity == null ? strings.joker : strings.cardName(identity);
  }

  /// Names the card a pickup took: the action's own id when it has one, then
  /// the card resolved from the pre-action pile, and only then an honest
  /// "a card".
  String _takenCardName(String? explicitId) {
    if (explicitId != null) {
      final named = cardName(explicitId);
      if (named != null) {
        return named;
      }
    }
    final taken = _takenCard;
    if (taken != null) {
      final identity = taken.identity;
      return identity == null ? strings.joker : strings.cardName(identity);
    }
    return strings.replayUnnamedCard;
  }

  String _cardNameOr(String? id, String fallback) {
    if (id == null) {
      return fallback;
    }
    return cardName(id) ?? fallback;
  }

  String _joined(Iterable<String> ids) {
    final names = [for (final id in ids) ?cardName(id)];
    return names.join(strings.isRtl ? '، ' : ', ');
  }

  /// One line describing what a frame is.
  String describeFrame(ReplayFrame frame) {
    return switch (frame.kind) {
      ReplayFrameKind.initial => strings.replayDeal,
      ReplayFrameKind.roundStart => strings.replayRoundStart(frame.roundNumber),
      ReplayFrameKind.actionApplied => describeAction(
        frame.appliedEntry!.seat,
        ClassicHareegActionIds.describe(frame.appliedEntry!.actionId),
      ),
    };
  }

  /// One line describing an applied action.
  ///
  /// Every action kind is covered, including the unparseable one: a move the
  /// app cannot classify still happened, and saying so plainly beats printing
  /// an identifier.
  String describeAction(
    PlayerSeat seat,
    ClassicHareegActionDescriptor descriptor,
  ) {
    final card = descriptor.cardId;
    final phrase = switch (descriptor.kind) {
      ClassicHareegActionKind.drawStock => strings.replayActionDraw(),
      ClassicHareegActionKind.takeDiscard => strings.replayActionTakeDiscard(
        _takenCardName(card),
      ),
      ClassicHareegActionKind.usePendingDiscard =>
        strings.replayActionUsePending(_takenCardName(card)),
      ClassicHareegActionKind.returnPendingDiscard =>
        strings.replayActionReturnPending(),
      ClassicHareegActionKind.returnOpeningMelds =>
        strings.replayActionReturnMelds(),
      ClassicHareegActionKind.returnTablePlay =>
        strings.replayActionReturnTablePlay(),
      ClassicHareegActionKind.claimFifty => strings.replayActionClaimFifty(),
      ClassicHareegActionKind.playMeld => strings.replayActionPlayMeld(),
      ClassicHareegActionKind.playMeldWithJoker =>
        strings.replayActionPlayMeldJoker(),
      ClassicHareegActionKind.placeCover => strings.replayActionCover(
        _cardNameOr(
          descriptor.cardIds.isEmpty ? null : descriptor.cardIds.first,
          strings.replayUnnamedCard,
        ),
      ),
      ClassicHareegActionKind.replaceJoker => strings.replayActionReplaceJoker(
        _cardNameOr(card, strings.replayUnnamedCard),
      ),
      ClassicHareegActionKind.discard => strings.replayActionDiscard(
        _cardNameOr(card, strings.replayUnnamedCard),
      ),
      ClassicHareegActionKind.discardBlockedCover =>
        strings.replayActionDiscardBlocked(
          _cardNameOr(card, strings.replayUnnamedCard),
        ),
      ClassicHareegActionKind.discardJoker => strings.replayActionDiscardJoker(
        _cardNameOr(card, strings.replayUnnamedCard),
      ),
      ClassicHareegActionKind.unknown => strings.replayActionUnknown,
    };
    return strings.replayActionLine(seat, phrase);
  }

  /// The headline sentence for one insight.
  String sentenceFor(ReviewInsight insight) {
    final seat = insight.subjectSeat ?? reviewPerspectiveSeat;
    return switch (insight.category) {
      ReviewInsightCategory.deadDevelopmentKept =>
        strings.replayInsightDeadDevelopment(_joined(insight.cardIds)),
      ReviewInsightCategory.deadPickup => strings.replayInsightDeadPickup(
        _joined(insight.cardIds),
      ),
      ReviewInsightCategory.feedRiskDiscard => strings.replayInsightFeedRisk(
        _joined(insight.cardIds),
        seat,
      ),
      ReviewInsightCategory.safeDiscard => strings.replayInsightSafeDiscard(
        _joined(insight.cardIds),
        seat,
      ),
      ReviewInsightCategory.missedCover => strings.replayInsightMissedCover(
        _joined(insight.cardIds),
      ),
      ReviewInsightCategory.opponentCollectingTell =>
        strings.replayInsightCollectingTell(seat, _joined(insight.cardIds)),
      ReviewInsightCategory.opponentOpened =>
        strings.replayInsightOpponentOpened(seat),
      ReviewInsightCategory.fiftyWindowOpen => strings.replayInsightFiftyWindow(
        _joined(insight.cardIds),
        _firstValue(insight),
      ),
    };
  }

  /// The supporting evidence lines for one insight.
  List<String> evidenceLines(ReviewInsight insight) {
    return [for (final item in insight.evidence) _evidenceLine(insight, item)];
  }

  String _evidenceLine(ReviewInsight insight, ReviewEvidence evidence) {
    final seat = evidence.seat ?? insight.subjectSeat ?? reviewPerspectiveSeat;
    return switch (evidence.kind) {
      ReviewEvidenceKind.deadIdentity => strings.replayEvidenceDeadIdentity(
        _identityName(evidence),
        evidence.value ?? 0,
      ),
      ReviewEvidenceKind.discardPilePickup => strings.replayEvidencePickup(
        seat,
        _joined(evidence.cardIds),
      ),
      ReviewEvidenceKind.visibleMeld => strings.replayEvidenceVisibleMeld(
        _joined(evidence.cardIds),
      ),
      ReviewEvidenceKind.handCount => strings.replayEvidenceHandCount(
        seat,
        evidence.value ?? 0,
      ),
      ReviewEvidenceKind.openingState => strings.replayEvidenceOpeningState(
        seat,
        evidence.value ?? 0,
      ),
      ReviewEvidenceKind.fiftyWindow => strings.replayEvidenceFiftyWindow(
        _joined(evidence.cardIds),
        evidence.value ?? 0,
      ),
      ReviewEvidenceKind.score => strings.replayEvidenceScore(
        seat,
        evidence.value ?? 0,
      ),
      ReviewEvidenceKind.ownHand => strings.replayEvidenceOwnHand(
        _joined(evidence.cardIds),
      ),
      ReviewEvidenceKind.noPublicTell => strings.replayEvidenceNoPublicTell(
        seat,
        evidence.value ?? 0,
      ),
    };
  }

  /// A dead identity names a rank and suit rather than a physical card,
  /// because the point is that *every* copy is gone, not that one is.
  String _identityName(ReviewEvidence evidence) {
    final rank = CardRank.fromName(evidence.rankLabel);
    final suit = CardSuit.fromName(evidence.suitLabel);
    if (rank == null || suit == null) {
      // A dead identity is always a standard card, so this only happens on
      // malformed data. Saying "Joker" would name a specific card that is not
      // the one meant.
      return strings.replayUnnamedCard;
    }
    return strings.cardName(CardIdentity(rank: rank, suit: suit));
  }

  int _firstValue(ReviewInsight insight) {
    for (final item in insight.evidence) {
      if (item.value != null) {
        return item.value!;
      }
    }
    return 0;
  }

  /// Localized copy for why a replay cannot be shown.
  String unavailableReason(ReplayUnavailableReason reason) {
    return switch (reason) {
      ReplayUnavailableReason.replayDataUnusable =>
        strings.replayReasonDataUnusable,
      ReplayUnavailableReason.reconstructionFailed =>
        strings.replayReasonReconstructionFailed,
      ReplayUnavailableReason.metadataInvalid =>
        strings.replayReasonMetadataInvalid,
    };
  }
}
