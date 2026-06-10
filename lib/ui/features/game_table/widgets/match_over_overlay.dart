import 'package:flutter/material.dart';

import '../../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../../domain/classic_hareeg/rules/match_progression_rules.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/theme/lounge_tokens.dart';

/// Dedicated, full-table landscape overlay shown when a match ends.
///
/// Kept deliberately separate from the round-score overlay: this is the
/// match-level summary surface (final standings + match actions) and is the
/// home for a richer post-match breakdown later (per-round history, the setup
/// recap). Living in the table means the match ends without leaving landscape —
/// no rotation, and the rematch restarts in place.
class MatchOverOverlay extends StatelessWidget {
  /// Creates the match-over overlay.
  const MatchOverOverlay({
    super.key,
    required this.result,
    required this.progress,
    required this.roundsPlayed,
    required this.eliminatedRound,
    required this.onRematch,
    required this.onReturnToMenu,
    required this.onExportReport,
    this.highContrast = false,
  });

  /// Final round result that ended the match.
  final RoundProgressResult result;

  /// Match progress after the final round (scores, winner, active seats).
  final MatchProgressState progress;

  /// One-based count of dealt rounds played in the match.
  final int roundsPlayed;

  /// Round in which each seat was eliminated, when known.
  final Map<PlayerSeat, int> eliminatedRound;

  /// Starts a new match with the same setup, in place.
  final VoidCallback onRematch;

  /// Returns to the main menu.
  final VoidCallback onReturnToMenu;

  /// Exports the completed match report.
  final VoidCallback onExportReport;

  /// Whether the high-contrast card profile is active.
  final bool highContrast;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final compact = MediaQuery.sizeOf(context).height < 390;
    final winner = progress.matchWinner;

    final rows = PlayerSeat.values.toList()
      ..sort((left, right) {
        final order = _scoreFor(left).compareTo(_scoreFor(right));
        if (order != 0) {
          return order;
        }
        if (left == winner) return -1;
        if (right == winner) return 1;
        return left.index.compareTo(right.index);
      });

