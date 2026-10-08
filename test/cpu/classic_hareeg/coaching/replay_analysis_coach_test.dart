import 'dart:io';

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

import '../../../scenario/classic_hareeg_scenario.dart';

HareegCard _c(CardRank rank, CardSuit suit, {int deck = 0}) =>
    ScenarioCards.card(rank, suit, deckIndex: deck);

const _narrateAll = AnalysisCoachSettings(
  verbosity: AnalysisVerbosity.narrateAll,
  cardDeathWarnings: true,
);

({ReviewObservation observation, ReviewedAction action}) _situation({
  required ClassicHareegMatchSnapshot snapshot,
  required String actionId,
  PlayerSeat actor = PlayerSeat.south,
}) {
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
      seat: actor,
      roundNumber: snapshot.roundNumber,
      phase: TurnPhase.action,
      actionId: actionId,
    ),
  );
  return (
    observation: ReviewObservation.fromFrames(
      previous: previous,
      applied: applied,
    ),
    action: ReviewedAction.fromEntry(applied.appliedEntry!),
  );
}

List<ReviewInsight> _review({
  required ClassicHareegMatchSnapshot snapshot,
  required String actionId,
  PlayerSeat actor = PlayerSeat.south,
  AnalysisCoachSettings settings = _narrateAll,
}) {
  final situation = _situation(
    snapshot: snapshot,
    actionId: actionId,
    actor: actor,
  );
  return ReplayAnalysisCoach.review(
    observation: situation.observation,
    action: situation.action,
    settings: settings,
  );
}

ClassicHareegMatchSnapshot _position({
  List<HareegCard>? southHand,
  List<HareegCard>? discardPile,
  List<DiscardEvent>? discardHistoryEvents,
  PlayerSeat currentSeat = PlayerSeat.south,
}) {
  return ClassicHareegScenario.deal(
    southHand: southHand,
    discardPile: discardPile,
    discardHistoryEvents: discardHistoryEvents,
    currentSeat: currentSeat,
  ).controller.toSnapshot(savedAt: replayClockEpoch);
}

