import 'package:flutter/material.dart';

import '../../../../domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import '../../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../../domain/classic_hareeg/rules/match_progression_rules.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/motif/geometric_motif_painter.dart';
import '../../../core/theme/lounge_tokens.dart';

/// Route arguments for [RoundSummaryScreen].
class RoundSummaryArguments {
  /// Creates round summary route arguments.
  const RoundSummaryArguments({
    required this.result,
    required this.progress,
    required this.previousScores,
    this.nextSnapshot,
  });

  /// Round outcome being summarized.
  final RoundProgressResult result;

  /// Match progress state after applying the round outcome.
  final MatchProgressState progress;

  /// Scores before this round.
  final Map<PlayerSeat, int> previousScores;

  /// Dealt next round to resume when the match is not over.
  final ClassicHareegMatchSnapshot? nextSnapshot;
}

/// Player-facing round or match summary.
class RoundSummaryScreen extends StatelessWidget {
  /// Creates a round summary screen.
  const RoundSummaryScreen({
    required this.result,
    required this.progress,
    required this.previousScores,
    this.onContinue,
    this.onReturnToMenu,
    super.key,
  });

  /// Round result being summarized.
  final RoundProgressResult result;

  /// Progress state after applying the round result.
  final MatchProgressState progress;

  /// Scores before this round.
  final Map<PlayerSeat, int> previousScores;

  /// Continue action for the next round.
  final VoidCallback? onContinue;

  /// Return-to-menu action.
  final VoidCallback? onReturnToMenu;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final winner = progress.matchWinner;
    final scoreSeats = previousScores.keys.toList()
      ..sort((left, right) => left.index.compareTo(right.index));

