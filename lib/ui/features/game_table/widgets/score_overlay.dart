import 'package:flutter/material.dart';

import '../../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/theme/lounge_tokens.dart';

/// Modal-style score overlay shown above the table when the score button is
/// tapped. Blocks table interaction while open.
class ScoreOverlay extends StatelessWidget {
  /// Creates the score overlay.
  const ScoreOverlay({
    super.key,
    required this.scores,
    required this.activeSeats,
    required this.starter,
    required this.currentSeat,
    required this.roundNumber,
    required this.onClose,
  });

  /// Per-seat match scores.
  final Map<PlayerSeat, int> scores;

  /// Seats still active in the match.
  final List<PlayerSeat> activeSeats;

  /// The round's starter seat.
  final PlayerSeat starter;

  /// Whose turn it currently is.
  final PlayerSeat currentSeat;

  /// One-based round number.
  final int roundNumber;

  /// Dismiss handler.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final seats = scores.keys.toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    return _OverlayShell(
      title: AppStrings.scoresTitle,
      onClose: onClose,
      footer: Wrap(
        spacing: LoungeTokens.space2,
        children: [
          _Pill(label: 'Round', value: '$roundNumber'),
          _Pill(label: 'Starter', value: _seatLabel(starter)),
          _Pill(label: 'Turn', value: _seatLabel(currentSeat)),
        ],
      ),
      child: Column(
        children: [
          for (final seat in seats)
            _ScoreRow(
              seat: seat,
              score: scores[seat] ?? 0,
              eliminated: !activeSeats.contains(seat),
            ),
        ],
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({
    required this.seat,
    required this.score,
    required this.eliminated,
  });

  final PlayerSeat seat;
  final int score;
  final bool eliminated;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            seat == PlayerSeat.south ? Icons.person : Icons.smart_toy,
            size: 18,
            color: eliminated
                ? LoungeTokens.mutedText
                : LoungeTokens.offWhiteText,
          ),
          const SizedBox(width: LoungeTokens.space2),
          Expanded(
            child: Text(
              _seatLabel(seat),
              style: TextStyle(
                color: eliminated
                    ? LoungeTokens.mutedText
                    : LoungeTokens.offWhiteText,
                fontWeight: FontWeight.w700,
                decoration: eliminated ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          Text(
            '$score',
            style: LoungeTokens.numericChip.copyWith(
              color: eliminated
                  ? LoungeTokens.mutedText
                  : LoungeTokens.goldAccent,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _OverlayShell extends StatelessWidget {
  const _OverlayShell({
    required this.title,
    required this.child,
    required this.onClose,
    this.footer,
  });

  final String title;
  final Widget child;
  final Widget? footer;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onClose,
      child: ColoredBox(
        color: LoungeTokens.overlayScrim,
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Material(
                color: LoungeTokens.coffeeCharcoal,
                borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(LoungeTokens.space5),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(title, style: LoungeTokens.heading),
                          ),
                          IconButton(
                            onPressed: onClose,
                            icon: const Icon(Icons.close),
                            tooltip: 'Close',
                          ),
                        ],
                      ),
                      const SizedBox(height: LoungeTokens.space2),
                      child,
                      if (footer != null) ...[
                        const SizedBox(height: LoungeTokens.space3),
                        footer!,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LoungeTokens.space3,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: LoungeTokens.feltRaised,
        borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
        border: Border.all(
          color: LoungeTokens.sandLine.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label ', style: LoungeTokens.bodyMuted),
          Text(value, style: LoungeTokens.numericChip),
        ],
      ),
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
