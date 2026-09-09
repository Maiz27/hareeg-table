import '../models/classic_hareeg_setup.dart';
import '../models/player_seat.dart';
import 'match_history_summary.dart';

/// Aggregated performance figures for the human seat over completed matches.
///
/// Every field is derived from [MatchHistorySummary] values alone. No replay
/// record is read, because listing a hundred matches must not read a hundred
/// replay files.
///
/// Counts are exact integers. Every rate and average is nullable, and a null
/// means **unavailable**, never zero: a rendered `0%` claims a measurement that
/// was never taken.
class MatchStatisticsMetrics {
  /// Creates a metrics value.
  const MatchStatisticsMetrics({
    required this.gamesPlayed,
    required this.wins,
    required this.winRate,
    required this.averagePlacement,
    required this.fiftyMeasuredMatches,
    required this.matchesWithFiftyAttempt,
    required this.fiftyAttempts,
    required this.fiftySuccesses,
    required this.fiftyAttemptRate,
    required this.fiftySuccessRate,
    required this.marginMatches,
    required this.averageScoringMargin,
  });

  /// Metrics over no matches at all.
  factory MatchStatisticsMetrics.empty() => const MatchStatisticsMetrics(
    gamesPlayed: 0,
    wins: 0,
    winRate: null,
    averagePlacement: null,
    fiftyMeasuredMatches: 0,
    matchesWithFiftyAttempt: 0,
    fiftyAttempts: 0,
    fiftySuccesses: 0,
    fiftyAttemptRate: null,
    fiftySuccessRate: null,
    marginMatches: 0,
    averageScoringMargin: null,
  );

  /// Computes metrics over [summaries].
  factory MatchStatisticsMetrics.fromSummaries(
    Iterable<MatchHistorySummary> summaries,
  ) {
    var gamesPlayed = 0;
    var wins = 0;
    var placementTotal = 0;
    var knownPlacements = 0;
    var fiftyMeasuredMatches = 0;
    var matchesWithFiftyAttempt = 0;
    var fiftyAttempts = 0;
    var fiftySuccesses = 0;
    var marginMatches = 0;
    var marginTotal = 0;

    for (final summary in summaries) {
      gamesPlayed++;
      if (summary.winner == PlayerSeat.south) {
        wins++;
      }
      if (summary.southPlacement > 0 &&
          summary.southPlacement <= summary.finalScores.length) {
        placementTotal += summary.southPlacement;
        knownPlacements++;
      }

      // Only a match tracked from its first dealt round contributes a Fifty
      // measurement. A migrated legacy match reports zero counters, and that
      // zero means unknown — counting it would report the player as measured
      // and found never to have tried.
      if (summary.fiftyCountersComplete) {
        fiftyMeasuredMatches++;
        final attempts = summary.fiftyCounters.attemptsFor(PlayerSeat.south);
        final successes = summary.fiftyCounters.successesFor(PlayerSeat.south);
        fiftyAttempts += attempts;
        fiftySuccesses += successes;
        if (attempts > 0) {
          matchesWithFiftyAttempt++;
        }
      }

      final margin = scoringMarginOf(summary);
      if (margin != null) {
        marginMatches++;
        marginTotal += margin;
      }
    }

    return MatchStatisticsMetrics(
      gamesPlayed: gamesPlayed,
      wins: wins,
      winRate: _ratio(wins, gamesPlayed),
      averagePlacement: _ratio(placementTotal, knownPlacements),
      fiftyMeasuredMatches: fiftyMeasuredMatches,
      matchesWithFiftyAttempt: matchesWithFiftyAttempt,
      fiftyAttempts: fiftyAttempts,
      fiftySuccesses: fiftySuccesses,
      fiftyAttemptRate: _ratio(matchesWithFiftyAttempt, fiftyMeasuredMatches),
      fiftySuccessRate: _ratio(fiftySuccesses, fiftyAttempts),
      marginMatches: marginMatches,
      averageScoringMargin: _ratio(marginTotal, marginMatches),
    );
  }

  /// Matches counted in this slice.
  final int gamesPlayed;

  /// Matches the human seat won.
  final int wins;

  /// [wins] over [gamesPlayed], or null when no match was played.
  final double? winRate;

  /// Mean known finishing placement, excluding unknown legacy rankings.
  /// Null when no placement was measured.
  final double? averagePlacement;

  /// Matches whose Fifty counters were actually measured.
  ///
  /// Differs from [gamesPlayed] whenever this slice holds a match migrated
  /// from a legacy save. Every Fifty figure below is over this denominator,
  /// which is why a surface showing them must disclose it when the two differ.
  final int fiftyMeasuredMatches;

  /// Measured matches in which the human seat attempted at least one Fifty.
  final int matchesWithFiftyAttempt;

