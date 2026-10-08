import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_strategy.dart';
import 'package:hareeg_table/data/persistence/preferences_repository.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/classic_hareeg_match_report.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/features/game_table/table_session_config.dart';
import 'package:hareeg_table/ui/features/game_table/views/game_table_screen.dart';
import 'package:hareeg_table/ui/features/match_reports/match_report_diagnostics.dart';

import '../../../support/fake_diagnostics.dart';
import '../../../support/test_fixtures.dart';

/// The live table's side of HT-56: it registers its in-flight report for the
/// global handlers, auto-captures the match when play breaks, and sends a
/// player's "Report table issue" through diagnostics with Share/Copy demoted
/// to a fallback. Diagnostics run against [FakeDiagnosticsTransport]; nothing
/// touches the network.
void main() {
  final strings = AppStrings.english;

  Future<void> pumpTable(
    WidgetTester tester, {
    required MatchReportDiagnostics diagnostics,
    required LiveMatchReportSource live,
    ClassicHareegMatchSnapshot? snapshot,
    CpuStrategy cpuStrategy = const ClassicHareegCpuStrategy(),
  }) async {
    final resolved = snapshot ?? _snapshot();
    await tester.pumpWidget(
      MaterialApp(
        home: GameTableScreen(
          setup: resolved.setup,
          session: TableSessionConfig.live(
            matchRepository: MemoryMatchRepository(),
            historyRepository: MemoryMatchHistoryRepository(),
          ),
          preferences: GamePreferences.defaults(),
          onPreferencesChanged: (_) {},
          initialSnapshot: resolved,
          cpuStrategy: cpuStrategy,
          diagnostics: diagnostics,
          liveMatchReports: live,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 30));
  }

  Future<void> openReportSheet(WidgetTester tester) async {
    await tester.tap(find.byTooltip(strings.pauseTable));
    await tester.pumpAndSettle();
    await tester.tap(find.text(strings.reportTableIssue).first);
    await tester.pumpAndSettle();
  }

  testWidgets('a live table registers its in-flight report and clears it on '
      'leaving', (tester) async {
    final live = LiveMatchReportSource();
    await pumpTable(
      tester,
      diagnostics: fakeDiagnostics(FakeDiagnosticsTransport(), liveMatch: live),
      live: live,
    );

    final report = live.current();
    expect(report, isNotNull);
    expect(report!.stage, MatchReportStage.active);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(live.hasLiveMatch, isFalse);
  });

  testWidgets('Send report uploads a user_report with the match attached and '
      'confirms with a toast', (tester) async {
    final transport = FakeDiagnosticsTransport();
    final live = LiveMatchReportSource();
    final diagnostics = fakeDiagnostics(transport, liveMatch: live);
    await diagnostics.applyConsent(allowed: true);
    await pumpTable(tester, diagnostics: diagnostics, live: live);

    await openReportSheet(tester);
    // Send leads; Share/Copy stay as the offline fallback.
    expect(find.text(strings.sendReport), findsOneWidget);
    expect(find.text(strings.shareReport), findsOneWidget);
    expect(find.text(strings.copyReport), findsOneWidget);

    await tester.tap(find.text(strings.sendReport));
    await tester.pumpAndSettle();

    final event = transport.sent.single;
    expect(event.allTags['source'], 'user_report');
    final attached = ClassicHareegMatchReport.fromJson(
      _jsonMap(jsonDecode(event.attachment!.text)),
    );
    expect(attached.stage, MatchReportStage.active);
    expect(find.text(strings.matchReportSent), findsOneWidget);
    await _letToastExpire(tester);
  });

  testWidgets('a failed send offers the share fallback', (tester) async {
    final transport = FakeDiagnosticsTransport(accept: false);
    final live = LiveMatchReportSource();
    final diagnostics = fakeDiagnostics(transport, liveMatch: live);
    await diagnostics.applyConsent(allowed: true);
    await pumpTable(tester, diagnostics: diagnostics, live: live);

    await openReportSheet(tester);
    await tester.tap(find.text(strings.sendReport));
    await tester.pumpAndSettle();

    expect(find.text(strings.matchReportSendFailed), findsOneWidget);
    expect(find.text(strings.matchReportSent), findsNothing);
    await _letToastExpire(tester);
  });

  testWidgets('without a DSN the sheet explains and keeps Share/Copy', (
    tester,
  ) async {
    final transport = FakeDiagnosticsTransport();
    final live = LiveMatchReportSource();
    final diagnostics = fakeDiagnostics(transport, dsn: '', liveMatch: live);
    await diagnostics.applyConsent(allowed: true);
    await pumpTable(tester, diagnostics: diagnostics, live: live);

    await openReportSheet(tester);

    expect(find.text(strings.sendReport), findsNothing);
    expect(find.text(strings.matchReportSendUnavailable), findsOneWidget);
    expect(find.text(strings.shareReport), findsOneWidget);
    expect(find.text(strings.copyReport), findsOneWidget);
  });

  testWidgets('after an opt-out the sheet says reports are off and nothing '
      'can be sent', (tester) async {
    final transport = FakeDiagnosticsTransport();
    final live = LiveMatchReportSource();
    final diagnostics = fakeDiagnostics(transport, liveMatch: live);
    await diagnostics.applyConsent(allowed: false);
    await pumpTable(tester, diagnostics: diagnostics, live: live);

    await openReportSheet(tester);

    expect(find.text(strings.sendReport), findsNothing);
    expect(find.text(strings.matchReportSendDisabled), findsOneWidget);
    expect(transport.sent, isEmpty);
  });

  testWidgets('a CPU turn that throws is auto-captured with the replayable '
      'match report', (tester) async {
    final transport = FakeDiagnosticsTransport();
    final live = LiveMatchReportSource();
    final diagnostics = fakeDiagnostics(transport, liveMatch: live);
    await diagnostics.applyConsent(allowed: true);
    final dealt = _dealt();
    final cpuSeat = PlayerSeat.values.firstWhere(
      (seat) => seat != PlayerSeat.south && seat != dealt.starter,
    );

    await pumpTable(
      tester,
      diagnostics: diagnostics,
      live: live,
      snapshot: _snapshot(currentSeat: cpuSeat, turnPhase: TurnPhase.draw),
      cpuStrategy: const _ThrowingCpuStrategy(),
    );

    final event = transport.sent.single;
    expect(event.source, DiagnosticsSource.uncaughtError);
    expect(event.allTags['trigger'], 'cpu_turn_error');
    expect(event.error, isA<StateError>());
    final attached = ClassicHareegMatchReport.fromJson(
      _jsonMap(jsonDecode(event.attachment!.text)),
    );
    expect(attached.snapshot.currentSeat, cpuSeat);
  });

  testWidgets('with reports off, a CPU turn that throws sends nothing', (
    tester,
  ) async {
    final transport = FakeDiagnosticsTransport();
    final live = LiveMatchReportSource();
    final diagnostics = fakeDiagnostics(transport, liveMatch: live);
    await diagnostics.applyConsent(allowed: false);
    final dealt = _dealt();
    final cpuSeat = PlayerSeat.values.firstWhere(
      (seat) => seat != PlayerSeat.south && seat != dealt.starter,
    );

    await pumpTable(
      tester,
      diagnostics: diagnostics,
      live: live,
      snapshot: _snapshot(currentSeat: cpuSeat, turnPhase: TurnPhase.draw),
      cpuStrategy: const _ThrowingCpuStrategy(),
    );

    expect(transport.sent, isEmpty);
    expect(transport.starts, 0);
  });
}

/// Lets the lounge toast's dismiss timer run out so no timer outlives the test.
Future<void> _letToastExpire(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 10));
  await tester.pumpAndSettle();
}

