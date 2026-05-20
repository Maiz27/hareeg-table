import 'package:flutter/material.dart';

import '../../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/motif/geometric_motif_painter.dart';
import '../../../core/theme/lounge_tokens.dart';

/// Modal-style score overlay shown above the table when the score button is
/// tapped. Visually matches the home menu's coffee-charcoal + sand-line
/// panel language so the table chrome reads as one product.
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

    return GestureDetector(
      onTap: onClose,
      child: ColoredBox(
        color: LoungeTokens.overlayScrim,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxHeight =
                  (constraints.maxHeight - LoungeTokens.space5).clamp(
                    160.0,
                    constraints.maxHeight,
                  );
              return Center(
                child: GestureDetector(
                  onTap: () {},
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LoungeTokens.space4,
                      vertical: LoungeTokens.space3,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 480,
                        maxHeight: maxHeight,
                      ),
                      child: _LoungePanel(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _PanelHeader(
                              icon: Icons.emoji_events_outlined,
                              title: AppStrings.scoresTitle,
                              subtitle:
                                  'Round $roundNumber, ${_seatLabel(currentSeat).toLowerCase()} to play',
                              onClose: onClose,
                            ),
                            const SizedBox(height: LoungeTokens.space4),
                            // The seat list scrolls when the panel is shorter
                            // than the content (compact landscape). The
                            // header and legend stay pinned so the round
                            // context is never hidden.
                            Flexible(
                              fit: FlexFit.loose,
                              child: SingleChildScrollView(
                                child: _ScoreList(
                                  seats: seats,
                                  scores: scores,
                                  activeSeats: activeSeats,
                                  starter: starter,
                                  currentSeat: currentSeat,
                                ),
                              ),
                            ),
                            const SizedBox(height: LoungeTokens.space3),
                            _LegendRow(
                              starterLabel: _seatLabel(starter),
                              currentLabel: _seatLabel(currentSeat),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ScoreList extends StatelessWidget {
  const _ScoreList({
    required this.seats,
    required this.scores,
    required this.activeSeats,
    required this.starter,
    required this.currentSeat,
  });

  final List<PlayerSeat> seats;
  final Map<PlayerSeat, int> scores;
  final List<PlayerSeat> activeSeats;
  final PlayerSeat starter;
  final PlayerSeat currentSeat;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: LoungeTokens.feltGreen.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
        border: Border.all(
          color: LoungeTokens.sandLine.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          for (var i = 0; i < seats.length; i++) ...[
            _ScoreRow(
              seat: seats[i],
              score: scores[seats[i]] ?? 0,
              eliminated: !activeSeats.contains(seats[i]),
              isStarter: seats[i] == starter,
              isCurrent: seats[i] == currentSeat,
            ),
            if (i < seats.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                color: LoungeTokens.sandLine.withValues(alpha: 0.16),
                indent: LoungeTokens.space4,
                endIndent: LoungeTokens.space4,
              ),
          ],
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
    required this.isStarter,
    required this.isCurrent,
  });

  final PlayerSeat seat;
  final int score;
  final bool eliminated;
  final bool isStarter;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final nameColor = eliminated
        ? LoungeTokens.mutedText
        : LoungeTokens.offWhiteText;
    final scoreColor = eliminated
        ? LoungeTokens.mutedText
        : (isCurrent ? LoungeTokens.fiftyFlame : LoungeTokens.goldAccent);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LoungeTokens.space4,
        vertical: LoungeTokens.space2,
      ),
      decoration: BoxDecoration(
        color: isCurrent
            ? LoungeTokens.goldAccent.withValues(alpha: 0.08)
            : Colors.transparent,
      ),
      child: Row(
        children: [
          _SeatBadge(seat: seat, eliminated: eliminated, highlight: isCurrent),
          const SizedBox(width: LoungeTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _seatLabel(seat),
                  style: TextStyle(
                    color: nameColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    letterSpacing: 0.2,
                    decoration: eliminated ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (isStarter || isCurrent || eliminated) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (isCurrent)
                        const _StatusTag(
                          label: 'Turn',
                          color: LoungeTokens.fiftyFlame,
                        ),
                      if (isStarter)
                        const _StatusTag(
                          label: 'Starter',
                          color: LoungeTokens.goldAccent,
                        ),
                      if (eliminated)
                        const _StatusTag(
                          label: 'Out',
                          color: LoungeTokens.deepRed,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: LoungeTokens.space3),
          Text(
            '$score',
            style: TextStyle(
              color: scoreColor,
              fontWeight: FontWeight.w800,
              fontSize: 22,
              letterSpacing: 0.4,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _SeatBadge extends StatelessWidget {
  const _SeatBadge({
    required this.seat,
    required this.eliminated,
    required this.highlight,
  });

  final PlayerSeat seat;
  final bool eliminated;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final iconColor = eliminated
        ? LoungeTokens.mutedText
        : (highlight ? LoungeTokens.fiftyFlame : LoungeTokens.offWhiteText);
    final borderColor = eliminated
        ? LoungeTokens.mutedText.withValues(alpha: 0.4)
        : (highlight
              ? LoungeTokens.fiftyFlame.withValues(alpha: 0.55)
              : LoungeTokens.sandLine.withValues(alpha: 0.4));
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: LoungeTokens.feltRaised,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: highlight ? 1.4 : 1.0),
      ),
      alignment: Alignment.center,
      child: Icon(
        seat == PlayerSeat.south ? Icons.person : Icons.smart_toy_outlined,
        size: 18,
        color: iconColor,
      ),
    );
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.starterLabel, required this.currentLabel});

  final String starterLabel;
  final String currentLabel;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: LoungeTokens.space2,
      runSpacing: LoungeTokens.space2,
      children: [
        _LegendPill(
          icon: Icons.flag_outlined,
          label: 'Started by $starterLabel',
        ),
        _LegendPill(
          icon: Icons.local_fire_department_outlined,
          label: 'On the table: $currentLabel',
        ),
      ],
    );
  }
}

class _LegendPill extends StatelessWidget {
  const _LegendPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LoungeTokens.space3,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: LoungeTokens.sandLine.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: LoungeTokens.goldAccent),
          const SizedBox(width: 6),
          Text(label, style: LoungeTokens.bodyMuted),
        ],
      ),
    );
  }
}

class _LoungePanel extends StatelessWidget {
  const _LoungePanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
          border: Border.all(
            color: LoungeTokens.sandLine.withValues(alpha: 0.32),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 28,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
          child: Stack(
            children: [
              Positioned(
                top: -34,
                right: -42,
                child: IgnorePointer(
                  child: SizedBox.square(
                    dimension: 168,
                    child: CustomPaint(
                      painter: const GeometricMotifPainter(
                        variant: LoungeMotifVariant.medallion,
                        opacity: 0.05,
                        strokeWidth: 1.0,
                        density: 4,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  LoungeTokens.space5,
                  LoungeTokens.space4,
                  LoungeTokens.space5,
                  LoungeTokens.space4,
                ),
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: LoungeTokens.feltRaised,
            borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
            border: Border.all(
              color: LoungeTokens.sandLine.withValues(alpha: 0.4),
            ),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: LoungeTokens.goldAccent, size: 22),
        ),
        const SizedBox(width: LoungeTokens.space4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: LoungeTokens.display.copyWith(fontSize: 22)),
              const SizedBox(height: 4),
              Text(subtitle, style: LoungeTokens.bodyMuted),
            ],
          ),
        ),
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          color: LoungeTokens.mutedText,
        ),
      ],
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
