import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/coaching/analysis_coach_settings.dart';
import 'package:hareeg_table/cpu/classic_hareeg/coaching/replay_analysis_coach.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart'
    show TurnPhase;
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/replay/match_replay_timeline.dart';
import 'package:hareeg_table/domain/classic_hareeg/replay/review_observation.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_action_transcript.dart';

import '../../../scenario/classic_hareeg_scenario.dart';
import '../../../support/completed_match_fixture.dart';

HareegCard _card(CardRank rank, CardSuit suit, {int deckIndex = 0}) =>
    ScenarioCards.card(rank, suit, deckIndex: deckIndex);

/// Wraps a crafted position as the pre-action frame of a review, paired with a
/// synthetic applied frame carrying [actionId].
({ReplayFrame previous, ReplayFrame applied}) _framesFor(
  ClassicHareegMatchSnapshot snapshot,
  String actionId, {
  PlayerSeat seat = PlayerSeat.south,
}) {
  final clock = replayClockEpoch;
  return (
    previous: ReplayFrame(
      index: 0,
      kind: ReplayFrameKind.initial,
      roundNumber: snapshot.roundNumber,
      snapshot: snapshot,
      clock: clock,
    ),
    applied: ReplayFrame(
      index: 1,
      kind: ReplayFrameKind.actionApplied,
      roundNumber: snapshot.roundNumber,
      snapshot: snapshot,
      clock: clock.add(const Duration(seconds: 1)),
      appliedEntry: MatchActionTranscriptEntry(
        order: 0,
        seat: seat,
        roundNumber: snapshot.roundNumber,
        phase: TurnPhase.action,
        actionId: actionId,
      ),
    ),
  );
}

ReviewObservation _observe(
  ClassicHareegMatchSnapshot snapshot,
  String actionId, {
  PlayerSeat seat = PlayerSeat.south,
}) {
  final frames = _framesFor(snapshot, actionId, seat: seat);
  return ReviewObservation.fromFrames(
    previous: frames.previous,
    applied: frames.applied,
  );
}

/// Two positions that are identical to anyone sitting at the table, but differ
/// in what the other three seats are holding.
({ClassicHareegMatchSnapshot a, ClassicHareegMatchSnapshot b}) _hiddenVariants() {
  final southHand = [
    _card(CardRank.seven, CardSuit.hearts),
    _card(CardRank.seven, CardSuit.spades),
    _card(CardRank.king, CardSuit.clubs),
    _card(CardRank.four, CardSuit.diamonds),
  ];
  final pile = [
    _card(CardRank.two, CardSuit.clubs),
    _card(CardRank.nine, CardSuit.diamonds),
  ];

  ClassicHareegMatchSnapshot build({
    required List<HareegCard> eastHand,
    required List<HareegCard> northHand,
    required List<HareegCard> westHand,
  }) {
    return ClassicHareegScenario.deal(
      southHand: southHand,
      eastHand: eastHand,
      northHand: northHand,
      westHand: westHand,
      discardPile: pile,
      currentSeat: PlayerSeat.south,
    ).controller.toSnapshot(savedAt: DateTime.utc(2026, 1, 1));
  }

  return (
    // Variant A: East is sitting on two more sevens, so South's seven is a
    // gift. Variant B: East cannot use it at all.
    a: build(
      eastHand: [
        _card(CardRank.seven, CardSuit.clubs),
        _card(CardRank.seven, CardSuit.diamonds),
        _card(CardRank.three, CardSuit.spades),
      ],
      northHand: [
        _card(CardRank.five, CardSuit.hearts),
        _card(CardRank.six, CardSuit.hearts),
        _card(CardRank.jack, CardSuit.spades),
      ],
      westHand: [
        _card(CardRank.ten, CardSuit.clubs),
        _card(CardRank.queen, CardSuit.diamonds),
        _card(CardRank.eight, CardSuit.spades),
      ],
    ),
    b: build(
      eastHand: [
        _card(CardRank.two, CardSuit.hearts),
        _card(CardRank.five, CardSuit.spades),
        _card(CardRank.jack, CardSuit.diamonds),
      ],
      northHand: [
        _card(CardRank.ten, CardSuit.hearts),
        _card(CardRank.three, CardSuit.clubs),
        _card(CardRank.queen, CardSuit.spades),
      ],
      westHand: [
        _card(CardRank.four, CardSuit.clubs),
        _card(CardRank.nine, CardSuit.spades),
        _card(CardRank.eight, CardSuit.hearts),
      ],
    ),
  );
}