void main() {
  group('the coach has no route to hidden state', () {
    test('its signature accepts nothing that could carry one', () {
      // The boundary is the parameter list. If a controller, snapshot,
      // transcript or timeline could be passed in, "it does not look at hidden
      // state" would be a promise rather than a property.
      final source = File(
        'lib/cpu/classic_hareeg/coaching/replay_analysis_coach.dart',
      ).readAsStringSync();

      for (final forbidden in const [
        'classic_hareeg_game_controller.dart',
        'classic_hareeg_match_snapshot.dart',
        'match_action_transcript.dart',
        'match_replay_timeline.dart',
      ]) {
        expect(source, isNot(contains(forbidden)), reason: forbidden);
      }
    });

    test('it holds no mutable state between calls', () {
      final source = File(
        'lib/cpu/classic_hareeg/coaching/replay_analysis_coach.dart',
      ).readAsStringSync();

      // A `static` is an offender unless it is const, final, a method or a
      // getter. Stated as a denial rather than an allow-list, because an
      // allow-list of type names silently permits `static int calls = 0;`.
      final offenders = <String>[];
      for (final line in source.split('\n')) {
        final trimmed = line.trim();
        if (!trimmed.startsWith('static ')) {
          continue;
        }
        final isConstOrFinal =
            trimmed.startsWith('static const ') ||
            trimmed.startsWith('static final ');
        final isCallable = trimmed.contains('(') || trimmed.contains(' get ');
        if (!isConstOrFinal && !isCallable) {
          offenders.add(trimmed);
        }
      }
      expect(offenders, isEmpty);

      expect(source, isNot(contains('DateTime.now(')));
      expect(source, isNot(contains('Random(')));
    });

    test('the same position twice gives the same answer', () {
      final snapshot = _position(
        southHand: [
          _c(CardRank.seven, CardSuit.hearts),
          _c(CardRank.three, CardSuit.spades),
        ],
      );
      final actionId = 'discard:${_c(CardRank.seven, CardSuit.hearts).id}';

      String shape(List<ReviewInsight> insights) => [
        for (final insight in insights)
          '${insight.category.name}:${insight.severity.name}:'
              '${insight.cardIds.join("+")}:'
              '${insight.evidence.map((e) => e.kind.name).join(",")}',
      ].join('|');

      expect(
        shape(_review(snapshot: snapshot, actionId: actionId)),
        shape(_review(snapshot: snapshot, actionId: actionId)),
      );
    });
  });

  group('every claim rests on evidence that actually supports it', () {
    test('an insight cannot be built without evidence at all', () {
      expect(
        () => ReviewInsight(
          category: ReviewInsightCategory.safeDiscard,
          evidence: const [],
        ),
        throwsArgumentError,
      );
    });

    test('calling a discard safe cites what was checked, not a hand size', () {
      // "Nothing they have shown suggests this helps them" is a claim about
      // absence. A seat's hand count is observable and true, and says nothing
      // about it — evidence in name only.
      final insights = _review(
        snapshot: _position(
          southHand: [
            _c(CardRank.three, CardSuit.spades),
            _c(CardRank.nine, CardSuit.hearts),
          ],
        ),
        actionId: 'discard:${_c(CardRank.three, CardSuit.spades).id}',
      );

      final safe = insights.singleWhere(
        (i) => i.category == ReviewInsightCategory.safeDiscard,
      );

      expect(
        safe.evidence.map((e) => e.kind),
        everyElement(ReviewEvidenceKind.noPublicTell),
      );
      expect(
        safe.evidence.map((e) => e.kind),
        isNot(contains(ReviewEvidenceKind.handCount)),
        reason: 'a hand size does not support a claim about pickups or melds',
      );
      expect(safe.evidence.single.seat, isNotNull);
    });

    test('the negative assessment names the seat it was made about', () {
      final target = _c(CardRank.seven, CardSuit.clubs);
      final insights = _review(
        snapshot: _position(
          southHand: [_c(CardRank.three, CardSuit.spades)],
          discardHistoryEvents: [
            DiscardEvent(
              seat: PlayerSeat.east,
              card: target,
              kind: DiscardEventKind.pickup,
              sequence: 1,
            ),
          ],
        ),
        actionId: 'discard:${_c(CardRank.three, CardSuit.spades).id}',
      );

      final safe = insights.singleWhere(
        (i) => i.category == ReviewInsightCategory.safeDiscard,
      );
      final evidence = safe.evidence.single;

      // The pickups that were examined are carried, so the claim can be
      // checked rather than taken on trust.
      expect(evidence.seat, PlayerSeat.east);
      expect(evidence.cardIds, contains(target.id));
    });

    test('no insight cites a fact about a seat it is not about', () {
      final insights = _review(
        snapshot: _position(
          southHand: [
            _c(CardRank.three, CardSuit.spades),
            _c(CardRank.nine, CardSuit.hearts),
          ],
        ),
        actionId: 'discard:${_c(CardRank.three, CardSuit.spades).id}',
      );

      for (final insight in insights) {
        for (final evidence in insight.evidence) {
          if (evidence.seat == null || insight.subjectSeat == null) {
            continue;
          }
          final aboutSubject = evidence.seat == insight.subjectSeat;
          final aboutReviewer = evidence.seat == reviewPerspectiveSeat;
          expect(
            aboutSubject || aboutReviewer,
            isTrue,
            reason:
                '${insight.category.name} cited ${evidence.kind.name} about '
                '${evidence.seat!.name}, which it is not about',
          );
        }
      }
    });
  });

  group('settings shape what is shown, not what is concluded', () {
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

    test('generation ignores the settings entirely', () {
      final situation = _situation(snapshot: snapshot, actionId: actionId);
      final generated = ReplayAnalysisCoach.generate(
        observation: situation.observation,
        action: situation.action,
      );

      expect(generated, isNotEmpty);
      expect(
        ReplayAnalysisCoach.generate(
          observation: situation.observation,
          action: situation.action,
        ).map((i) => i.category),
        generated.map((i) => i.category),
      );
    });

    test('the quietest level keeps only clear mistakes', () {
      final quiet = _review(
        snapshot: snapshot,
        actionId: actionId,
        settings: const AnalysisCoachSettings(
          verbosity: AnalysisVerbosity.clearMistakes,
          cardDeathWarnings: true,
        ),
      );

      expect(quiet, isNotEmpty);
      expect(
        quiet.every((i) => i.severity == ReviewSeverity.mistake),
        isTrue,
      );
    });

    test('silencing dead-card warnings leaves the rest alone', () {
      final loud = _review(snapshot: snapshot, actionId: actionId);
      final quiet = _review(
        snapshot: snapshot,
        actionId: actionId,
        settings: const AnalysisCoachSettings(
          verbosity: AnalysisVerbosity.narrateAll,
          cardDeathWarnings: false,
        ),
      );

      expect(
        loud.map((i) => i.category),
        contains(ReviewInsightCategory.deadDevelopmentKept),
      );
      expect(
        quiet.map((i) => i.category),
        isNot(contains(ReviewInsightCategory.deadDevelopmentKept)),
      );
      expect(
        quiet.map((i) => i.category).toSet(),
        loud
            .where((i) => !i.category.isCardDeathWarning)
            .map((i) => i.category)
            .toSet(),
      );
    });
  });
}
