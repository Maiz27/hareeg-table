import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_diagnostic_event.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_diagnostic_log.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_recorder.dart';

import '../../../scenario/classic_hareeg_match_driver.dart';
import '../../../scenario/classic_hareeg_scenario.dart';

void main() {
  group('MatchDiagnosticLog', () {
    test('assigns monotonic order and exposes events oldest-first', () {
      final log = MatchDiagnosticLog();
      final a = log.record(
        category: MatchDiagnosticCategory.rules,
        type: 'first',
        roundNumber: 1,
      );
      final b = log.record(
        category: MatchDiagnosticCategory.scoring,
        type: 'second',
        roundNumber: 1,
      );

      expect(a.order, 0);
      expect(b.order, 1);
      expect(log.events.map((e) => e.type), ['first', 'second']);
      expect(log.droppedCount, 0);
    });

    test('caps at capacity and counts dropped events', () {
      final log = MatchDiagnosticLog(capacity: 3);
      for (var i = 0; i < 5; i++) {
        log.record(
          category: MatchDiagnosticCategory.rules,
          type: 'e$i',
          roundNumber: 1,
        );
      }

      expect(log.events, hasLength(3));
      expect(log.events.map((e) => e.type), ['e2', 'e3', 'e4']);
      expect(log.events.map((e) => e.order), [2, 3, 4]);
      expect(log.droppedCount, 2);
    });

    test('round-trips through JSON preserving order and dropped count', () {
      final log = MatchDiagnosticLog(capacity: 2);
      for (var i = 0; i < 4; i++) {
        log.record(
          category: MatchDiagnosticCategory.fifty,
          type: 'event-$i',
          roundNumber: i + 1,
          seat: PlayerSeat.east,
          phase: TurnPhase.draw,
          data: {'k': i},
        );
      }

      final decoded = MatchDiagnosticLog.fromJson(log.toJson());

      expect(decoded.capacity, 2);
      expect(decoded.droppedCount, 2);
      expect(decoded.events.map((e) => e.type), ['event-2', 'event-3']);
      expect(decoded.events.first.order, 2);
      expect(decoded.events.first.seat, PlayerSeat.east);
      expect(decoded.events.first.phase, TurnPhase.draw);
      expect(decoded.events.first.data['k'], 2);
      // The next recorded event continues the order sequence.
      final next = decoded.record(
        category: MatchDiagnosticCategory.coach,
        type: 'after-restore',
        roundNumber: 9,
      );
      expect(next.order, 4);
    });

    test('omits empty payload, seat, and phase from JSON', () {
      final event = MatchDiagnosticEvent(
        order: 0,
        category: MatchDiagnosticCategory.finish,
        type: 'roundEnded',
        roundNumber: 2,
      );
      final json = event.toJson();
      expect(json.containsKey('seat'), isFalse);
      expect(json.containsKey('phase'), isFalse);
      expect(json.containsKey('data'), isFalse);
    });
  });

  group('MatchRecorder helpers', () {
    test('records coach hint triggers', () {
      final recorder = MatchRecorder();
      recorder.recordCoachHint(
        roundNumber: 3,
        hintId: 'drawStock',
        seat: PlayerSeat.south,
        phase: TurnPhase.action,
        data: {'count': 2},
      );

      final event = recorder.diagnostics.events.single;
      expect(event.category, MatchDiagnosticCategory.coach);
      expect(event.type, 'coachHint');
      expect(event.data['hintId'], 'drawStock');
      expect(event.data['count'], 2);
      expect(event.seat, PlayerSeat.south);
    });

    test('records persistence boundaries', () {
      final recorder = MatchRecorder();
      recorder.recordPersistence(
        type: 'resumed',
        roundNumber: 1,
        data: {'stage': 'restore'},
      );
      recorder.recordPersistence(type: 'saved', roundNumber: 1);

      final events = recorder.diagnostics.events;
      expect(events.map((e) => e.category),
          everyElement(MatchDiagnosticCategory.persistence));
      expect(events.map((e) => e.type), ['resumed', 'saved']);
      expect(events.first.data['stage'], 'restore');
    });
  });

  group('Controller-driven diagnostic capture', () {
    test('records an invalid action with rule context', () {
      final recorder = MatchRecorder();
      // A fresh deal starts in action phase with no pending discard, so
      // use-pending-discard is illegal and must surface as a rules event.
      final scenario = ClassicHareegScenario.deal(seed: 7, recorder: recorder);
      final result = scenario.controller.applyAction(
        ClassicHareegActionIds.usePendingDiscard,
      );

      expect(result.isSuccess, isFalse);
      final event = recorder.diagnostics.events.singleWhere(
        (e) => e.type == 'invalidAction',
      );
      expect(event.category, MatchDiagnosticCategory.rules);
      expect(event.data['actionId'], ClassicHareegActionIds.usePendingDiscard);
      expect(event.data['kind'], ClassicHareegActionKind.usePendingDiscard.name);
      expect((event.data['message'] as String?), isNotEmpty);
    });

    test('captures scoring, finish, and AI events across a full match', () {
      final captured = _driveEndedMatch();
      final events = captured.recorder.diagnostics.events;

      expect(
        events.any((e) => e.category == MatchDiagnosticCategory.finish),
        isTrue,
        reason: 'every completed round must record a finish event',
      );
      expect(
        events.any((e) => e.category == MatchDiagnosticCategory.scoring),
        isTrue,
        reason: 'round results fold scores, which must be recorded',
      );
      expect(
        events.any((e) => e.category == MatchDiagnosticCategory.ai),
        isTrue,
        reason: 'a CPU-decided round end must record an AI decision',
      );
      // Finish events carry the outcome type.
      final finish = events.firstWhere(
        (e) => e.category == MatchDiagnosticCategory.finish,
      );
      expect(finish.type, 'roundEnded');
      expect(finish.data['outcome'], isNotNull);
    });
  });
}

/// A driven match that ends naturally and exercises scoring/finish/AI events.
class _CapturedMatch {
  _CapturedMatch(this.recorder, this.report);
  final MatchRecorder recorder;
  final MatchRunReport report;
}

_CapturedMatch _driveEndedMatch() {
  final setup = ClassicHareegSetup.defaults().copyWith(
    cpuDifficulty: CpuDifficulty.expert,
    tableStrictness: TableStrictness.standard,
  );
  for (var seed = 1; seed <= 60; seed++) {
    final recorder = MatchRecorder();
    final report = ClassicHareegMatchDriver().run(
      setup: setup,
      seed: seed,
      recorder: recorder,
    );
    final events = recorder.diagnostics.events;
    if (report.endedNaturally &&
        events.any((e) => e.category == MatchDiagnosticCategory.scoring) &&
        events.any((e) => e.category == MatchDiagnosticCategory.ai)) {
      return _CapturedMatch(recorder, report);
    }
  }
  fail('No converging seed produced scoring + AI diagnostics in 60 tries.');
}
