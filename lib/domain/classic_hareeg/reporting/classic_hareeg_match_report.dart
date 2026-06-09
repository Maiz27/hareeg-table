import '../game/classic_hareeg_match_snapshot.dart';
import '../game/classic_hareeg_round.dart';
import '../models/classic_hareeg_setup.dart';
import '../models/player_seat.dart';
import '../persistence/persistence_codec.dart';
import '../rules/match_progression_rules.dart';
import 'classic_hareeg_match_report_v1.dart';
import 'match_action_transcript.dart';
import 'match_diagnostic_log.dart';

/// Lifecycle point captured by a match report.
enum MatchReportStage {
  /// Report exported while a match is still in progress.
  active,

  /// Report exported after the match-over flow is shown.
  completed;

  /// Parses a serialized stage name.
  static MatchReportStage? fromName(String? name) {
    if (name == null) {
      return null;
    }
    for (final stage in MatchReportStage.values) {
      if (stage.name == name) {
        return stage;
      }
    }
    return null;
  }
}

/// App/build metadata embedded in a match report.
class MatchReportAppMetadata {
  /// Creates report app metadata.
  const MatchReportAppMetadata({
    required this.appId,
    required this.appName,
    required this.version,
    required this.buildNumber,
  });

  /// Application/package identifier.
  final String appId;

  /// Human-readable application name.
  final String appName;

  /// Build version name.
  final String version;

  /// Build number/code when available.
  final String buildNumber;
}

/// Versioned diagnostic export for a Classic Hareeg match.
///
/// The report intentionally contains app/build metadata and structured match
/// state, but no preferences, locale, player names, or other user-entered data.
class ClassicHareegMatchReport {
  /// Creates a match report.
  const ClassicHareegMatchReport({
    required this.app,
    required this.platform,
    required this.generatedAt,
    required this.stage,
    required this.setup,
    required this.roundNumber,
    required this.currentSeat,
    required this.turnPhase,
    required this.scores,
    required this.snapshot,
    this.seed,
    this.roundResult,
    this.matchProgress,
    this.diagnostics,
    this.transcript,
  });

  /// Builds an active-match report from the current snapshot.
  factory ClassicHareegMatchReport.active({
    required MatchReportAppMetadata app,
    required String platform,
    required DateTime generatedAt,
    required ClassicHareegMatchSnapshot snapshot,
    MatchDiagnosticLog? diagnostics,
    MatchActionTranscript? transcript,
  }) {
    return ClassicHareegMatchReport(
      app: app,
      platform: platform,
      generatedAt: generatedAt,
      stage: MatchReportStage.active,
      setup: snapshot.setup,
      seed: snapshot.seed,
      roundNumber: snapshot.roundNumber,
      currentSeat: snapshot.currentSeat,
      turnPhase: snapshot.turnPhase,
      scores: snapshot.scores,
      snapshot: snapshot,
      diagnostics: diagnostics,
      transcript: transcript,
    );
  }

  /// Builds a completed-match report from the final match-over state.
  factory ClassicHareegMatchReport.completed({
    required MatchReportAppMetadata app,
    required String platform,
    required DateTime generatedAt,
    required ClassicHareegMatchSnapshot snapshot,
    required RoundProgressResult roundResult,
    required MatchProgressState matchProgress,
    MatchDiagnosticLog? diagnostics,
    MatchActionTranscript? transcript,
  }) {
    return ClassicHareegMatchReport(
      app: app,
      platform: platform,
      generatedAt: generatedAt,
      stage: MatchReportStage.completed,
      setup: snapshot.setup,
      seed: snapshot.seed,
      roundNumber: snapshot.roundNumber,
      currentSeat: snapshot.currentSeat,
      turnPhase: snapshot.turnPhase,
      scores: matchProgress.scores,
      snapshot: snapshot,
      roundResult: roundResult,
      matchProgress: matchProgress,
      diagnostics: diagnostics,
      transcript: transcript,
    );
  }

  /// Restores a report from JSON-compatible data.
  factory ClassicHareegMatchReport.fromJson(Map<String, Object?> json) {
    return decodeWithSchemaVersion<ClassicHareegMatchReport>(
      json,
      decoders: {matchReportV1Version: decodeMatchReportV1},
    );
  }

  /// App/build metadata.
  final MatchReportAppMetadata app;

  /// Platform that produced the report.
  final String platform;

  /// UTC timestamp when the report was generated.
  final DateTime generatedAt;

  /// Active or completed export stage.
  final MatchReportStage stage;

  /// Setup used by the reported match.
  final ClassicHareegSetup setup;

  /// Seed used to shuffle the reported round, when known.
  final int? seed;

  /// One-based dealt round number.
  final int roundNumber;

  /// Current/final active seat at the time of export.
  final PlayerSeat currentSeat;

  /// Current/final turn phase at the time of export.
  final TurnPhase turnPhase;

  /// Current/final scores by seat.
  final Map<PlayerSeat, int> scores;

  /// Current/final full match snapshot.
  final ClassicHareegMatchSnapshot snapshot;

  /// Final round result for completed reports.
  final RoundProgressResult? roundResult;

  /// Final match progress for completed reports.
  final MatchProgressState? matchProgress;

  /// Rolling, capped diagnostic event log, when captured.
  final MatchDiagnosticLog? diagnostics;

  /// Replayable domain-level action transcript, when captured.
  final MatchActionTranscript? transcript;

  /// Converts the report to the current JSON schema.
  Map<String, Object?> toJson() => encodeMatchReportV1(this);
}
