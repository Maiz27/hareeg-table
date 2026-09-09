import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/replay/replay_branch_seed.dart';
import 'package:hareeg_table/domain/classic_hareeg/replay/replay_reconstruction.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_action_transcript.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_recorder.dart';

import '../../../scenario/classic_hareeg_scenario.dart';

final _clock = replayClockEpoch;
const _seat = PlayerSeat.south;

ClassicHareegGameController _beforeClaim() {
  HareegCard card(CardRank rank, CardSuit suit) =>
      ScenarioCards.card(rank, suit, deckIndex: 1);
  return ClassicHareegScenario.deal(
    southHand: [
      card(CardRank.two, CardSuit.diamonds),
      card(CardRank.seven, CardSuit.diamonds),
      card(CardRank.three, CardSuit.diamonds),
      card(CardRank.seven, CardSuit.spades),
      card(CardRank.four, CardSuit.diamonds),
      card(CardRank.ace, CardSuit.spades),
    ],
    discardPile: [card(CardRank.seven, CardSuit.hearts)],
    currentSeat: _seat,
    turnPhase: TurnPhase.draw,
    fiftyWindowOpenedAt: _clock,
    now: () => _clock,
  ).controller;
}

ClassicHareegGameController _claimed() {
  final controller = _beforeClaim();
  expect(controller.applyAction('claim-fifty').isSuccess, isTrue);
  return controller;
}

ClassicHareegMatchSnapshot _save(ClassicHareegGameController c) =>
    c.toPositionSnapshot(savedAt: _clock);

ClassicHareegGameController _load(Map<String, Object?> json) =>
    ClassicHareegGameController.fromSnapshot(
      ClassicHareegMatchSnapshot.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, Object?>,
      ),
      now: () => _clock,
    );

void _finish(ClassicHareegGameController controller) {
  for (var i = 0; i < 10 && !controller.isRoundOver; i++) {
    final action = controller.cpuActionIdsFor(_seat).single;
    final result = controller.applyAction(action);
    expect(result.isSuccess, isTrue, reason: action);
    expect(result.wasReverted, isFalse);
  }
  expect(controller.isRoundOver, isTrue);
  expect(controller.roundResult?.winner, _seat);
  expect(_save(controller).activeFiftyProofActions, isNull);
}