/// A TEST-ONLY full-information judgement, deliberately kept out of production.
///
/// It exists to prove the two hidden variants genuinely differ in a way a
/// cheating coach could have exploited. Without it, comparing the coach's
/// output across two arbitrary hidden hands would prove nothing: two variants
/// that were never going to change the answer would compare equal for reasons
/// having nothing to do with the evidence boundary.
///
/// `ReplayAnalysisCoach.review` cannot reach this: its parameter list has no
/// place to put a hidden hand.
bool _wouldCompleteAnEastSet(
  ClassicHareegMatchSnapshot snapshot,
  HareegCard discarded,
) {
  final identity = discarded.identity;
  if (identity == null) {
    return false;
  }
  final matching = (snapshot.hands[PlayerSeat.east] ?? const [])
      .where((card) => card.identity?.rank == identity.rank)
      .length;
  return matching >= 2;
}

void main() {
  final sevenOfHearts = _card(CardRank.seven, CardSuit.hearts);
  final discardSeven = 'discard:${sevenOfHearts.id}';

  group('the observation cannot express hidden state', () {
    test('it carries exactly the agreed observable fields', () {
      // An inventory rather than a spot check: adding a field to the
      // observation is a decision about the evidence boundary, and this test
      // is what forces that decision to be made deliberately.
      const expected = {
        'perspective',
        'actingSeat',
        'roundNumber',
        'currentSeat',
        'turnPhase',
        'perspectiveHand',
        'discardPile',
        'visibleMelds',
        'handCounts',
        'stockCount',
        'scores',
        'activeSeats',
        'removedSeats',
        'openedSeats',
        'pendingDiscard',
        'fiftyWindow',
        'discardHistoryEvents',
        'deckCopyCount',
        'tableStrictness',
        'openingRequirement',
        'signature',
      };

      final file = const LocalFileSystemReader().readReviewObservation();
      // Scoped to the observation itself: the small helper types alongside it
      // (a Fifty window view, a parsed action) have their own fields, and
      // sweeping the whole file would police the wrong thing.
      final start = file.indexOf('class ReviewObservation {');
      expect(start, greaterThan(0));
      final source = file.substring(start);
      final declared = RegExp(
        r'^\s*(?:final|late final)\s+[\w<>?, ]+\s+(\w+)\s*(?:=|;)',
        multiLine: true,
      ).allMatches(source).map((m) => m.group(1)!).toSet();

      expect(
        declared.difference(expected),
        isEmpty,
        reason:
            'A new field on ReviewObservation widens what the analysis coach '
            'can see. If it is observable, add it to this list deliberately; '
            'if it is not, it must not be here at all.',
      );
    });

    test('two hands the player cannot see produce the same observation', () {
      final variants = _hiddenVariants();

      final a = _observe(variants.a, discardSeven);
      final b = _observe(variants.b, discardSeven);

      expect(a, b);
      expect(a.signature, b.signature);
    });

    test('a different stock at the same count produces the same observation', () {
      final base = ClassicHareegScenario.deal(currentSeat: PlayerSeat.south);
      final snapshot = base.controller.toSnapshot(
        savedAt: DateTime.utc(2026, 1, 1),
      );
      final shuffled = ClassicHareegMatchSnapshot.fromJson({
        ...snapshot.toJson(),
        'stock': [
          for (final card in snapshot.stock.reversed) card.toJson(),
        ],
      });

      expect(shuffled.stock.length, snapshot.stock.length);
      expect(
        shuffled.stock.map((c) => c.id).toList(),
        isNot(snapshot.stock.map((c) => c.id).toList()),
      );

      expect(
        _observe(snapshot, 'draw-stock'),
        _observe(shuffled, 'draw-stock'),
      );
    });

    test('the hand order the player happens to be using is not observable', () {
      final base = ClassicHareegScenario.deal(currentSeat: PlayerSeat.south);
      final snapshot = base.controller.toSnapshot(
        savedAt: DateTime.utc(2026, 1, 1),
      );
      final reordered = ClassicHareegMatchSnapshot.fromJson({
        ...snapshot.toJson(),
        'hands': {
          ...(snapshot.toJson()['hands']! as Map).cast<String, Object?>(),
          'south': [
            for (final card
                in (snapshot.hands[PlayerSeat.south] ?? const []).reversed)
              card.toJson(),
          ],
        },
      });

      expect(
        _observe(snapshot, 'draw-stock'),
        _observe(reordered, 'draw-stock'),
      );
    });
  });

  group('the coach cannot see what the observation cannot carry', () {
    test('identical observable positions yield identical advice', () {
      final variants = _hiddenVariants();

      // First establish that the two variants really do differ where a
      // full-information judge would care. Without this the comparison below
      // could pass for the wrong reason.
      expect(
        _wouldCompleteAnEastSet(variants.a, sevenOfHearts),
        isTrue,
        reason: 'variant A must make the discard a genuine gift',
      );
      expect(
        _wouldCompleteAnEastSet(variants.b, sevenOfHearts),
        isFalse,
        reason: 'variant B must make the discard harmless',
      );

      final settings = AnalysisCoachSettings(
        verbosity: AnalysisVerbosity.narrateAll,
        cardDeathWarnings: true,
      );

      List<String> adviceFor(ClassicHareegMatchSnapshot snapshot) {
        final frames = _framesFor(snapshot, discardSeven);
        final observation = ReviewObservation.fromFrames(
          previous: frames.previous,
          applied: frames.applied,
        );
        return [
          for (final insight in ReplayAnalysisCoach.review(
            observation: observation,
            action: ReviewedAction.fromEntry(frames.applied.appliedEntry!),
            settings: settings,
          ))
            '${insight.category.name}:${insight.severity.name}:'
                '${insight.cardIds.join("+")}:'
                '${insight.evidence.map((e) => e.kind.name).join(",")}',
        ];
      }

      expect(adviceFor(variants.a), adviceFor(variants.b));
    });

    test('the coach reaches none of the types that carry hidden state', () {
      final source = const LocalFileSystemReader().readCoach();
      for (final forbidden in const [
        'classic_hareeg_game_controller.dart',
        'classic_hareeg_match_snapshot.dart',
        'match_action_transcript.dart',
        'match_replay_timeline.dart',
      ]) {
        expect(
          source,
          isNot(contains(forbidden)),
          reason:
              'Importing $forbidden would give the coach a route to hidden '
              'state, and the boundary would become a promise rather than a '
              'property.',
        );
      }
    });
  });

  test('truncating the future does not change an earlier observation', () {
    // What happened later cannot retroactively change what was knowable at the
    // time, so an insight at step i must not depend on step i+1 existing.
    final state = buildCompletedMatch(seed: 13).recorderState;
    final full = MatchActionTranscript(
      initialSnapshot: state.initialSnapshot!,
      entries: state.entries,
    );
    final fullTimeline =
        (MatchReplayTimeline.build(full) as ReplayTimelineBuilt).timeline;

    for (final cut in [40, 120, 260]) {
      final truncated = MatchActionTranscript(
        initialSnapshot: state.initialSnapshot!,
        entries: state.entries.take(cut).toList(),
      );
      final shortTimeline =
          (MatchReplayTimeline.build(truncated) as ReplayTimelineBuilt).timeline;

      final index = shortTimeline.length - 1;
      expect(shortTimeline.frameAt(index).kind, ReplayFrameKind.actionApplied);

      final fromShort = ReviewObservation.fromFrames(
        previous: shortTimeline.frameAt(index - 1),
        applied: shortTimeline.frameAt(index),
      );
      final fromFull = ReviewObservation.fromFrames(
        previous: fullTimeline.frameAt(index - 1),
        applied: fullTimeline.frameAt(index),
      );

      expect(fromShort, fromFull, reason: 'cut after $cut actions');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('a frame that applied no action cannot be reviewed', () {
    final base = ClassicHareegScenario.deal();
    final snapshot = base.controller.toSnapshot(savedAt: DateTime.utc(2026));
    final initial = ReplayFrame(
      index: 0,
      kind: ReplayFrameKind.initial,
      roundNumber: snapshot.roundNumber,
      snapshot: snapshot,
      clock: replayClockEpoch,
    );

    expect(
      () => ReviewObservation.fromFrames(previous: initial, applied: initial),
      throwsArgumentError,
    );
  });
}

/// Reads the two source files whose *shape* is part of the contract.
class LocalFileSystemReader {
  const LocalFileSystemReader();

  String readReviewObservation() => _read(
    'lib/domain/classic_hareeg/replay/review_observation.dart',
  );

  String readCoach() =>
      _read('lib/cpu/classic_hareeg/coaching/replay_analysis_coach.dart');

  String _read(String path) => File(path).readAsStringSync();
}
