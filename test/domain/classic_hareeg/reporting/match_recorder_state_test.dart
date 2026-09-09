import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_recorder.dart';

void main() {
  ClassicHareegMatchSnapshot buildSnapshot({
    int seed = 7,
    int roundNumber = 1,
  }) {
    final round = ClassicHareegRound.deal(
      setup: ClassicHareegSetup.defaults(),
      seed: seed,
    );
    return ClassicHareegMatchSnapshot(
      setup: round.setup,
      hands: round.hands,
      stock: round.stock,
      discardPile: round.discardPile,
      starter: round.starter,
      currentSeat: round.currentSeat,
      turnPhase: round.turnPhase,
      roundNumber: roundNumber,
      savedAt: DateTime.utc(2026, 8, 22),
    );
  }

  MatchRecorder recorderWithActions(int count, {int fromRound = 1}) {
    final recorder = MatchRecorder()..captureInitialState(buildSnapshot());
    for (var i = 0; i < count; i++) {
      recorder.recordAction(
        seat: PlayerSeat.values[i % PlayerSeat.values.length],
        roundNumber: fromRound,
        phase: TurnPhase.action,
        actionId: 'action-$i',
      );
    }
    return recorder;
  }

  group('MatchRecorderState', () {
    test('rejects a present non-object initial snapshot', () {
      for (final malformed in <Object>['oops', 7, <Object>[]]) {
        final json = recorderWithActions(1).toState().toJson()
          ..['initialSnapshot'] = malformed;
        expect(() => MatchRecorderState.fromJson(json), throwsFormatException);
      }
    });

    test('allows an absent or null initial snapshot', () {
      final json = recorderWithActions(0).toState().toJson()
        ..remove('initialSnapshot');
      expect(MatchRecorderState.fromJson(json).initialSnapshot, isNull);
      json['initialSnapshot'] = null;
      expect(MatchRecorderState.fromJson(json).initialSnapshot, isNull);
    });
    test('captures the base snapshot, entries, and next order', () {
      final state = recorderWithActions(3).toState();

      expect(state.initialSnapshot, isNotNull);
      expect(state.entries, hasLength(3));
      expect(state.nextOrder, 3);
    });

    test('round-trips losslessly, field by field', () {
      final original = recorderWithActions(4).toState();

      final restored = MatchRecorderState.fromJson(original.toJson());

      expect(restored.nextOrder, original.nextOrder);
      expect(restored.entries, hasLength(original.entries.length));
      for (var i = 0; i < original.entries.length; i++) {
        expect(restored.entries[i].order, original.entries[i].order);
        expect(restored.entries[i].seat, original.entries[i].seat);
        expect(
          restored.entries[i].roundNumber,
          original.entries[i].roundNumber,
        );
        expect(restored.entries[i].phase, original.entries[i].phase);
        expect(restored.entries[i].actionId, original.entries[i].actionId);
      }
      expect(
        restored.initialSnapshot!.hands[PlayerSeat.south]!.first.id,
        original.initialSnapshot!.hands[PlayerSeat.south]!.first.id,
      );
    });

    test('rejects an unsupported schema version', () {
      final json = recorderWithActions(1).toState().toJson()..['version'] = 99;

      expect(() => MatchRecorderState.fromJson(json), throwsFormatException);
    });

    test('rejects duplicate entry orders', () {
      final json = recorderWithActions(3).toState().toJson();
      final entries = json['entries']! as List<Object?>;
      entries[2] = {...entries[1]! as Map<String, Object?>};

      expect(() => MatchRecorderState.fromJson(json), throwsFormatException);
    });

    test('rejects reordered entries', () {
      final json = recorderWithActions(3).toState().toJson();
      final entries = json['entries']! as List<Object?>;
      json['entries'] = [entries[2], entries[1], entries[0]];

      expect(() => MatchRecorderState.fromJson(json), throwsFormatException);
    });

    test('rejects a stale next-order counter', () {
      // A counter at or below the last recorded order would make the next
      // action collide with one already in the transcript.
      final json = recorderWithActions(4).toState().toJson()..['nextOrder'] = 2;

      expect(() => MatchRecorderState.fromJson(json), throwsFormatException);
    });

    test('rejects a negative order counter', () {
      final json = recorderWithActions(1).toState().toJson()
        ..['nextOrder'] = -1;

      expect(() => MatchRecorderState.fromJson(json), throwsFormatException);
    });
  });

  group('MatchRecorder.restore', () {
    test('continues the match-wide order instead of restarting it', () {
      final state = recorderWithActions(5).toState();

      final resumed = MatchRecorder.restore(state)
        ..recordAction(
          seat: PlayerSeat.south,
          roundNumber: 2,
          phase: TurnPhase.action,
          actionId: 'after-resume',
        );

      final transcript = resumed.transcript!;
      expect(transcript.entries, hasLength(6));
      expect(transcript.entries.last.order, 5);
      expect(transcript.entries.last.actionId, 'after-resume');
    });

    test('ignores captureInitialState so the transcript is not rebased', () {
      // This is the bug the sprint exists to fix. A resumed match used to build
      // a fresh recorder, which captured the resumed round as its base and
      // silently dropped every earlier action.
      final state = recorderWithActions(3).toState();
      final originalBase = state.initialSnapshot!;

      final resumed = MatchRecorder.restore(state)
        // The resumed controller offers its own round as a base, as it does
        // for every fresh recorder.
        ..captureInitialState(buildSnapshot(seed: 99, roundNumber: 4));

      final transcript = resumed.transcript!;
      expect(transcript.entries, hasLength(3));
      expect(
        transcript.initialSnapshot.hands[PlayerSeat.south]!.first.id,
        originalBase.hands[PlayerSeat.south]!.first.id,
      );
    });

    test('a fresh recorder still accepts its first base snapshot', () {
      final recorder = MatchRecorder()
        ..captureInitialState(buildSnapshot())
        ..recordAction(
          seat: PlayerSeat.south,
          roundNumber: 1,
          phase: TurnPhase.action,
          actionId: 'first',
        );

      expect(recorder.transcript, isNotNull);
    });

    test('carries the Fifty counters across the restore', () {
      final recorder = recorderWithActions(1)
        ..recordAction(
          seat: PlayerSeat.south,
          roundNumber: 1,
          phase: TurnPhase.action,
          actionId: 'claim-fifty',
        )
        ..recordFiftySuccess(PlayerSeat.south);

      final resumed = MatchRecorder.restore(recorder.toState());

      expect(resumed.fiftyCounters.attemptsFor(PlayerSeat.south), 1);
      expect(resumed.fiftyCounters.successesFor(PlayerSeat.south), 1);
    });
  });

  group('Fifty counting', () {
    test('counts an explicit claim as an attempt at the action seam', () {
      final recorder = MatchRecorder()
        ..captureInitialState(buildSnapshot())
        ..recordAction(
          seat: PlayerSeat.east,
          roundNumber: 1,
          phase: TurnPhase.action,
          actionId: 'claim-fifty',
        );

      expect(recorder.fiftyCounters.attemptsFor(PlayerSeat.east), 1);
      expect(recorder.fiftyCounters.successesFor(PlayerSeat.east), 0);
    });

    test('does not count a windowed take that happens to be a Fifty', () {
      final recorder = MatchRecorder()
        ..captureInitialState(buildSnapshot())
        ..recordAction(
          seat: PlayerSeat.south,
          roundNumber: 1,
          phase: TurnPhase.draw,
          actionId: 'take-discard',
        );

      expect(recorder.fiftyCounters.attemptsFor(PlayerSeat.south), 0);
    });

    test('a success needs a recorded claim from the same seat', () {
      final recorder = MatchRecorder()..captureInitialState(buildSnapshot());

      expect(
        () => recorder.recordFiftySuccess(PlayerSeat.south),
        throwsStateError,
      );
    });

    test('counts exactly, past the capped diagnostic log', () {
      // The diagnostic log holds 200 events and drops the oldest. Counters
      // derived from it would undercount a long match, which is why they are
      // accumulated separately.
      final recorder = MatchRecorder(diagnosticCapacity: 10)
        ..captureInitialState(buildSnapshot());

      for (var i = 0; i < 300; i++) {
        recorder
          ..recordAction(
            seat: PlayerSeat.south,
            roundNumber: 1,
            phase: TurnPhase.action,
            actionId: 'claim-fifty',
          )
          ..recordPersistence(type: 'saved', roundNumber: 1);
      }

      expect(recorder.fiftyCounters.attemptsFor(PlayerSeat.south), 300);
      expect(recorder.diagnostics.events.length, lessThanOrEqualTo(10));
    });
  });
}