void main() {
  test('exact snapshot saves only the immutable unplayed suffix', () {
    final controller = _claimed();
    final before = _save(controller);
    final actions = before.activeFiftyProofActions!;
    expect(actions, hasLength(3));
    expect(() => actions.add('discard:bad'), throwsUnsupportedError);
    expect(controller.applyAction(actions.first).isSuccess, isTrue);
    final after = _save(controller);
    expect(after.activeFiftyProofActions, actions.skip(1).toList());
    expect(before.activeFiftyProofActions, hasLength(3));
    final json = after.toJson();
    final decoded = ClassicHareegMatchSnapshot.fromJson(json);
    expect(
      () => decoded.activeFiftyProofActions!.clear(),
      throwsUnsupportedError,
    );
    final resumed = _load(json);
    expect(resumed.cpuActionIdsFor(_seat).single, actions[1]);
    _finish(controller);
    _finish(resumed);
    expect(_save(resumed).toJson(), _save(controller).toJson());
  });

  test('older exact saves without a script still replan and finish', () {
    final controller = _claimed();
    expect(
      controller
          .applyAction(controller.cpuActionIdsFor(_seat).single)
          .isSuccess,
      isTrue,
    );
    final json = _save(controller).toJson()..remove('activeFiftyProofActions');
    final resumed = _load(json);
    _finish(resumed);
    _finish(controller);
    expect(_save(resumed).toJson(), _save(controller).toJson());
  });

  test(
    'rollback projection never pairs a remaining suffix with an earlier board',
    () {
      final controller = _claimed();
      expect(
        controller
            .applyAction(controller.cpuActionIdsFor(_seat).single)
            .isSuccess,
        isTrue,
      );
      final json = controller.toSnapshot(savedAt: _clock).toJson();
      expect(json.containsKey('activeFiftyProofActions'), isFalse);
      _finish(_load(json));
    },
  );

  test('off-script legal play invalidates the persisted plan', () {
    final controller = _claimed();
    final actions = _save(controller).activeFiftyProofActions!;
    // Play the other meld first, as a human can during a proof turn.
    expect(controller.applyAction(actions[1]).isSuccess, isTrue);
    expect(_save(controller).activeFiftyProofActions, isNull);
    final resumed = _load(_save(controller).toJson());
    expect(resumed.cpuActionIdsFor(_seat), controller.cpuActionIdsFor(_seat));
    _finish(resumed);
    _finish(controller);
  });

  test(
    'proof actions are ignored without an active claim or exact journal',
    () {
      final controller = _beforeClaim();
      final json = _save(controller).toJson();
      final poisoned = {
        ...json,
        'activeFiftyProofActions': ['discard:bad'],
      };
      expect(
        _load(poisoned).cpuActionIdsFor(_seat),
        controller.cpuActionIdsFor(_seat),
      );
      final claim = _claimed();
      final rollback = claim.toSnapshot(savedAt: _clock).toJson()
        ..['activeFiftyProofActions'] = ['discard:bad'];
      expect(
        _load(rollback).cpuActionIdsFor(_seat),
        claim.cpuActionIdsFor(_seat),
      );
    },
  );

  test('malformed proof action metadata fails decoding', () {
    final json = _save(_claimed()).toJson();
    for (final invalid in <Object>[
      'not a list',
      [],
      [42],
      [''],
    ]) {
      expect(
        () => _load({...json, 'activeFiftyProofActions': invalid}),
        throwsFormatException,
      );
    }
  });

  test('encoding an empty proof suffix omits it and round-trips', () {
    final base = _save(_claimed());
    final snapshot = ClassicHareegMatchSnapshot(
      setup: base.setup,
      hands: base.hands,
      stock: base.stock,
      discardPile: base.discardPile,
      starter: base.starter,
      currentSeat: base.currentSeat,
      turnPhase: base.turnPhase,
      savedAt: base.savedAt,
      scores: base.scores,
      turnJournal: base.turnJournal,
      activeFiftyProofActions: const [],
    );
    expect(snapshot.turnJournal, isNotNull);
    final json = snapshot.toJson();
    expect(json.containsKey('activeFiftyProofActions'), isFalse);
    final decoded = ClassicHareegMatchSnapshot.fromJson(
      jsonDecode(jsonEncode(json)) as Map<String, Object?>,
    );
    expect(decoded.activeFiftyProofActions, isNull);
    expect(decoded.toJson(), json);
  });

  test(
    'stale, unknown and truncated scripts replan without mutating the board',
    () {
      final controller = _claimed();
      final snapshot = _save(controller);
      final actions = snapshot.activeFiftyProofActions!;
      for (final stale in [
        [actions.last, ...actions], // An early discard is illegal.
        ['old-format-action'],
        [actions.first, 'old-format-action'], // Valid head, stale tail.
        [actions.first], // Legal prefix but no completed proof.
        ['place-cover:east:999:deck-1-two-diamonds', actions.last],
      ]) {
        final json = {...snapshot.toJson(), 'activeFiftyProofActions': stale};
        final encoded = jsonEncode(json);
        final restored = _load(json);
        expect(restored.isRoundOver, isFalse);
        expect(restored.isFiftyProofTurn, isTrue);
        expect(_save(restored).activeFiftyProofActions, isNull);
        expect(
          _save(restored).toJson()..remove('activeFiftyProofActions'),
          snapshot.toJson()..remove('activeFiftyProofActions'),
        );
        expect(
          jsonEncode(json),
          encoded,
          reason: 'caller snapshot is untouched',
        );
        expect(
          restored.cpuActionIdsFor(_seat),
          controller.cpuActionIdsFor(_seat),
        );
        _finish(restored);
      }
    },
  );

  test('validating a stored proof never records speculative actions', () {
    final snapshot = _save(_claimed());
    final before = jsonEncode(snapshot.toJson());
    final recorder = MatchRecorder()..captureInitialState(snapshot);
    final recordedBefore = recorder.toState().toJson();
    final restored = ClassicHareegGameController.fromSnapshot(
      snapshot,
      now: () => _clock,
      recorder: recorder,
    );
    expect(_save(restored).toJson(), snapshot.toJson());
    expect(jsonEncode(snapshot.toJson()), before);
    expect(recorder.toState().toJson(), recordedBefore);
    expect(restored.isRoundOver, isFalse);
  });

  test('reconstructed and branched frames preserve the proof suffix', () {
    final controller = _beforeClaim();
    final initial = controller.toSnapshot(savedAt: _clock);
    expect(controller.applyAction('claim-fifty').isSuccess, isTrue);
    final first = controller.cpuActionIdsFor(_seat).single;
    expect(controller.applyAction(first).isSuccess, isTrue);
    final expected = _save(controller).activeFiftyProofActions;
    final reconstruction = ReplayReconstruction(
      MatchActionTranscript(
        initialSnapshot: initial,
        entries: [
          MatchActionTranscriptEntry(
            order: 0,
            seat: _seat,
            roundNumber: 1,
            phase: TurnPhase.draw,
            actionId: 'claim-fifty',
          ),
          MatchActionTranscriptEntry(
            order: 1,
            seat: _seat,
            roundNumber: 1,
            phase: TurnPhase.action,
            actionId: first,
          ),
        ],
      ),
    );
    while (reconstruction.advance()) {}
    expect(reconstruction.failure, isNull);
    final frame = reconstruction.frames.last;
    expect(frame.snapshot.activeFiftyProofActions, expected);
    expect(
      () => frame.snapshot.activeFiftyProofActions!.clear(),
      throwsUnsupportedError,
    );
    final branch = ReplayBranchSeed.fromFrame(
      frame,
      nextFrame: null,
      branchStart: _clock.add(const Duration(days: 100)),
    )!;
    expect(branch.snapshot.activeFiftyProofActions, expected);
    expect(
      _load(branch.snapshot.toJson()).cpuActionIdsFor(_seat).single,
      expected!.first,
    );
  });
}
