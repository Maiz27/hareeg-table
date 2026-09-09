import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/coaching/analysis_coach_settings.dart';
import 'package:hareeg_table/cpu/classic_hareeg/coaching/replay_analysis_coach.dart';
import 'package:hareeg_table/cpu/classic_hareeg/coaching/review_insight.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_discard_history.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart'
    show TurnPhase;
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/replay/match_replay_timeline.dart';
import 'package:hareeg_table/domain/classic_hareeg/replay/review_observation.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_action_transcript.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

import '../../../scenario/classic_hareeg_scenario.dart';
import '../../../support/completed_match_fixture.dart';

HareegCard _c(CardRank rank, CardSuit suit, {int deck = 0}) =>
    ScenarioCards.card(rank, suit, deckIndex: deck);

const _narrateAll = AnalysisCoachSettings(
  verbosity: AnalysisVerbosity.narrateAll,
  cardDeathWarnings: true,
);

/// Builds the position, then reviews one action taken from it.
List<ReviewInsight> _review({
  required ClassicHareegMatchSnapshot snapshot,
  required String actionId,
  PlayerSeat actor = PlayerSeat.south,
  AnalysisCoachSettings settings = _narrateAll,
}) {
  final clock = replayClockEpoch;
  final previous = ReplayFrame(
    index: 0,
    kind: ReplayFrameKind.initial,
    roundNumber: snapshot.roundNumber,
    snapshot: snapshot,
    clock: clock,
  );
  final applied = ReplayFrame(
    index: 1,
    kind: ReplayFrameKind.actionApplied,
    roundNumber: snapshot.roundNumber,
    snapshot: snapshot,
    clock: clock.add(const Duration(seconds: 1)),
    appliedEntry: MatchActionTranscriptEntry(
      order: 0,
      seat: actor,
      roundNumber: snapshot.roundNumber,
      phase: TurnPhase.action,
      actionId: actionId,
    ),
  );

  return ReplayAnalysisCoach.review(
    observation: ReviewObservation.fromFrames(
      previous: previous,
      applied: applied,
    ),
    action: ReviewedAction.fromEntry(applied.appliedEntry!),
    settings: settings,
  );
}

Set<ReviewInsightCategory> _categories(List<ReviewInsight> insights) =>
    insights.map((i) => i.category).toSet();

ClassicHareegMatchSnapshot _position({
  List<HareegCard>? southHand,
  List<HareegCard>? eastHand,
  List<HareegCard>? discardPile,
  Map<PlayerSeat, List<PlacedMeld>>? tableMelds,
  OpeningState? openingState,
  List<DiscardEvent>? discardHistoryEvents,
  PlayerSeat currentSeat = PlayerSeat.south,
  DateTime? fiftyWindowOpenedAt,
}) {
  return ClassicHareegScenario.deal(
    southHand: southHand,
    eastHand: eastHand,
    discardPile: discardPile,
    tableMelds: tableMelds,
    openingState: openingState,
    discardHistoryEvents: discardHistoryEvents,
    currentSeat: currentSeat,
    fiftyWindowOpenedAt: fiftyWindowOpenedAt,
  ).controller.toSnapshot(savedAt: replayClockEpoch);
}

/// Opens a Fifty window on a finished position.
///
/// Set on the snapshot rather than driven through the controller: the review
/// reads the stored window, and a window needs its provenance (who discarded)
/// as well as its clock before it counts as open.
ClassicHareegMatchSnapshot _withOpenFiftyWindow(
  ClassicHareegMatchSnapshot snapshot,
) {
  return ClassicHareegMatchSnapshot.fromJson({
    ...snapshot.toJson(),
    'fiftyWindowOpenedAt': replayClockEpoch.toIso8601String(),
    'fiftyWindowDiscarder': PlayerSeat.east.name,
  });
}

