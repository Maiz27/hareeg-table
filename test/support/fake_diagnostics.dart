import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/classic_hareeg_match_report.dart';
import 'package:hareeg_table/ui/features/match_reports/match_report_diagnostics.dart';

/// A DSN-shaped value; nothing in tests ever reaches the network with it
/// because every test gateway uses [FakeDiagnosticsTransport].
const testSentryDsn = 'https://public@o0.ingest.sentry.io/0';

/// In-memory stand-in for the Sentry transport. Records lifecycle and events.
class FakeDiagnosticsTransport implements DiagnosticsTransport {
  FakeDiagnosticsTransport({this.accept = true, this.throwOnSend = false});

  /// What [send] reports back.
  bool accept;

  /// Makes [send] throw, to prove the gateway never lets it escape.
  bool throwOnSend;

  int starts = 0;
  int stops = 0;
  DiagnosticsGate? gate;
  final List<DiagnosticsEvent> sent = [];

  bool get isRunning => starts > stops;

  @override
  Future<void> start(DiagnosticsGate gate) async {
    starts += 1;
    this.gate = gate;
  }

  @override
  Future<void> stop() async {
    stops += 1;
  }

  @override
  Future<bool> send(DiagnosticsEvent event) async {
    if (throwOnSend) {
      throw StateError('transport down');
    }
    sent.add(event);
    return accept;
  }
}

/// A gateway with a DSN and a fake transport, consent not yet applied.
MatchReportDiagnostics fakeDiagnostics(
  FakeDiagnosticsTransport transport, {
  String dsn = testSentryDsn,
  LiveMatchReportSource? liveMatch,
}) {
  return MatchReportDiagnostics(
    dsn: dsn,
    transport: transport,
    liveMatch: liveMatch ?? LiveMatchReportSource(),
  );
}

/// A small, valid active-match report.
ClassicHareegMatchReport sampleMatchReport({int seed = 19}) {
  final setup = ClassicHareegSetup.defaults();
  final round = ClassicHareegRound.deal(setup: setup, seed: seed);
  return ClassicHareegMatchReport.active(
    app: const MatchReportAppMetadata(
      appId: 'com.maiz27.hareegtable',
      appName: 'Hareeg Table',
      version: '1.0.0-alpha.test',
      buildNumber: '42',
    ),
    platform: 'test',
    generatedAt: DateTime.utc(2026, 6, 9),
    snapshot: ClassicHareegMatchSnapshot(
      setup: setup,
      hands: round.hands,
      seed: round.seed,
      stock: round.stock,
      discardPile: round.discardPile,
      starter: round.starter,
      currentSeat: round.currentSeat,
      turnPhase: round.turnPhase,
      savedAt: DateTime.utc(2026, 6, 9),
    ),
  );
}