  /// Total human-seat Fifty attempts across measured matches.
  final int fiftyAttempts;

  /// Total human-seat Fifty successes across measured matches.
  final int fiftySuccesses;

  /// [matchesWithFiftyAttempt] over [fiftyMeasuredMatches], or null when
  /// nothing was measured.
  final double? fiftyAttemptRate;

  /// [fiftySuccesses] over [fiftyAttempts], or null when there were no
  /// attempts to succeed at.
  final double? fiftySuccessRate;

  /// Matches that could produce a scoring margin.
  final int marginMatches;

  /// Mean scoring margin, or null when no match could produce one.
  ///
  /// Positive favours the human seat. See [scoringMarginOf].
  final double? averageScoringMargin;

  /// Whether this slice measured fewer Fifty matches than it played.
  ///
  /// The signal a surface uses to decide whether the Fifty denominator needs
  /// disclosing, computed per slice rather than read off the overall figures.
  bool get hasUnmeasuredFiftyMatches => fiftyMeasuredMatches != gamesPlayed;

  /// One match's scoring margin, or null when it has no opponent score.
  ///
  /// The best opponent's final score minus the human seat's, so a positive
  /// margin favours the human seat: a lower score is better in Classic Hareeg,
  /// which makes the *lowest* opponent score the strongest one to measure
  /// against.
  static int? scoringMarginOf(MatchHistorySummary summary) {
    final southScore = summary.finalScores[PlayerSeat.south];
    if (southScore == null) {
      return null;
    }

    int? bestOpponent;
    for (final entry in summary.finalScores.entries) {
      if (entry.key == PlayerSeat.south) {
        continue;
      }
      if (bestOpponent == null || entry.value < bestOpponent) {
        bestOpponent = entry.value;
      }
    }

    if (bestOpponent == null) {
      return null;
    }
    return bestOpponent - southScore;
  }

  static double? _ratio(int numerator, int denominator) {
    if (denominator == 0) {
      return null;
    }
    return numerator / denominator;
  }
}

/// Overall and grouped statistics over a set of completed matches.
///
/// The three groupings are independent facts about a match, not alternative
/// views of one. In particular table strictness does not stand in for whether
/// the coach was on: a player can run a Strict table with coaching enabled, or
/// a Coaching-tier table with the coach switched off.
class MatchStatisticsReport {
  /// Creates a report.
  const MatchStatisticsReport({
    required this.overall,
    required this.byCpuDifficulty,
    required this.byTableStrictness,
    required this.byCoachWasEnabled,
  });

  /// Computes a report over [summaries].
  factory MatchStatisticsReport.fromSummaries(
    Iterable<MatchHistorySummary> summaries,
  ) {
    final all = List<MatchHistorySummary>.of(summaries);

    return MatchStatisticsReport(
      overall: MatchStatisticsMetrics.fromSummaries(all),
      byCpuDifficulty: _group(
        all,
        CpuDifficulty.values,
        (summary) => summary.setup.cpuDifficulty,
      ),
      byTableStrictness: _group(
        all,
        TableStrictness.values,
        (summary) => summary.setup.tableStrictness,
      ),
      // Ordered false before true so the rendered comparison reads
      // "without coaching, then with" regardless of which match was archived
      // first.
      byCoachWasEnabled: _group(all, const [
        false,
        true,
      ], (summary) => summary.coachWasEnabled),
    );
  }

  /// Metrics over every match.
  final MatchStatisticsMetrics overall;

  /// Metrics per CPU difficulty, in declared enum order.
  final Map<CpuDifficulty, MatchStatisticsMetrics> byCpuDifficulty;

  /// Metrics per table strictness tier, in declared enum order.
  final Map<TableStrictness, MatchStatisticsMetrics> byTableStrictness;

  /// Metrics split by whether the coach was enabled, false first.
  final Map<bool, MatchStatisticsMetrics> byCoachWasEnabled;

  /// Whether there is nothing to report.
  bool get isEmpty => overall.gamesPlayed == 0;

  /// Groups in a fixed key order, omitting keys no match falls under.
  ///
  /// An absent group and a zero-filled one are not the same statement. A
  /// zero-filled Expert group would be indistinguishable from having played
  /// Expert and lost every time.
  static Map<K, MatchStatisticsMetrics> _group<K>(
    List<MatchHistorySummary> summaries,
    List<K> keyOrder,
    K Function(MatchHistorySummary) keyOf,
  ) {
    final buckets = <K, List<MatchHistorySummary>>{};
    for (final summary in summaries) {
      buckets.putIfAbsent(keyOf(summary), () => []).add(summary);
    }

    return {
      for (final key in keyOrder)
        if (buckets[key] != null)
          key: MatchStatisticsMetrics.fromSummaries(buckets[key]!),
    };
  }
}
