import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/history/match_replay_record.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_action_transcript.dart';

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

  MatchActionTranscript buildTranscript() {
    return MatchActionTranscript(
      initialSnapshot: buildSnapshot(),
      entries: [
        const MatchActionTranscriptEntry(
          order: 0,
          seat: PlayerSeat.south,
          roundNumber: 1,
          phase: TurnPhase.draw,
          actionId: 'draw-stock',
        ),
        const MatchActionTranscriptEntry(
          order: 1,
          seat: PlayerSeat.south,
          roundNumber: 1,
          phase: TurnPhase.action,
          actionId: 'discard:deck-0-two-spades',
        ),
      ],
    );
  }

  group('MatchReplayRecord', () {
    test('round-trips through JSON', () {
      final record = MatchReplayRecord(
        matchId: testMatchId,
        transcript: buildTranscript(),
      );

      final restored = MatchReplayRecord.fromJson(record.toJson());

      expect(restored.matchId, testMatchId);
      expect(restored.transcript.entries, hasLength(2));
      expect(restored.transcript.entries.first.actionId, 'draw-stock');
      expect(restored.transcript.entries.last.order, 1);
      expect(
        restored.transcript.initialSnapshot.hands[PlayerSeat.south]!.first.id,
        record.transcript.initialSnapshot.hands[PlayerSeat.south]!.first.id,
      );
    });

    test('carries the match id it belongs to', () {
      // The id is what lets a reader confirm the bytes it loaded are the match
      // it asked for, rather than trusting the file name it read them from.
      final record = MatchReplayRecord(
        matchId: testMatchId,
        transcript: buildTranscript(),
      );

      expect(record.toJson()['matchId'], testMatchId);
    });

    test('rejects an invalid match id on construction', () {
      expect(
        () => MatchReplayRecord(
          matchId: '../escape',
          transcript: buildTranscript(),
        ),
        throwsArgumentError,
      );
    });

    test('rejects an invalid match id on decode', () {
      final json = MatchReplayRecord(
        matchId: testMatchId,
        transcript: buildTranscript(),
      ).toJson()..['matchId'] = 'a/b';

      expect(() => MatchReplayRecord.fromJson(json), throwsFormatException);
    });

    test('rejects an unsupported schema version', () {
      final json = MatchReplayRecord(
        matchId: testMatchId,
        transcript: buildTranscript(),
      ).toJson()..['version'] = 99;

      expect(() => MatchReplayRecord.fromJson(json), throwsFormatException);
    });

    test('rejects a record with no transcript', () {
      final json = MatchReplayRecord(
        matchId: testMatchId,
        transcript: buildTranscript(),
      ).toJson()..remove('transcript');

      expect(() => MatchReplayRecord.fromJson(json), throwsFormatException);
    });

    test('rejects a non-monotonic transcript', () {
      final json = MatchReplayRecord(
        matchId: testMatchId,
        transcript: buildTranscript(),
      ).toJson();
      final transcript = json['transcript']! as Map<String, Object?>;
      transcript['entries'] = [
        (transcript['entries']! as List<Object?>)[1],
        (transcript['entries']! as List<Object?>)[0],
      ];

      expect(() => MatchReplayRecord.fromJson(json), throwsFormatException);
    });
  });
}
