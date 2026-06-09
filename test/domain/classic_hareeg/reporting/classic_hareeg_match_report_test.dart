import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/classic_hareeg_match_report.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/classic_hareeg_match_report_v1.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_action_transcript.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_diagnostic_event.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_diagnostic_log.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/match_progression_rules.dart';

void main() {
  group('ClassicHareegMatchReport', () {
    test('serializes and parses active match reports', () {
      final snapshot = _snapshot(
        seed: 17,
        currentSeat: PlayerSeat.east,
        turnPhase: TurnPhase.draw,
        roundNumber: 3,
        scores: const {
          PlayerSeat.south: -1,
          PlayerSeat.east: 8,
          PlayerSeat.north: 12,
          PlayerSeat.west: 3,
        },
      );
      final report = ClassicHareegMatchReport.active(
        app: _app,
        platform: 'windows',
        generatedAt: DateTime.utc(2026, 6, 9, 10, 30),
        snapshot: snapshot,
      );

      final json = report.toJson();
      final decoded = ClassicHareegMatchReport.fromJson(json);

      expect(json['version'], 1);
      expect(json['schema'], 'classic_hareeg_match_report');
      expect(json.containsKey('preferences'), isFalse);
      expect(json.containsKey('locale'), isFalse);
      expect(decoded.stage, MatchReportStage.active);
      expect(decoded.app.appId, _app.appId);
      expect(decoded.platform, 'windows');
      expect(decoded.generatedAt, DateTime.utc(2026, 6, 9, 10, 30));
      expect(decoded.setup.deckCount, snapshot.setup.deckCount);
      expect(decoded.seed, 17);
      expect(decoded.roundNumber, 3);
      expect(decoded.currentSeat, PlayerSeat.east);
      expect(decoded.turnPhase, TurnPhase.draw);
      expect(decoded.scores[PlayerSeat.north], 12);
      expect(decoded.snapshot.seed, 17);
      expect(decoded.snapshot.currentSeat, PlayerSeat.east);
    });

    test('serializes and parses completed match reports', () {
      final snapshot = _snapshot(
        seed: 23,
        roundNumber: 6,
        scores: const {
          PlayerSeat.south: -3,
          PlayerSeat.east: 31,
          PlayerSeat.north: 18,
          PlayerSeat.west: 24,
        },
      );
      const result = RoundProgressResult(
        type: RoundOutcomeType.normalFinish,
        winner: PlayerSeat.south,
        remainingCardCounts: {
          PlayerSeat.south: 0,
          PlayerSeat.east: 4,
          PlayerSeat.north: 7,
          PlayerSeat.west: 9,
        },
      );
      const progress = MatchProgressState(
        scores: {
          PlayerSeat.south: -3,
          PlayerSeat.east: 31,
          PlayerSeat.north: 18,
          PlayerSeat.west: 24,
        },
        activeSeats: [PlayerSeat.south],
        nextStarter: PlayerSeat.south,
        matchWinner: PlayerSeat.south,
      );
      final report = ClassicHareegMatchReport.completed(
        app: _app,
        platform: 'android',
        generatedAt: DateTime.utc(2026, 6, 9, 11),
        snapshot: snapshot,
        roundResult: result,
        matchProgress: progress,
      );

      final decoded = ClassicHareegMatchReport.fromJson(report.toJson());

      expect(decoded.stage, MatchReportStage.completed);
      expect(decoded.seed, 23);
      expect(decoded.roundResult!.type, RoundOutcomeType.normalFinish);
      expect(decoded.roundResult!.winner, PlayerSeat.south);
      expect(decoded.matchProgress!.matchWinner, PlayerSeat.south);
      expect(decoded.scores[PlayerSeat.east], 31);
      expect(decoded.snapshot.roundNumber, 6);
    });

    test('carries diagnostics and transcript through a JSON round-trip', () {
      final snapshot = _snapshot(seed: 53);
      final diagnostics = MatchDiagnosticLog(capacity: 16)
        ..record(
          category: MatchDiagnosticCategory.fifty,
          type: 'fiftyClaimed',
          roundNumber: 1,
          seat: PlayerSeat.south,
          phase: TurnPhase.draw,
        );
      final transcript = MatchActionTranscript(
        initialSnapshot: snapshot,
        entries: const [
          MatchActionTranscriptEntry(
            order: 0,
            seat: PlayerSeat.south,
            roundNumber: 1,
            phase: TurnPhase.action,
            actionId: 'draw-stock',
          ),
        ],
      );
      final report = ClassicHareegMatchReport.active(
        app: _app,
        platform: 'windows',
        generatedAt: DateTime.utc(2026, 6, 9, 16),
        snapshot: snapshot,
        diagnostics: diagnostics,
        transcript: transcript,
      );

      final decoded = ClassicHareegMatchReport.fromJson(report.toJson());

      expect(decoded.diagnostics, isNotNull);
      expect(decoded.diagnostics!.events.single.type, 'fiftyClaimed');
      expect(decoded.transcript, isNotNull);
      expect(decoded.transcript!.entries.single.actionId, 'draw-stock');
      expect(decoded.transcript!.initialSnapshot.seed, 53);
    });

    test('omits diagnostics and transcript keys when absent', () {
      final report = ClassicHareegMatchReport.active(
        app: _app,
        platform: 'windows',
        generatedAt: DateTime.utc(2026, 6, 9, 17),
        snapshot: _snapshot(seed: 59),
      );
      final json = report.toJson();

      expect(json.containsKey('diagnostics'), isFalse);
      expect(json.containsKey('transcript'), isFalse);
      // Older tooling that never wrote these fields still parses fine.
      final decoded = ClassicHareegMatchReport.fromJson(json);
      expect(decoded.diagnostics, isNull);
      expect(decoded.transcript, isNull);
    });

    test('parsing tolerates additive unknown fields', () {
      final report = ClassicHareegMatchReport.active(
        app: _app,
        platform: 'linux',
        generatedAt: DateTime.utc(2026, 6, 9, 12),
        snapshot: _snapshot(seed: 31),
      );
      final json = report.toJson()
        ..['futureTopLevelField'] = true
        ..['app'] = {
          ...(report.toJson()['app']! as Map<String, Object?>),
          'futureAppField': 'ignored',
        };

      final decoded = ClassicHareegMatchReport.fromJson(json);

      expect(decoded.stage, MatchReportStage.active);
      expect(decoded.seed, 31);
    });

    test('unsupported schema versions fail clearly', () {
      final report = ClassicHareegMatchReport.active(
        app: _app,
        platform: 'macOS',
        generatedAt: DateTime.utc(2026, 6, 9, 13),
        snapshot: _snapshot(seed: 41),
      );
      final json = report.toJson()..['version'] = 2;

      expect(
        () => ClassicHareegMatchReport.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Unsupported schema version 2'),
          ),
        ),
      );
    });

    test('v1 decoder reports encountered and expected versions', () {
      final report = ClassicHareegMatchReport.active(
        app: _app,
        platform: 'macOS',
        generatedAt: DateTime.utc(2026, 6, 9, 14),
        snapshot: _snapshot(seed: 43),
      );
      final json = report.toJson()..['version'] = 2;

      expect(
        () => decodeMatchReportV1(json),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'Unsupported match report version 2; expected 1.',
          ),
        ),
      );
    });

    test('completed reports reject malformed active seat lists', () {
      for (final (:activeSeats, :message) in [
        (
          activeSeats: ['south', 'dealer'],
          message: 'Unknown match report seat: dealer.',
        ),
        (
          activeSeats: ['south', 'south'],
          message: 'Duplicate match report seat: south.',
        ),
        (
          activeSeats: ['south', 7],
          message: 'Invalid match report seat value: 7.',
        ),
      ]) {
        expect(
          () => ClassicHareegMatchReport.fromJson(
            _completedReportJson(activeSeats: activeSeats),
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              message,
            ),
          ),
        );
      }
    });
  });
}

