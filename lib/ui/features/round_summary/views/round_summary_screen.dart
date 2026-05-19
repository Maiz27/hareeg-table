import 'package:flutter/material.dart';

import '../../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../../domain/classic_hareeg/rules/match_progression_rules.dart';

/// Route arguments for [RoundSummaryScreen].
class RoundSummaryArguments {
  /// Creates round summary route arguments.
  const RoundSummaryArguments({
    required this.result,
    required this.progress,
    required this.previousScores,
  });

  /// Round outcome being summarized.
  final RoundProgressResult result;

  /// Match progress state after applying the round outcome.
  final MatchProgressState progress;

  /// Scores before this round.
  final Map<PlayerSeat, int> previousScores;
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
    final winner = progress.matchWinner;

    return Scaffold(
      appBar: AppBar(title: const Text('Round summary')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(_headline, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(_details),
            const SizedBox(height: 20),
            for (final seat in previousScores.keys) ...[
              _ScoreLine(
                seat: seat,
                before: previousScores[seat] ?? 0,
                after: progress.scores[seat] ?? 0,
                eliminated: !progress.activeSeats.contains(seat),
              ),
              const Divider(height: 16),
            ],
            if (winner != null) ...[
              const SizedBox(height: 12),
              Text('Match winner: ${_seatLabel(winner)}'),
            ] else ...[
              const SizedBox(height: 12),
              Text('Next starter: ${_seatLabel(progress.nextStarter)}'),
            ],
            const SizedBox(height: 24),
            if (winner == null)
              FilledButton.icon(
                onPressed: onContinue,
                icon: const Icon(Icons.skip_next),
                label: const Text('Continue next round'),
              )
            else
              FilledButton.icon(
                onPressed: onReturnToMenu,
                icon: const Icon(Icons.home_outlined),
                label: const Text('Return to menu'),
              ),
          ],
        ),
      ),
    );
  }

  String get _headline {
    return switch (result.type) {
      RoundOutcomeType.normalFinish => '${_seatLabel(result.winner!)} finished',
      RoundOutcomeType.fiftyFinish => '${_seatLabel(result.winner!)} hit Fifty',
      RoundOutcomeType.draw => 'Round drawn',
    };
  }

  String get _details {
    return switch (result.type) {
      RoundOutcomeType.normalFinish =>
        'Winner scores -1. Other active players score their remaining card count.',
      RoundOutcomeType.fiftyFinish =>
        result.firstRoundFiftyException
            ? 'First-round Fifty exception: winner scores -1; discarder takes remaining cards plus 3.'
            : 'Fifty winner scores -3; discarder takes remaining cards plus 3.',
      RoundOutcomeType.draw =>
        'No score changes. The same starter deals again.',
    };
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
    final delta = after - before;
    final deltaText = delta >= 0 ? '+$delta' : '$delta';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(_seatLabel(seat)),
      subtitle: eliminated ? const Text('Eliminated') : null,
      trailing: Text('$before -> $after ($deltaText)'),
    );
  }
}

String _seatLabel(PlayerSeat seat) {
  return switch (seat) {
    PlayerSeat.south => 'You',
    PlayerSeat.east => 'CPU East',
    PlayerSeat.north => 'CPU North',
    PlayerSeat.west => 'CPU West',
  };
}