void main() {
  group('dead development', () {
    // South keeps a pair of tens whose only two completions are both already
    // face up, so the pair can never become a meld.
    final pairOfTens = [
      _c(CardRank.ten, CardSuit.spades),
      _c(CardRank.ten, CardSuit.diamonds),
      _c(CardRank.king, CardSuit.clubs),
    ];

    test('fires when every completion is already accounted for', () {
      final snapshot = _position(
        southHand: pairOfTens,
        discardPile: [
          _c(CardRank.ten, CardSuit.clubs),
          _c(CardRank.ten, CardSuit.hearts),
          _c(CardRank.ten, CardSuit.clubs, deck: 1),
          _c(CardRank.ten, CardSuit.hearts, deck: 1),
        ],
      );

      final insights = _review(
        snapshot: snapshot,
        actionId: 'discard:${_c(CardRank.king, CardSuit.clubs).id}',
      );
      expect(
        _categories(insights),
        contains(ReviewInsightCategory.deadDevelopmentKept),
      );
    });

    test('stays quiet while one completion is still live', () {
      // Identical board except one ten is still unaccounted for. The signal
      // must depend on the evidence, not on the shape of the hand.
      final snapshot = _position(
        southHand: pairOfTens,
        discardPile: [
          _c(CardRank.ten, CardSuit.clubs),
          _c(CardRank.ten, CardSuit.clubs, deck: 1),
          _c(CardRank.ten, CardSuit.hearts),
        ],
      );

      final insights = _review(
        snapshot: snapshot,
        actionId: 'discard:${_c(CardRank.king, CardSuit.clubs).id}',
      );
      expect(
        _categories(insights),
        isNot(contains(ReviewInsightCategory.deadDevelopmentKept)),
      );
    });

    test('is not raised about a group the player just broke up', () {
      final snapshot = _position(
        southHand: pairOfTens,
        discardPile: [
          _c(CardRank.ten, CardSuit.clubs),
          _c(CardRank.ten, CardSuit.hearts),
          _c(CardRank.ten, CardSuit.clubs, deck: 1),
          _c(CardRank.ten, CardSuit.hearts, deck: 1),
        ],
      );

      // Throwing one of the tens is the player acting on the problem, not
      // keeping it.
      final insights = _review(
        snapshot: snapshot,
        actionId: 'discard:${_c(CardRank.ten, CardSuit.spades).id}',
      );
      final dead = insights
          .where((i) => i.category == ReviewInsightCategory.deadDevelopmentKept)
          .toList();
      for (final insight in dead) {
        expect(
          insight.cardIds,
          isNot(contains(_c(CardRank.ten, CardSuit.spades).id)),
        );
      }
    });
  });

  group('the feed judgement is exactly one verdict', () {
    final hand = [
      _c(CardRank.seven, CardSuit.hearts),
      _c(CardRank.three, CardSuit.spades),
    ];

    test('a discard the next seat has been collecting is flagged', () {
      final snapshot = _position(
        southHand: hand,
        discardHistoryEvents: [
          DiscardEvent(
            seat: PlayerSeat.east,
            card: _c(CardRank.seven, CardSuit.clubs),
            kind: DiscardEventKind.pickup,
            sequence: 1,
          ),
        ],
      );

      final categories = _categories(
        _review(
          snapshot: snapshot,
          actionId: 'discard:${_c(CardRank.seven, CardSuit.hearts).id}',
        ),
      );
      expect(categories, contains(ReviewInsightCategory.feedRiskDiscard));
      expect(categories, isNot(contains(ReviewInsightCategory.safeDiscard)));
    });

    test('a discard with nothing against it is called safe', () {
      final snapshot = _position(southHand: hand);

      final categories = _categories(
        _review(
          snapshot: snapshot,
          actionId: 'discard:${_c(CardRank.three, CardSuit.spades).id}',
        ),
      );
      expect(categories, contains(ReviewInsightCategory.safeDiscard));
      expect(
        categories,
        isNot(contains(ReviewInsightCategory.feedRiskDiscard)),
      );
    });

    test('exactly one of the two appears, never both and never neither', () {
      for (final card in hand) {
        final insights = _review(
          snapshot: _position(
            southHand: hand,
            discardHistoryEvents: [
              DiscardEvent(
                seat: PlayerSeat.east,
                card: _c(CardRank.seven, CardSuit.clubs),
                kind: DiscardEventKind.pickup,
                sequence: 1,
              ),
            ],
          ),
          actionId: 'discard:${card.id}',
        );
        final verdicts = insights
            .where(
              (i) =>
                  i.category == ReviewInsightCategory.feedRiskDiscard ||
                  i.category == ReviewInsightCategory.safeDiscard,
            )
            .length;
        expect(verdicts, 1, reason: 'discarding ${card.id}');
      }
    });
  });

  group('an opponent opening', () {
    test('is announced on the meld that opens them', () {
      final snapshot = _position(currentSeat: PlayerSeat.east);

      final categories = _categories(
        _review(
          snapshot: snapshot,
          actionId: 'play-meld:a,b,c',
          actor: PlayerSeat.east,
        ),
      );
      expect(categories, contains(ReviewInsightCategory.opponentOpened));
    });

    test('is not repeated on their later melds', () {
      final snapshot = _position(
        currentSeat: PlayerSeat.east,
        openingState: ScenarioCards.openedFor(PlayerSeat.east),
      );

      final categories = _categories(
        _review(
          snapshot: snapshot,
          actionId: 'play-meld:a,b,c',
          actor: PlayerSeat.east,
        ),
      );
      expect(
        categories,
        isNot(contains(ReviewInsightCategory.opponentOpened)),
      );
    });
  });

  group('an open Fifty window', () {
    test('is narrated on the action taken while it stood', () {
      final snapshot = _withOpenFiftyWindow(
        _position(
          southHand: [_c(CardRank.three, CardSuit.spades)],
          discardPile: [_c(CardRank.nine, CardSuit.hearts)],
        ),
      );
      expect(snapshot.fiftyWindowOpenedAt, isNotNull);

      expect(
        _categories(_review(snapshot: snapshot, actionId: 'draw-stock')),
        contains(ReviewInsightCategory.fiftyWindowOpen),
      );
    });

    test('is not narrated back at the player who claimed it', () {
      final snapshot = _withOpenFiftyWindow(
        _position(
          southHand: [_c(CardRank.three, CardSuit.spades)],
          discardPile: [_c(CardRank.nine, CardSuit.hearts)],
        ),
      );

      expect(
        _categories(_review(snapshot: snapshot, actionId: 'claim-fifty')),
        isNot(contains(ReviewInsightCategory.fiftyWindowOpen)),
      );
    });

    test('is absent when no window was open', () {
      final snapshot = _position(
        southHand: [_c(CardRank.three, CardSuit.spades)],
      );

      expect(
        _categories(_review(snapshot: snapshot, actionId: 'draw-stock')),
        isNot(contains(ReviewInsightCategory.fiftyWindowOpen)),
      );
    });
  });

  group('who the insight is about', () {
    test('the player\'s own judgements are never raised about an opponent', () {
      const southOnly = {
        ReviewInsightCategory.deadDevelopmentKept,
        ReviewInsightCategory.deadPickup,
        ReviewInsightCategory.feedRiskDiscard,
        ReviewInsightCategory.safeDiscard,
        ReviewInsightCategory.missedCover,
      };

      final snapshot = _position(
        southHand: [_c(CardRank.seven, CardSuit.hearts)],
        currentSeat: PlayerSeat.east,
      );

      for (final actionId in [
        'discard:${_c(CardRank.seven, CardSuit.hearts).id}',
        'take-discard',
      ]) {
        final categories = _categories(
          _review(
            snapshot: snapshot,
            actionId: actionId,
            actor: PlayerSeat.east,
          ),
        );
        expect(categories.intersection(southOnly), isEmpty, reason: actionId);
      }
    });

    test('opponent tells are never raised about the player', () {
      const opponentOnly = {
        ReviewInsightCategory.opponentCollectingTell,
        ReviewInsightCategory.opponentOpened,
      };

      final snapshot = _position(
        southHand: [_c(CardRank.seven, CardSuit.hearts)],
        discardPile: [_c(CardRank.seven, CardSuit.clubs)],
      );

      for (final actionId in ['take-discard', 'play-meld:a,b,c']) {
        final categories = _categories(
          _review(snapshot: snapshot, actionId: actionId),
        );
        expect(
          categories.intersection(opponentOnly),
          isEmpty,
          reason: actionId,
        );
      }
    });
  });

  group('settings filter, they do not change the analysis', () {
    final snapshot = _position(
      southHand: [
        _c(CardRank.ten, CardSuit.spades),
        _c(CardRank.ten, CardSuit.diamonds),
        _c(CardRank.king, CardSuit.clubs),
      ],
      discardPile: [
        _c(CardRank.ten, CardSuit.clubs),
        _c(CardRank.ten, CardSuit.hearts),
        _c(CardRank.ten, CardSuit.clubs, deck: 1),
        _c(CardRank.ten, CardSuit.hearts, deck: 1),
      ],
    );
    final actionId = 'discard:${_c(CardRank.king, CardSuit.clubs).id}';

    ReviewObservation observationFor() {
      final previous = ReplayFrame(
        index: 0,
        kind: ReplayFrameKind.initial,
        roundNumber: snapshot.roundNumber,
        snapshot: snapshot,
        clock: replayClockEpoch,
      );
      final applied = ReplayFrame(
        index: 1,
        kind: ReplayFrameKind.actionApplied,
        roundNumber: snapshot.roundNumber,
        snapshot: snapshot,
        clock: replayClockEpoch.add(const Duration(seconds: 1)),
        appliedEntry: MatchActionTranscriptEntry(
          order: 0,
          seat: PlayerSeat.south,
          roundNumber: snapshot.roundNumber,
          phase: TurnPhase.action,
          actionId: actionId,
        ),
      );
      return ReviewObservation.fromFrames(previous: previous, applied: applied);
    }

    test('the same position is analysed identically whatever is shown', () {
      final observation = observationFor();
      final action = ReviewedAction(
        actingSeat: PlayerSeat.south,
        descriptor: ReviewedAction.fromEntry(
          MatchActionTranscriptEntry(
            order: 0,
            seat: PlayerSeat.south,
            roundNumber: 1,
            phase: TurnPhase.action,
            actionId: actionId,
          ),
        ).descriptor,
      );

      final unfiltered = ReplayAnalysisCoach.generate(
        observation: observation,
        action: action,
      );
      expect(unfiltered, isNotEmpty);

      // Generation is independent of the player's choices; only the filter
      // depends on them.
      for (final settings in const [
        AnalysisCoachSettings(
          verbosity: AnalysisVerbosity.narrateAll,
          cardDeathWarnings: true,
        ),
        AnalysisCoachSettings(
          verbosity: AnalysisVerbosity.clearMistakes,
          cardDeathWarnings: false,
        ),
        AnalysisCoachSettings(
          verbosity: AnalysisVerbosity.keyMoments,
          cardDeathWarnings: true,
        ),
      ]) {
        final again = ReplayAnalysisCoach.generate(
          observation: observation,
          action: action,
        );
        expect(
          again.map((i) => i.category).toList(),
          unfiltered.map((i) => i.category).toList(),
          reason: settings.verbosity.name,
        );
      }
    });

    test('each level really drops something', () {
      final all = _review(
        snapshot: snapshot,
        actionId: actionId,
        settings: const AnalysisCoachSettings(
          verbosity: AnalysisVerbosity.narrateAll,
          cardDeathWarnings: true,
        ),
      );
      final key = _review(
        snapshot: snapshot,
        actionId: actionId,
        settings: const AnalysisCoachSettings(
          verbosity: AnalysisVerbosity.keyMoments,
          cardDeathWarnings: true,
        ),
      );
      final mistakes = _review(
        snapshot: snapshot,
        actionId: actionId,
        settings: const AnalysisCoachSettings(
          verbosity: AnalysisVerbosity.clearMistakes,
          cardDeathWarnings: true,
        ),
      );

      expect(all.length, greaterThan(key.length));
      expect(key.length, greaterThanOrEqualTo(mistakes.length));
      expect(
        key.every((i) => i.severity != ReviewSeverity.narration),
        isTrue,
      );
      expect(
        mistakes.every((i) => i.severity == ReviewSeverity.mistake),
        isTrue,
      );
    });

    test('dead-card warnings can be silenced without silencing anything else', () {
      final loud = _review(
        snapshot: snapshot,
        actionId: actionId,
        settings: const AnalysisCoachSettings(
          verbosity: AnalysisVerbosity.narrateAll,
          cardDeathWarnings: true,
        ),
      );
      final quiet = _review(
        snapshot: snapshot,
        actionId: actionId,
        settings: const AnalysisCoachSettings(
          verbosity: AnalysisVerbosity.narrateAll,
          cardDeathWarnings: false,
        ),
      );

      expect(
        _categories(loud),
        contains(ReviewInsightCategory.deadDevelopmentKept),
      );
      expect(
        _categories(quiet),
        isNot(contains(ReviewInsightCategory.deadDevelopmentKept)),
      );
      // Everything that was not a dead-card warning survives.
      expect(
        quiet.map((i) => i.category).toSet(),
        loud
            .where((i) => !i.category.isCardDeathWarning)
            .map((i) => i.category)
            .toSet(),
      );
    });
  });

  test('an insight without evidence cannot be built', () {
    expect(
      () => ReviewInsight(
        category: ReviewInsightCategory.safeDiscard,
        evidence: const [],
      ),
      throwsArgumentError,
    );
  });

  test(
    'across a real match, no insight ever names a card the player could not see',
    timeout: const Timeout(Duration(minutes: 8)),
    () {
      final state = buildCompletedMatch(seed: 13).recorderState;
      final timeline =
          (MatchReplayTimeline.build(
                MatchActionTranscript(
                  initialSnapshot: state.initialSnapshot!,
                  entries: state.entries,
                ),
              )
              as ReplayTimelineBuilt)
          .timeline;

      var reviewed = 0;
      for (var i = 1; i < timeline.length; i++) {
        final frame = timeline.frameAt(i);
        if (frame.kind != ReplayFrameKind.actionApplied) {
          continue;
        }
        final previous = timeline.frameAt(i - 1);
        final observation = ReviewObservation.fromFrames(
          previous: previous,
          applied: frame,
        );

        // Everything the reviewing seat could legitimately name.
        final visible = <String>{
          for (final card in observation.perspectiveHand) card.id,
          for (final card in observation.discardPile) card.id,
          if (observation.pendingDiscard != null)
            observation.pendingDiscard!.id,
          for (final melds in observation.visibleMelds.values)
            for (final meld in melds)
              for (final card in meld.cards) card.id,
          ...observation.publiclySeenCardIds,
        };

        // Everything only a cheat could name.
        final hidden = <String>{
          for (final seat in PlayerSeat.values)
            if (seat != observation.perspective)
              for (final card in previous.snapshot.hands[seat] ?? const [])
                card.id,
          for (final card in previous.snapshot.stock) card.id,
        }..removeAll(visible);

        for (final insight in ReplayAnalysisCoach.review(
          observation: observation,
          action: ReviewedAction.fromEntry(frame.appliedEntry!),
          settings: _narrateAll,
        )) {
          reviewed += 1;
          final referenced = insight.allReferencedCardIds;
          expect(
            referenced.intersection(hidden),
            isEmpty,
            reason:
                'frame $i (${insight.category.name}) named a hidden card',
          );
          expect(
            referenced.difference(visible),
            isEmpty,
            reason:
                'frame $i (${insight.category.name}) named a card from '
                'nowhere observable',
          );
        }
      }

      // A sweep that produced nothing would pass while proving nothing.
      expect(reviewed, greaterThan(100));
    },
  );
}
