import 'package:flutter/material.dart';

import '../../../../domain/classic_hareeg/history/match_history_summary.dart';
import '../../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/theme/lounge_tokens.dart';

/// One completed match, rendered from its summary alone.
///
/// Every fact here comes from [MatchHistorySummary]. No replay record is read
/// to draw a card, which is what lets a hundred-match history open without a
/// hundred file reads.
///
/// A replayable match offers a Replay action. One whose replay was lost keeps
/// the same honest chip and offers nothing, because an affordance that fails
/// when tapped teaches the player not to trust the list.
class MatchHistoryEntryCard extends StatelessWidget {
  /// Creates a history entry.
  const MatchHistoryEntryCard({
    required this.summary,
    required this.onDelete,
    this.onReplay,
    super.key,
  });

  /// The match to render.
  final MatchHistorySummary summary;

  /// Invoked when the player asks to delete this match.
  final VoidCallback onDelete;

  /// Invoked when the player asks to replay this match.
  ///
  /// Null for a match with no usable replay, which is what keeps the entry
  /// inert rather than merely disabled-looking.
  final VoidCallback? onReplay;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final setup = summary.setup;

    final won = summary.winner == PlayerSeat.south;
    final placement = summary.southPlacement;
    // A page from the match book: lit from the top-start corner, edged in
    // gold when the player won.
    return Container(
      margin: const EdgeInsets.only(bottom: LoungeTokens.space3),
      padding: const EdgeInsets.all(LoungeTokens.space4),
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.9, -1),
          radius: 1.6,
          colors: [
            Color.lerp(
              LoungeTokens.coffeeCharcoal,
              LoungeTokens.goldAccent,
              won ? 0.12 : 0.05,
            )!.withValues(alpha: 0.75),
            LoungeTokens.coffeeCharcoal.withValues(alpha: 0.5),
          ],
        ),
        borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
        border: Border.all(
          color: won
              ? LoungeTokens.goldAccent.withValues(alpha: 0.5)
              : LoungeTokens.sandLine.withValues(alpha: 0.18),
        ),
        boxShadow: LoungeTokens.elevationL2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PlacementMedallion(placement: placement, won: won),
              const SizedBox(width: LoungeTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(strings.historyOutcomeHeading, style: _sectionLabel),
                    const SizedBox(height: LoungeTokens.space1),
                    Text(
                      '${strings.historyWinnerLabel}: '
                      '${strings.seatLabel(summary.winner)}',
                      style: LoungeTokens.display.copyWith(
                        color: won
                            ? LoungeTokens.goldAccent
                            : LoungeTokens.offWhiteText,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: strings.historyDeleteTooltip,
                color: LoungeTokens.mutedText,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: LoungeTokens.space2),
          _FactRow(
            facts: [
              '${strings.historyPlacementLabel}: '
                  '${summary.southPlacement > 0 ? strings.historyPlacementValue(summary.southPlacement, summary.finalScores.length) : strings.historyPlacementUnknown}',
              strings.historyRoundsValue(summary.roundCount),
            ],
          ),
          const SizedBox(height: LoungeTokens.space2),
          _ScoreLine(summary: summary),
          const SizedBox(height: LoungeTokens.space3),
          Text(strings.historySetupHeading, style: _sectionLabel),
          const SizedBox(height: LoungeTokens.space1),
          _FactRow(
            facts: [
              strings.cpuDifficultyLabel(setup.cpuDifficulty),
              strings.tableStrictnessLabel(setup.tableStrictness),
              strings.decksValue(setup.deckCount),
              strings.historyJokersValue(setup.jokerCount),
              strings.historyOpeningValue(setup.openingRequirement),
              strings.fiftySecondsValue(setup.fiftyTimerSeconds),
              strings.starterModeLabel(setup.starterMode),
            ],
          ),
          const SizedBox(height: LoungeTokens.space3),
          Wrap(
            spacing: LoungeTokens.space2,
            runSpacing: LoungeTokens.space2,
            children: [
              // Availability is stated either way. A replayable match that
              // silently showed nothing would be indistinguishable from one
              // whose replay was lost.
              // Availability is stated either way, and stated separately from
              // the action. A match whose replay was lost must not merely lack
              // a button — silence there is indistinguishable from a bug.
              _StatusChip(
                icon: summary.replayable
                    ? Icons.movie_outlined
                    : Icons.movie_filter_outlined,
                label: summary.replayable
                    ? strings.historyReplayAvailable
                    : strings.historyReplayUnavailable,
                muted: !summary.replayable,
              ),
              if (summary.replayable && onReplay != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: LoungeTokens.tapTargetCardShort,
                  ),
                  child: TextButton.icon(
                    onPressed: onReplay,
                    icon: const Icon(Icons.movie_outlined, size: 16),
                    label: Text(strings.replayTitle),
                  ),
                ),
              _StatusChip(
                icon: summary.coachWasEnabled
                    ? Icons.lightbulb
                    : Icons.lightbulb_outline,
                label: summary.coachWasEnabled
                    ? strings.historyCoachOn
                    : strings.historyCoachOff,
                muted: !summary.coachWasEnabled,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static const _sectionLabel = TextStyle(
    color: LoungeTokens.mutedText,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.9,
  );
}

class _ScoreLine extends StatelessWidget {
  const _ScoreLine({required this.summary});

  final MatchHistorySummary summary;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    // Declared seat order, so two matches never list their scores differently.
    final seats = [
      for (final seat in PlayerSeat.values)
        if (summary.finalScores.containsKey(seat)) seat,
    ];

    return _FactRow(
      facts: [
        for (final seat in seats)
          strings.historySeatScore(seat, summary.finalScores[seat]!),
      ],
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.facts});

  final List<String> facts;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: LoungeTokens.space3,
      runSpacing: LoungeTokens.space1,
      children: [
        for (final fact in facts)
          Text(fact, style: LoungeTokens.bodyMuted.copyWith(fontSize: 12.5)),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.muted,
  });

  final IconData icon;
  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final color = muted ? LoungeTokens.mutedText : LoungeTokens.sandLine;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LoungeTokens.space2,
        vertical: LoungeTokens.space1,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(LoungeTokens.radiusCard),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: LoungeTokens.space1),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// The player's finishing place on a lacquered medallion: gold for a win,
/// a trophy in place of the 1.
class _PlacementMedallion extends StatelessWidget {
  const _PlacementMedallion({required this.placement, required this.won});

  final int placement;
  final bool won;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: won
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE8B95A), LoungeTokens.goldAccent],
              )
            : const RadialGradient(
                center: Alignment(-0.3, -0.45),
                colors: [Color(0xFF3A2A1C), LoungeTokens.coffeeCharcoal],
              ),
        border: Border.all(
          color: won
              ? LoungeTokens.goldAccent
              : LoungeTokens.sandLine.withValues(alpha: 0.4),
        ),
        boxShadow: [
          if (won)
            BoxShadow(
              color: LoungeTokens.goldAccent.withValues(alpha: 0.35),
              blurRadius: 12,
            ),
        ],
      ),
      child: won
          ? const Icon(
              Icons.emoji_events_outlined,
              size: 22,
              color: LoungeTokens.coffeeCharcoal,
            )
          : Text(
              placement > 0 ? '$placement' : '–',
              style: LoungeTokens.numericDisplay.copyWith(
                fontSize: 18,
                color: LoungeTokens.sandLine,
              ),
            ),
    );
  }
}