final _setup = ClassicHareegSetup.defaults();

ClassicHareegRound _dealt() => ClassicHareegRound.deal(setup: _setup, seed: 3);

ClassicHareegMatchSnapshot _snapshot({
  PlayerSeat currentSeat = PlayerSeat.south,
  TurnPhase turnPhase = TurnPhase.action,
}) {
  final dealt = _dealt();
  return ClassicHareegMatchSnapshot(
    setup: _setup,
    hands: dealt.hands,
    stock: dealt.stock,
    discardPile: dealt.discardPile,
    starter: dealt.starter,
    currentSeat: currentSeat,
    turnPhase: turnPhase,
    activeSeats: const [
      PlayerSeat.south,
      PlayerSeat.east,
      PlayerSeat.north,
      PlayerSeat.west,
    ],
    savedAt: DateTime.utc(2026, 6, 1),
  );
}

class _ThrowingCpuStrategy implements CpuStrategy {
  const _ThrowingCpuStrategy();

  @override
  CpuMoveIntent chooseMove(
    CpuTurnSnapshot snapshot, {
    CpuObservation? observation,
  }) {
    throw StateError('strategy exploded');
  }
}

Map<String, Object?> _jsonMap(Object? value) {
  final map = value as Map<String, dynamic>;
  return {for (final entry in map.entries) entry.key: entry.value};
}