    return Scaffold(
      backgroundColor: LoungeTokens.feltGreen,
      appBar: AppBar(title: Text(strings.roundSummary)),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const _SummaryBackdrop(),
            ListView(
              padding: const EdgeInsets.fromLTRB(
                LoungeTokens.space5,
                LoungeTokens.space5,
                LoungeTokens.space5,
                LoungeTokens.space8,
              ),
              children: [
                _SummaryIntro(
                  headline: _headline(strings),
                  details: _details(strings),
                ),
                const _SectionBreak(),
                _ScoreSection(
                  scoreSeats: scoreSeats,
                  previousScores: previousScores,
                  progress: progress,
                ),
                const _SectionBreak(),
                _NextStepLine(
                  winner: winner,
                  nextStarter: progress.nextStarter,
                ),
                const SizedBox(height: LoungeTokens.space6),
                if (winner == null)
                  FilledButton.icon(
                    onPressed: onContinue,
                    icon: const Icon(Icons.skip_next),
                    label: Text(strings.continueNextRound),
                  )
                else
                  FilledButton.icon(
                    onPressed: onReturnToMenu,
                    icon: const Icon(Icons.home_outlined),
                    label: Text(strings.returnToMenu),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _headline(AppStrings strings) {
    return switch (result.type) {
      RoundOutcomeType.normalFinish => strings.playerFinished(result.winner!),
      RoundOutcomeType.fiftyFinish => strings.playerHitFifty(result.winner!),
      RoundOutcomeType.draw => strings.roundDrawn,
    };
  }

  String _details(AppStrings strings) {
    return switch (result.type) {
      RoundOutcomeType.normalFinish => strings.roundSummaryDetailNormal(),
      RoundOutcomeType.fiftyFinish => strings.roundSummaryDetailFifty(
        firstRoundException: result.firstRoundFiftyException,
      ),
      RoundOutcomeType.draw => strings.roundSummaryDetailDraw(),
    };
  }
}

class _SummaryBackdrop extends StatelessWidget {
  const _SummaryBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -42,
          right: -54,
          child: LoungeMotif(
            variant: LoungeMotifVariant.medallion,
            opacity: 0.052,
            strokeWidth: 1.0,
            density: 4,
            size: const Size.square(220),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 18,
          child: SizedBox(
            height: 30,
            child: CustomPaint(
              painter: const GeometricMotifPainter(
                variant: LoungeMotifVariant.border,
                opacity: 0.08,
                strokeWidth: 1.0,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryIntro extends StatelessWidget {
  const _SummaryIntro({required this.headline, required this.details});

  final String headline;
  final String details;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox.square(
          dimension: 50,
          child: CustomPaint(
            painter: GeometricMotifPainter(
              variant: LoungeMotifVariant.medallion,
              opacity: 0.38,
              strokeWidth: 1.0,
              density: 3,
            ),
          ),
        ),
        const SizedBox(width: LoungeTokens.space4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(headline, style: LoungeTokens.display),
              const SizedBox(height: LoungeTokens.space2),
              Text(details, style: LoungeTokens.bodyMuted),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScoreSection extends StatelessWidget {
  const _ScoreSection({
    required this.scoreSeats,
    required this.previousScores,
    required this.progress,
  });

  final List<PlayerSeat> scoreSeats;
  final Map<PlayerSeat, int> previousScores;
  final MatchProgressState progress;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.scoreboard_outlined,
              color: LoungeTokens.goldAccent,
            ),
            const SizedBox(width: LoungeTokens.space2),
            Expanded(child: Text(strings.scores, style: LoungeTokens.heading)),
          ],
        ),
        const SizedBox(height: LoungeTokens.space4),
        for (var i = 0; i < scoreSeats.length; i++) ...[
          _ScoreLine(
            seat: scoreSeats[i],
            before: previousScores[scoreSeats[i]] ?? 0,
            after: progress.scores[scoreSeats[i]] ?? 0,
            eliminated: !progress.activeSeats.contains(scoreSeats[i]),
          ),
          if (i < scoreSeats.length - 1) const _ThinDivider(),
        ],
      ],
    );
  }
}

class _ScoreLine extends StatelessWidget {
  const _ScoreLine({
    required this.seat,
    required this.before,
    required this.after,
    required this.eliminated,
  });

  final PlayerSeat seat;
  final int before;
  final int after;
  final bool eliminated;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final delta = after - before;
    final deltaText = delta >= 0 ? '+$delta' : '$delta';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LoungeTokens.space2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings.seatLabel(seat), style: LoungeTokens.titleSmall),
                if (eliminated)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      strings.eliminated,
                      style: LoungeTokens.bodyMuted,
                    ),
                  ),
              ],
            ),
          ),
          Text('$before -> $after', style: LoungeTokens.numericChip),
          const SizedBox(width: LoungeTokens.space3),
          Text(deltaText, style: LoungeTokens.bodyMuted),
        ],
      ),
    );
  }
}

class _NextStepLine extends StatelessWidget {
  const _NextStepLine({required this.winner, required this.nextStarter});

  final PlayerSeat? winner;
  final PlayerSeat nextStarter;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final hasWinner = winner != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          hasWinner ? Icons.emoji_events_outlined : Icons.flag_outlined,
          color: LoungeTokens.goldAccent,
        ),
        const SizedBox(width: LoungeTokens.space3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasWinner ? strings.matchWinner : strings.nextStarter,
                style: LoungeTokens.heading,
              ),
              const SizedBox(height: LoungeTokens.space2),
              Text(
                strings.seatLabel(hasWinner ? winner! : nextStarter),
                style: LoungeTokens.body,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionBreak extends StatelessWidget {
  const _SectionBreak();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LoungeTokens.space5),
      child: Divider(
        height: 1,
        color: LoungeTokens.sandLine.withValues(alpha: 0.24),
      ),
    );
  }
}

class _ThinDivider extends StatelessWidget {
  const _ThinDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: LoungeTokens.space4,
      color: LoungeTokens.sandLine.withValues(alpha: 0.14),
    );
  }
}
