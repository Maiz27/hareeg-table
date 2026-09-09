import '../models/classic_hareeg_setup.dart';
import '../models/player_seat.dart';
import '../persistence/persistence_codec.dart';
import 'match_fifty_counters.dart';
import 'match_id.dart';

/// Schema version implemented by the history summary wire format.
const int matchHistorySummaryVersion = 1;

/// Lightweight facts about one completed match.
///
/// Everything history browsing and statistics need, with no replay payload —
/// listing a hundred matches must not read a hundred replay files.
class MatchHistorySummary {
  /// Creates a summary.
  MatchHistorySummary({
    required this.matchId,
    required DateTime completedAt,
    required this.setup,
    required Map<PlayerSeat, int> finalScores,
    required this.winner,
    required this.southPlacement,
    required this.roundCount,
    required this.coachWasEnabled,
    required this.fiftyCounters,
    required this.fiftyCountersComplete,
    required this.replayable,
  }) : completedAt = completedAt.toUtc(),
       finalScores = Map.unmodifiable(finalScores) {
    if (!isValidMatchId(matchId)) {
      throw ArgumentError.value(matchId, 'matchId', 'Invalid match id.');
    }
  }

  /// Restores a summary from JSON-compatible data.
  factory MatchHistorySummary.fromJson(Map<String, Object?> json) {
    final version = asJsonInt(json['version']);
    if (version != matchHistorySummaryVersion) {
      throw FormatException(
        'Unsupported history summary version $version; '
        'expected $matchHistorySummaryVersion.',
      );
    }

    final matchId = asJsonString(json['matchId']);
    final completedAtRaw = asJsonString(json['completedAt']);
    final setupJson = asJsonMap(json['setup']);
    final winner = PlayerSeat.fromName(asJsonString(json['winner']));
    final southPlacement = asJsonInt(json['southPlacement']);
    final roundCount = asJsonInt(json['roundCount']);
    final coachWasEnabled = asJsonBool(json['coachWasEnabled']);
    final countersJson = asJsonMap(json['fiftyCounters']);
    final countersComplete = asJsonBool(json['fiftyCountersComplete']);
    final replayable = asJsonBool(json['replayable']);

    if (matchId == null ||
        completedAtRaw == null ||
        setupJson == null ||
        winner == null ||
        southPlacement == null ||
        roundCount == null ||
        coachWasEnabled == null ||
        countersJson == null ||
        countersComplete == null ||
        replayable == null) {
      throw const FormatException('Invalid history summary.');
    }

    final completedAt = DateTime.tryParse(completedAtRaw);
    if (completedAt == null) {
      throw const FormatException('Invalid history summary timestamp.');
    }

    return MatchHistorySummary(
      matchId: matchId,
      completedAt: completedAt,
      setup: ClassicHareegSetup.fromJson(setupJson),
      finalScores: _decodeSeatInts(json['finalScores']),
      winner: winner,
      southPlacement: southPlacement,
      roundCount: roundCount,
      coachWasEnabled: coachWasEnabled,
      fiftyCounters: MatchFiftyCounters.fromJson(countersJson),
      fiftyCountersComplete: countersComplete,
      replayable: replayable,
    );
  }

  /// Stable match identity, and the replay record's storage key.
  final String matchId;

  /// When the match completed, in UTC.
  final DateTime completedAt;

  /// The setup the match was played with.
  final ClassicHareegSetup setup;

  /// Final score per seat.
  final Map<PlayerSeat, int> finalScores;

  /// The winning seat.
  final PlayerSeat winner;

  /// The human seat's one-based finish position.
  final int southPlacement;

  /// Rounds dealt during the match.
  final int roundCount;

  /// Whether coaching was available and enabled at any point in the match.
  ///
  /// Sticky: a match that had coaching on for one round and off for the rest
  /// still reports true, because the fact being recorded is "this player had
  /// help", not "this player has help right now".
  final bool coachWasEnabled;

  /// Per-seat Fifty attempts and successes.
  ///
  /// Only a measurement when [fiftyCountersComplete] is true.
  final MatchFiftyCounters fiftyCounters;

  /// Whether [fiftyCounters] was tracked for the whole match.
  ///
  /// False for a match migrated from a legacy save that predates counting. Its
  /// counters read as zero, and that zero means **unknown**, not measured-zero:
  /// no consumer may treat it as evidence the player never tried a Fifty.
  ///
  /// Deliberately independent of [replayable]. A match can lose its replay file
  /// long after completion and still have counters that were measured
  /// perfectly, so one flag cannot carry both meanings.
  final bool fiftyCountersComplete;

  /// Whether a replay record is available for this match.
  final bool replayable;

  /// Returns a copy with [replayable] set.
  MatchHistorySummary withReplayable(bool value) {
    return MatchHistorySummary(
      matchId: matchId,
      completedAt: completedAt,
      setup: setup,
      finalScores: finalScores,
      winner: winner,
      southPlacement: southPlacement,
      roundCount: roundCount,
      coachWasEnabled: coachWasEnabled,
      fiftyCounters: fiftyCounters,
      fiftyCountersComplete: fiftyCountersComplete,
      replayable: value,
    );
  }

  /// Converts the summary to JSON-compatible data.
  Map<String, Object?> toJson() => {
    'version': matchHistorySummaryVersion,
    'matchId': matchId,
    'completedAt': completedAt.toIso8601String(),
    'setup': setup.toJson(),
    'finalScores': {
      for (final entry in finalScores.entries) entry.key.name: entry.value,
    },
    'winner': winner.name,
    'southPlacement': southPlacement,
    'roundCount': roundCount,
    'coachWasEnabled': coachWasEnabled,
    'fiftyCounters': fiftyCounters.toJson(),
    'fiftyCountersComplete': fiftyCountersComplete,
    'replayable': replayable,
  };

  static Map<PlayerSeat, int> _decodeSeatInts(Object? raw) {
    final map = asJsonMap(raw);
    if (map == null) {
      throw const FormatException('Invalid history summary score map.');
    }

    final decoded = <PlayerSeat, int>{};
    for (final entry in map.entries) {
      final seat = PlayerSeat.fromName(entry.key);
      final value = asJsonInt(entry.value);
      if (seat == null || value == null) {
        throw FormatException('Invalid history summary score "${entry.key}".');
      }
      decoded[seat] = value;
    }
    return decoded;
  }
}