const _app = MatchReportAppMetadata(
  appId: 'com.maiz27.hareegtable',
  appName: 'Hareeg Table',
  version: '1.0.0-alpha.test',
  buildNumber: '42',
);

ClassicHareegMatchSnapshot _snapshot({
  required int seed,
  PlayerSeat currentSeat = PlayerSeat.south,
  TurnPhase turnPhase = TurnPhase.action,
  int roundNumber = 1,
  Map<PlayerSeat, int> scores = const {},
}) {
  final setup = ClassicHareegSetup.defaults();
  final round = ClassicHareegRound.deal(setup: setup, seed: seed);
  return ClassicHareegMatchSnapshot(
    setup: setup,
    hands: round.hands,
    seed: round.seed,
    stock: round.stock,
    discardPile: round.discardPile,
    starter: round.starter,
    currentSeat: currentSeat,
    turnPhase: turnPhase,
    scores: scores,
    roundNumber: roundNumber,
    savedAt: DateTime.utc(2026, 6, 9),
  );
}

Map<String, Object?> _completedReportJson({
  required List<Object?> activeSeats,
}) {
  const result = RoundProgressResult(
    type: RoundOutcomeType.normalFinish,
    winner: PlayerSeat.south,
    remainingCardCounts: {
      PlayerSeat.south: 0,
      PlayerSeat.east: 4,
      PlayerSeat.north: 7,
      PlayerSeat.west: 9,
    },
  );
  const progress = MatchProgressState(
    scores: {
      PlayerSeat.south: -3,
      PlayerSeat.east: 31,
      PlayerSeat.north: 18,
      PlayerSeat.west: 24,
    },
    activeSeats: [PlayerSeat.south],
    nextStarter: PlayerSeat.south,
    matchWinner: PlayerSeat.south,
  );
  final report = ClassicHareegMatchReport.completed(
    app: _app,
    platform: 'android',
    generatedAt: DateTime.utc(2026, 6, 9, 15),
    snapshot: _snapshot(seed: 47),
    roundResult: result,
    matchProgress: progress,
  );
  final json = report.toJson();
  final matchProgress = json['matchProgress']! as Map<String, Object?>;
  matchProgress['activeSeats'] = activeSeats;
  return json;
}
