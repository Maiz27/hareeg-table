import 'package:flutter/material.dart';

import '../../../../app/app_orientation.dart';
import '../../../../app/app_routes.dart';
import '../../../../data/persistence/match_history_repository.dart';
import '../../../../domain/classic_hareeg/history/match_history_outcomes.dart';
import '../../../../domain/classic_hareeg/history/match_statistics.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../match_history_view_state.dart';
import '../match_statistics_format.dart';
import '../widgets/history_state_panels.dart';
import '../widgets/match_statistic_tile.dart';

/// Matches below which the figures are labelled as an early sample.
const int lowDataMatchThreshold = 3;

/// Aggregate performance over stored match summaries.
///
/// Every number comes from [MatchStatisticsReport], computed in the domain
/// layer over the same summaries the history browser lists. No replay record is
/// read, and no arithmetic happens in this file.
class MatchStatisticsScreen extends StatefulWidget {
  /// Creates the statistics surface.
  const MatchStatisticsScreen({required this.historyRepository, super.key});

  /// Completed-match storage.
  final MatchHistoryRepository historyRepository;

  @override
  State<MatchStatisticsScreen> createState() => _MatchStatisticsScreenState();
}

class _MatchStatisticsScreenState extends State<MatchStatisticsScreen> {
  MatchHistoryViewState _state = const MatchHistoryLoading();

  @override
  void initState() {
    super.initState();
    AppOrientation.usePortrait();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = const MatchHistoryLoading());

    MatchHistoryListOutcome outcome;
    try {
      outcome = await widget.historyRepository.listSummaries();
    } catch (error, stackTrace) {
      debugPrint('Failed to list summaries for statistics: $error');
      debugPrintStack(stackTrace: stackTrace);
      outcome = MatchHistoryListFailed(
        MatchHistoryFailure(
          kind: MatchHistoryFailureKind.retryable,
          message: 'History listing threw.',
          cause: error,
        ),
      );
    }

    if (!mounted) {
      return;
    }
    setState(() => _state = MatchHistoryViewState.fromOutcome(outcome));
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Scaffold(
      backgroundColor: LoungeTokens.feltGreen,
      appBar: AppBar(
        backgroundColor: LoungeTokens.coffeeCharcoal,
        foregroundColor: LoungeTokens.offWhiteText,
        title: Text(strings.statisticsTitle),
        actions: [
          IconButton(
            onPressed: () =>
                Navigator.of(context).pushReplacementNamed(AppRoutes.history),
            icon: const Icon(Icons.history),
            tooltip: strings.historyMenuLabel,
            color: LoungeTokens.sandLine,
          ),
        ],
      ),
      body: SafeArea(child: _body(strings)),
    );
  }

  Widget _body(AppStrings strings) {
    return switch (_state) {
      MatchHistoryLoading() => const Center(child: CircularProgressIndicator()),
      MatchHistoryEmpty() => HistoryEmptyPanel(
        icon: Icons.insights_outlined,
        title: strings.statisticsEmptyTitle,
        body: strings.statisticsEmptyBody,
      ),
      MatchHistoryFailed(:final failure) => HistoryFailurePanel(
        failure: failure,
        onRetry: _load,
      ),
      MatchHistoryLoaded(:final summaries) => _report(
        strings,
        MatchStatisticsReport.fromSummaries(summaries),
      ),
    };
  }

  Widget _report(AppStrings strings, MatchStatisticsReport report) {
    if (report.isEmpty) {
      return HistoryEmptyPanel(
        icon: Icons.insights_outlined,
        title: strings.statisticsEmptyTitle,
        body: strings.statisticsEmptyBody,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        LoungeTokens.space4,
        LoungeTokens.space4,
        LoungeTokens.space4,
        LoungeTokens.space6,
      ),
      children: [
        if (report.overall.gamesPlayed < lowDataMatchThreshold)
          HistoryLowDataNote(matches: report.overall.gamesPlayed),
        _StatisticsSlice(
          key: const ValueKey('stats-slice-overall'),
          heading: strings.statsOverallHeading,
          metrics: report.overall,
        ),
        _GroupSection(
          keyPrefix: 'difficulty',
          heading: strings.statsByDifficultyHeading,
          groups: {
            for (final entry in report.byCpuDifficulty.entries)
              strings.cpuDifficultyLabel(entry.key): entry.value,
          },
        ),
        _GroupSection(
          keyPrefix: 'strictness',
          heading: strings.statsByStrictnessHeading,
          groups: {
            for (final entry in report.byTableStrictness.entries)
              strings.tableStrictnessLabel(entry.key): entry.value,
          },
        ),
        _GroupSection(
          keyPrefix: 'coach',
          heading: strings.statsByCoachHeading,
          groups: {
            for (final entry in report.byCoachWasEnabled.entries)
              (entry.key
                      ? strings.statsCoachOnGroup
                      : strings.statsCoachOffGroup):
                  entry.value,
          },
        ),
      ],
    );
  }
}