    return GestureDetector(
      key: const ValueKey('match-over-overlay'),
      // Terminal surface: swallow background taps so the finished table behind
      // it can't be interacted with. The actions below are the only way out.
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: ColoredBox(
        color: Colors.black.withValues(alpha: highContrast ? 0.78 : 0.58),
        child: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 14 : 22,
              vertical: compact ? 10 : 18,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: compact ? 640 : 720,
                maxHeight: MediaQuery.sizeOf(context).height - 24,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: highContrast
                      ? Colors.black.withValues(alpha: 0.98)
                      : LoungeTokens.coffeeCharcoal.withValues(alpha: 0.97),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: highContrast
                        ? const Color(0xFFFFD400)
                        : LoungeTokens.goldAccent.withValues(alpha: 0.40),
                    width: highContrast ? 2 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.40),
                      blurRadius: 30,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Padding(
                  padding: EdgeInsets.all(compact ? 12 : 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Header(winner: winner, result: result, compact: compact),
                      SizedBox(height: compact ? 10 : 14),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _Standings(
                                rows: rows,
                                progress: progress,
                                winner: winner,
                                eliminatedRound: eliminatedRound,
                                compact: compact,
                              ),
                              SizedBox(height: compact ? 8 : 12),
                              Text(
                                strings.roundsPlayed(roundsPlayed),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: LoungeTokens.offWhiteText.withValues(
                                    alpha: 0.66,
                                  ),
                                  fontSize: compact ? 11 : 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: compact ? 12 : 16),
                      _Actions(
                        compact: compact,
                        onRematch: onRematch,
                        onReturnToMenu: onReturnToMenu,
                        onExportReport: onExportReport,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  int _scoreFor(PlayerSeat seat) => progress.scores[seat] ?? 0;
}

class _Header extends StatelessWidget {
  const _Header({
    required this.winner,
    required this.result,
    required this.compact,
  });

  final PlayerSeat? winner;
  final RoundProgressResult result;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final headline = winner == null
        ? strings.matchOver
        : strings.matchWinnerHeadline(winner!);
    final resultLine = switch (result.type) {
      RoundOutcomeType.fiftyFinish => strings.wonByFifty,
      RoundOutcomeType.normalFinish => strings.wonByFinish,
      RoundOutcomeType.draw => strings.roundDrawn,
    };
    return Row(
      children: [
        Icon(
          Icons.emoji_events_outlined,
          color: LoungeTokens.goldAccent,
          size: compact ? 22 : 26,
        ),
        SizedBox(width: compact ? 10 : 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                strings.matchOver.toUpperCase(),
                style: TextStyle(
                  color: LoungeTokens.goldAccent,
                  fontSize: compact ? 10 : 12,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                headline,
                style: TextStyle(
                  color: LoungeTokens.goldAccent,
                  fontSize: compact ? 20 : 26,
                  fontWeight: FontWeight.w900,
                  height: 1.02,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                resultLine,
                style: TextStyle(
                  color: LoungeTokens.offWhiteText.withValues(alpha: 0.74),
                  fontSize: compact ? 11 : 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Standings extends StatelessWidget {
  const _Standings({
    required this.rows,
    required this.progress,
    required this.winner,
    required this.eliminatedRound,
    required this.compact,
  });

  final List<PlayerSeat> rows;
  final MatchProgressState progress;
  final PlayerSeat? winner;
  final Map<PlayerSeat, int> eliminatedRound;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: LoungeTokens.feltGreen.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: LoungeTokens.sandLine.withValues(alpha: 0.20)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            _StandingRow(
              key: ValueKey('match-over-standing-${rows[i].name}'),
              rank: i + 1,
              seat: rows[i],
              score: progress.scores[rows[i]] ?? 0,
              isWinner: rows[i] == winner,
              isEliminated: !progress.activeSeats.contains(rows[i]),
              eliminatedRound: eliminatedRound[rows[i]],
              compact: compact,
            ),
            if (i < rows.length - 1)
              Divider(
                height: 1,
                color: LoungeTokens.sandLine.withValues(alpha: 0.14),
              ),
          ],
        ],
      ),
    );
  }
}

class _StandingRow extends StatelessWidget {
  const _StandingRow({
    required this.rank,
    required this.seat,
    required this.score,
    required this.isWinner,
    required this.isEliminated,
    required this.compact,
    this.eliminatedRound,
    super.key,
  });

  final int rank;
  final PlayerSeat seat;
  final int score;
  final bool isWinner;
  final bool isEliminated;
  final bool compact;
  final int? eliminatedRound;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final footnote = eliminatedRound == null
        ? strings.eliminated
        : strings.eliminatedInRound(eliminatedRound!);
    final accent = isWinner
        ? LoungeTokens.goldAccent
        : LoungeTokens.offWhiteText;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isWinner
            ? LoungeTokens.selectedGlow.withValues(alpha: 0.30)
            : Colors.transparent,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 7 : 9,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Text(
                '$rank.',
                style: TextStyle(
                  color: isWinner
                      ? LoungeTokens.goldAccent
                      : LoungeTokens.mutedText,
                  fontSize: compact ? 13 : 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Icon(
              isWinner ? Icons.emoji_events_outlined : Icons.person_outline,
              color: isWinner
                  ? LoungeTokens.goldAccent
                  : LoungeTokens.mutedText.withValues(alpha: 0.70),
              size: compact ? 16 : 19,
            ),
            SizedBox(width: compact ? 8 : 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    strings.seatLabel(seat),
                    style: TextStyle(
                      color: accent,
                      fontSize: compact ? 13 : 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (isEliminated && !isWinner)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        footnote,
                        style: TextStyle(
                          color: LoungeTokens.offWhiteText.withValues(
                            alpha: 0.60,
                          ),
                          fontSize: compact ? 10 : 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Text(
              score > 0 ? '+$score' : '$score',
              style: TextStyle(
                color: accent,
                fontSize: compact ? 14 : 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.compact,
    required this.onRematch,
    required this.onReturnToMenu,
    required this.onExportReport,
  });

  final bool compact;
  final VoidCallback onRematch;
  final VoidCallback onReturnToMenu;
  final VoidCallback onExportReport;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const ValueKey('match-over-overlay-menu'),
            onPressed: onReturnToMenu,
            icon: const Icon(Icons.home_outlined, size: 18),
            label: Text(strings.returnToMenu),
          ),
        ),
        SizedBox(width: compact ? 8 : 10),
        Expanded(
          child: OutlinedButton.icon(
            key: const ValueKey('match-over-overlay-export'),
            onPressed: onExportReport,
            icon: const Icon(Icons.file_upload_outlined, size: 18),
            label: Text(strings.exportMatchReport),
          ),
        ),
        SizedBox(width: compact ? 8 : 10),
        Expanded(
          child: FilledButton.icon(
            key: const ValueKey('match-over-overlay-rematch'),
            onPressed: onRematch,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(strings.newMatchSameSetup),
          ),
        ),
      ],
    );
  }
}
