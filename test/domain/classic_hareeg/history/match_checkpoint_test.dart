import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_checkpoint.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_terminal_facts.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_recorder.dart';

import '../../../support/test_fixtures.dart';

void main() {
  ClassicHareegMatchSnapshot buildSnapshot() {
    final round = ClassicHareegRound.deal(
      setup: ClassicHareegSetup.defaults(),
      seed: 7,
    );
    return ClassicHareegMatchSnapshot(
      setup: round.setup,
      hands: round.hands,
      stock: round.stock,
      discardPile: round.discardPile,
      starter: round.starter,
      currentSeat: round.currentSeat,
      turnPhase: round.turnPhase,
      savedAt: DateTime.utc(2026, 8, 22),
    );
  }

  /// Facts for a genuinely finished match: every seat scored, and exactly one
  /// survivor — the winner. Anything less no longer constructs.
  MatchTerminalFacts buildFacts() {
    return MatchTerminalFacts(
      completedAt: DateTime.utc(2026, 8, 22, 10),
      winner: PlayerSeat.south,
      finalScores: const {
        PlayerSeat.south: 5,
        PlayerSeat.east: 31,
        PlayerSeat.north: 33,
        PlayerSeat.west: 32,
      },
      roundCount: 4,
      eliminationRounds: const {
        PlayerSeat.west: 2,
        PlayerSeat.north: 3,
        PlayerSeat.east: 4,
      },
      seats: PlayerSeat.values,
    );
  }

  group('MatchCheckpoint', () {
    test('round-trips a live checkpoint', () {
      final checkpoint = MatchCheckpoint(
        matchId: testMatchId,
        snapshot: buildSnapshot(),
        eliminationRounds: const {PlayerSeat.west: 2},
        coachWasEnabled: true,
      );

      final restored = MatchCheckpoint.fromJson(checkpoint.toJson());

      expect(restored.matchId, testMatchId);
      expect(restored.isTerminal, isFalse);
      expect(restored.eliminationRounds[PlayerSeat.west], 2);
      expect(restored.coachWasEnabled, isTrue);
      expect(restored.fiftyCountersComplete, isTrue);
      expect(restored.replayIneligible, isFalse);
    });

    test('rejects an invalid match id', () {
      expect(
        () => MatchCheckpoint(matchId: 'a/b', snapshot: buildSnapshot()),
        throwsArgumentError,
      );
    });

    for (final field in const [
      'coachWasEnabled',
      'fiftyCountersComplete',
      'replayIneligible',
      'eliminationRounds',
    ]) {
      test('rejects a checkpoint missing "$field"', () {
        // Defaulting a lost field would silently hand back trust the checkpoint
        // had withdrawn: a missing replayIneligible makes a known-incomplete
        // match replayable again, and a missing fiftyCountersComplete presents
        // unknown counters as measured.
        final json = MatchCheckpoint(
          matchId: testMatchId,
          snapshot: buildSnapshot(),
          replayIneligible: true,
          fiftyCountersComplete: false,
        ).toJson()..remove(field);

        expect(() => MatchCheckpoint.fromJson(json), throwsFormatException);
      });
    }

    test('a terminal checkpoint refuses to advance', () {
      // A rematch is a new match. Advancing the finished one would save the
      // rematch under the old identity, already terminal — unresumable, and
      // unable to publish a second history entry.
      final terminal = MatchCheckpoint(
        matchId: testMatchId,
        snapshot: buildSnapshot(),
      ).terminalize(buildFacts());

      expect(
        () => terminal.withProgress(snapshot: buildSnapshot()),
        throwsStateError,
      );
    });

    for (final field in const ['recorderState', 'terminalFacts']) {
      test('rejects a present-but-null "$field"', () {
        // An omitted key is the documented absence — a legacy save with no
        // recorder, a live match with no terminal facts. A key that is present
        // and explicitly null is a record that once held something and no
        // longer does, which is damage, not absence.
        final json = MatchCheckpoint(
          matchId: testMatchId,
          snapshot: buildSnapshot(),
        ).toJson()..[field] = null;

        expect(json.containsKey(field), isTrue);
        expect(() => MatchCheckpoint.fromJson(json), throwsFormatException);
      });

      test('accepts an omitted "$field"', () {
        final json = MatchCheckpoint(
          matchId: testMatchId,
          snapshot: buildSnapshot(),
        ).toJson()..remove(field);

        expect(() => MatchCheckpoint.fromJson(json), returnsNormally);
      });

      test('rejects a present-but-malformed "$field"', () {
        // Absent and corrupt are different facts. Reading a damaged recorder as
        // "this match never had one" would quietly downgrade a replayable match
        // instead of reporting the damage.
        final json = MatchCheckpoint(
          matchId: testMatchId,
          snapshot: buildSnapshot(),
        ).toJson()..[field] = 'not-an-object';

        expect(() => MatchCheckpoint.fromJson(json), throwsFormatException);
      });
    }

    test('rejects a mistyped flag', () {
      final json = MatchCheckpoint(
        matchId: testMatchId,
        snapshot: buildSnapshot(),
      ).toJson()..['replayIneligible'] = 'yes';

      expect(() => MatchCheckpoint.fromJson(json), throwsFormatException);
    });

    test('a terminal checkpoint decodes without a live elimination map', () {
      // Absent by design once terminal: the frozen copy on the terminal facts
      // is the only one, so its absence must not be read as data loss.
      final json = MatchCheckpoint(
        matchId: testMatchId,
        snapshot: buildSnapshot(),
      ).terminalize(buildFacts()).toJson();

      expect(json.containsKey('eliminationRounds'), isFalse);
      expect(MatchCheckpoint.fromJson(json).isTerminal, isTrue);
    });

    test('rejects an unsupported schema version', () {
      final json = MatchCheckpoint(
        matchId: testMatchId,
        snapshot: buildSnapshot(),
      ).toJson()..['version'] = 99;

      expect(() => MatchCheckpoint.fromJson(json), throwsFormatException);
    });

    group('elimination rounds', () {
      test('merging never lowers a seat and never drops one', () {
        final merged = mergeEliminationRounds(
          const {PlayerSeat.west: 2, PlayerSeat.east: 5},
          // A resumed controller only knows about its own round, so it reports
          // west as going out later than it really did.
          const {PlayerSeat.west: 9, PlayerSeat.north: 7},
        );

        expect(merged[PlayerSeat.west], 2);
        expect(merged[PlayerSeat.east], 5);
        expect(merged[PlayerSeat.north], 7);
      });

      test('withProgress merges rather than replaces', () {
        final checkpoint = MatchCheckpoint(
          matchId: testMatchId,
          snapshot: buildSnapshot(),
          eliminationRounds: const {PlayerSeat.west: 2},
        );

        final advanced = checkpoint.withProgress(
          snapshot: buildSnapshot(),
          eliminationRounds: const {PlayerSeat.east: 6},
        );

        expect(advanced.eliminationRounds[PlayerSeat.west], 2);
        expect(advanced.eliminationRounds[PlayerSeat.east], 6);
      });

      test('a terminal checkpoint serializes exactly one map', () {
        final terminal = MatchCheckpoint(
          matchId: testMatchId,
          snapshot: buildSnapshot(),
          eliminationRounds: const {PlayerSeat.east: 4},
        ).terminalize(buildFacts());

        final json = terminal.toJson();

        // The live map is off the wire entirely once terminal; the frozen copy
        // on the terminal facts is the only one, so there is nothing to drift.
        expect(json.containsKey('eliminationRounds'), isFalse);
        expect(json.containsKey('terminalFacts'), isTrue);

        final restored = MatchCheckpoint.fromJson(json);
        expect(restored.isTerminal, isTrue);
        expect(restored.eliminationRounds[PlayerSeat.east], 4);
      });

      test('a terminal checkpoint reads eliminations through its facts', () {
        final terminal = MatchCheckpoint(
          matchId: testMatchId,
          snapshot: buildSnapshot(),
          // A stale live map that disagrees with the frozen one.
          eliminationRounds: const {PlayerSeat.north: 99},
        ).terminalize(buildFacts());

        expect(terminal.eliminationRounds, buildFacts().eliminationRounds);
        // The frozen value wins over the stale live one: north went out in
        // round 3, not round 99.
        expect(terminal.eliminationRounds[PlayerSeat.north], 3);
      });
    });

    group('sticky flags', () {
      test('coachWasEnabled turns on and never turns back off', () {
        var checkpoint = MatchCheckpoint(
          matchId: testMatchId,
          snapshot: buildSnapshot(),
        );

        expect(checkpoint.coachWasEnabled, isFalse);

        checkpoint = checkpoint.withCoachEnabled(false);
        expect(checkpoint.coachWasEnabled, isFalse);

        checkpoint = checkpoint.withCoachEnabled(true);
        expect(checkpoint.coachWasEnabled, isTrue);

        // Switching the coach off later does not undo having used it.
        checkpoint = checkpoint.withCoachEnabled(false);
        expect(checkpoint.coachWasEnabled, isTrue);
      });

      test('the coach flag survives progress and terminalization', () {
        final checkpoint = MatchCheckpoint(
          matchId: testMatchId,
          snapshot: buildSnapshot(),
        ).withCoachEnabled(true).withProgress(snapshot: buildSnapshot());

        expect(checkpoint.coachWasEnabled, isTrue);
        expect(checkpoint.terminalize(buildFacts()).coachWasEnabled, isTrue);
      });

      test('replayIneligible is sticky across progress and terminalization', () {
        final checkpoint = MatchCheckpoint(
          matchId: testMatchId,
          snapshot: buildSnapshot(),
        ).withReplayIneligible();

        expect(checkpoint.replayIneligible, isTrue);
        expect(
          checkpoint.withProgress(snapshot: buildSnapshot()).replayIneligible,
          isTrue,
        );
        expect(
          checkpoint.terminalize(buildFacts()).replayIneligible,
          isTrue,
        );
        expect(
          MatchCheckpoint.fromJson(checkpoint.toJson()).replayIneligible,
          isTrue,
        );
      });
    });

    test('Fifty counters come from the recorder state, not a second copy', () {
      final recorder = MatchRecorder()
        ..recordAction(
          seat: PlayerSeat.south,
          roundNumber: 1,
          phase: TurnPhase.action,
          actionId: 'claim-fifty',
        );

      final checkpoint = MatchCheckpoint(
        matchId: testMatchId,
        snapshot: buildSnapshot(),
        recorderState: recorder.toState(),
      );

      expect(checkpoint.fiftyCounters.attemptsFor(PlayerSeat.south), 1);
      // There is no independent counter field on the checkpoint that could
      // disagree with the recorder — the getter delegates.
      expect(
        checkpoint.toJson().containsKey('fiftyCounters'),
        isFalse,
      );
    });

    test('a checkpoint with no recorder reports empty counters', () {
      final checkpoint = MatchCheckpoint(
        matchId: testMatchId,
        snapshot: buildSnapshot(),
        fiftyCountersComplete: false,
      );

      expect(checkpoint.fiftyCounters.attemptsFor(PlayerSeat.south), 0);
      // The zero is only readable as "unknown" because completeness says so.
      expect(checkpoint.fiftyCountersComplete, isFalse);
    });
  });

  group('PendingMatchArchive', () {
    test('carries an id and nothing else', () {
      final pending = PendingMatchArchive(matchId: testMatchId);

      final json = pending.toJson();

      expect(json.keys.toSet(), {'version', 'matchId'});
      expect(PendingMatchArchive.fromJson(json).matchId, testMatchId);
    });

    test('rejects an invalid id and an unsupported version', () {
      expect(
        () => PendingMatchArchive(matchId: '../escape'),
        throwsArgumentError,
      );
      expect(
        () => PendingMatchArchive.fromJson(const {
          'version': 99,
          'matchId': testMatchId,
        }),
        throwsFormatException,
      );
    });
  });
}