class _GroupSection extends StatelessWidget {
  const _GroupSection({
    required this.keyPrefix,
    required this.heading,
    required this.groups,
  });

  final String keyPrefix;
  final String heading;
  final Map<String, MatchStatisticsMetrics> groups;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            top: LoungeTokens.space5,
            bottom: LoungeTokens.space1,
          ),
          child: Text(heading, style: _groupingHeading),
        ),
        for (final entry in groups.entries)
          _StatisticsSlice(
            // Keyed per slice so a test can scope its assertions to one
            // group's subtree rather than to the whole screen.
            key: ValueKey('stats-slice-$keyPrefix-${entry.key}'),
            heading: entry.key,
            metrics: entry.value,
            compactHeading: true,
          ),
      ],
    );
  }

  static const _groupingHeading = TextStyle(
    color: LoungeTokens.sandLine,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.0,
  );
}

/// One slice of the report: a heading, its tiles, and its own disclosures.
class _StatisticsSlice extends StatelessWidget {
  const _StatisticsSlice({
    required this.heading,
    required this.metrics,
    this.compactHeading = false,
    super.key,
  });

  final String heading;
  final MatchStatisticsMetrics metrics;
  final bool compactHeading;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Container(
      margin: const EdgeInsets.only(top: LoungeTokens.space3),
      padding: const EdgeInsets.all(LoungeTokens.space4),
      decoration: BoxDecoration(
        color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(LoungeTokens.radiusCard),
        border: Border.all(
          color: LoungeTokens.sandLine.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            heading,
            style: TextStyle(
              color: LoungeTokens.offWhiteText,
              fontSize: compactHeading ? 15 : 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: LoungeTokens.space3),
          LayoutBuilder(
            builder: (context, constraints) {
              // Two columns when there is room, one when there is not, so a
              // 320-wide portrait screen does not overflow.
              final columns = constraints.maxWidth >= 340 ? 2 : 1;
              final tileWidth =
                  (constraints.maxWidth - LoungeTokens.space2 * (columns - 1)) /
                  columns;

              return Wrap(
                spacing: LoungeTokens.space2,
                runSpacing: LoungeTokens.space2,
                children: [
                  for (final tile in _tiles(strings))
                    SizedBox(width: tileWidth, child: tile),
                ],
              );
            },
          ),
          // Slice-local: this group's own denominator, not the screen's.
          if (metrics.hasUnmeasuredFiftyMatches)
            HistoryFiftySampleNote(
              measured: metrics.fiftyMeasuredMatches,
              played: metrics.gamesPlayed,
            ),
        ],
      ),
    );
  }

  List<Widget> _tiles(AppStrings strings) {
    return [
      MatchStatisticTile(
        label: strings.statsGamesPlayed,
        value: MatchStatisticsFormat.count(metrics.gamesPlayed),
      ),
      MatchStatisticTile(
        label: strings.statsWinRate,
        value: MatchStatisticsFormat.percent(metrics.winRate),
      ),
      MatchStatisticTile(
        label: strings.statsAveragePlacement,
        value: MatchStatisticsFormat.average(metrics.averagePlacement),
      ),
      MatchStatisticTile(
        label: strings.statsFiftyAttemptRate,
        value: MatchStatisticsFormat.percent(metrics.fiftyAttemptRate),
      ),
      MatchStatisticTile(
        label: strings.statsFiftySuccessRate,
        value: MatchStatisticsFormat.percent(metrics.fiftySuccessRate),
      ),
      MatchStatisticTile(
        label: strings.statsAverageMargin,
        value: MatchStatisticsFormat.signedMargin(metrics.averageScoringMargin),
        // The sign is meaningless without stating which direction is good.
        hint: strings.statsMarginDirection,
      ),
    ];
  }
}
