import 'package:flutter/material.dart';

import '../../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/cards/card_theme.dart';
import '../../../core/panels/lounge_panel.dart';
import '../../../core/theme/lounge_tokens.dart';
import 'seat_plate.dart';

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
    this.eliminationScore = 31,
  });

  /// Score at which a seat is out of the match; the heat bars run to it.
  final int eliminationScore;

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
    final strings = context.strings;
    final highContrast = CardContrastScope.enabledOf(context);
    final seats = scores.keys.toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onClose,
      child: ColoredBox(
        color: highContrast
            ? Colors.black.withValues(alpha: 0.72)
            : LoungeTokens.overlayScrim,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxHeight = (constraints.maxHeight - LoungeTokens.space5)
                  .clamp(160.0, constraints.maxHeight);
              return Center(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
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
                      child: LoungePanel(
                        highContrast: highContrast,
                        padding: const EdgeInsets.fromLTRB(
                          LoungeTokens.space5,
                          LoungeTokens.space4,
                          LoungeTokens.space5,
                          LoungeTokens.space4,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            LoungePanelHeader(
                              icon: Icons.emoji_events_outlined,
                              title: strings.scoresTitle,
                              subtitle: strings.roundToPlay(
                                roundNumber,
                                currentSeat,
                              ),
                              onClose: onClose,
                              closeTooltip: strings.close,
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
                                  eliminationScore: eliminationScore,
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
                              starter: starter,
                              currentSeat: currentSeat,
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
    required this.eliminationScore,
    required this.seats,
    required this.scores,
    required this.activeSeats,
    required this.starter,
    required this.currentSeat,
  });

  final int eliminationScore;
  final List<PlayerSeat> seats;
  final Map<PlayerSeat, int> scores;
  final List<PlayerSeat> activeSeats;
  final PlayerSeat starter;
  final PlayerSeat currentSeat;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            LoungeTokens.feltSpotlight.withValues(alpha: 0.6),
            LoungeTokens.feltGreen.withValues(alpha: 0.5),
          ],
        ),
        borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
        border: Border.all(color: LoungeTokens.sandLine.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < seats.length; i++) ...[
            _ScoreRow(
              eliminationScore: eliminationScore,
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
    required this.eliminationScore,
    required this.seat,
    required this.score,
    required this.eliminated,
    required this.isStarter,
    required this.isCurrent,
  });

  final int eliminationScore;
  final PlayerSeat seat;
  final int score;
  final bool eliminated;
  final bool isStarter;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final nameColor = eliminated
        ? LoungeTokens.mutedText
        : LoungeTokens.offWhiteText;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LoungeTokens.space4,
        vertical: LoungeTokens.space2,
      ),
      decoration: BoxDecoration(
        gradient: isCurrent
            ? LinearGradient(
                colors: [
                  LoungeTokens.goldAccent.withValues(alpha: 0.14),
                  LoungeTokens.goldAccent.withValues(alpha: 0.0),
                ],
              )
            : null,
      ),
      child: Opacity(
        opacity: eliminated ? 0.55 : 1,
        child: Row(
          children: [
            ScoreMedallion(
              diameter: 40,
              score: score,
              eliminationScore: eliminationScore,
              active: isCurrent && !eliminated,
            ),
            const SizedBox(width: LoungeTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        seat == PlayerSeat.south
                            ? Icons.person_outline
                            : Icons.smart_toy_outlined,
                        size: 15,
                        color: LoungeTokens.sandLine,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          strings.seatLabel(seat),
                          overflow: TextOverflow.ellipsis,
                          style: LoungeTokens.title.copyWith(
                            color: nameColor,
                            decoration: eliminated
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                      if (isStarter || isCurrent || eliminated) ...[
                        const SizedBox(width: LoungeTokens.space2),
                        if (isCurrent)
                          _StatusTag(
                            label: strings.turn,
                            color: LoungeTokens.goldAccent,
                          ),
                        if (isStarter) ...[
                          const SizedBox(width: 4),
                          _StatusTag(
                            label: strings.starter,
                            color: LoungeTokens.sandLine,
                          ),
                        ],
                        if (eliminated) ...[
                          const SizedBox(width: 4),
                          _StatusTag(
                            label: strings.out,
                            color: LoungeTokens.invalidAction,
                          ),
                        ],
                      ],
                    ],
                  ),
                  const SizedBox(height: LoungeTokens.space2),
                  _HeatBar(score: score, limit: eliminationScore),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How far a seat has run toward the elimination line: sand while safe,
/// warming to flame as it closes in, with the line itself marked.
class _HeatBar extends StatelessWidget {
  const _HeatBar({required this.score, required this.limit});

  final int score;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final fraction = limit <= 0 ? 0.0 : (score / limit).clamp(0.0, 1.0);
    final color = Color.lerp(
      LoungeTokens.sandLine,
      LoungeTokens.fiftyFlame,
      ((fraction - 0.45) / 0.55).clamp(0.0, 1.0),
    )!;
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 6,
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                FractionallySizedBox(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: fraction,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [LoungeTokens.sandLine, color],
                      ),
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.4),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: LoungeTokens.space2),
        Icon(
          Icons.local_fire_department_outlined,
          size: 13,
          color: LoungeTokens.fiftyFlame.withValues(alpha: 0.8),
        ),
        Text(
          '$limit',
          style: LoungeTokens.numericChip.copyWith(
            fontSize: 11,
            color: LoungeTokens.mutedText,
          ),
        ),
      ],
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
  const _LegendRow({required this.starter, required this.currentSeat});

  final PlayerSeat starter;
  final PlayerSeat currentSeat;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final starterLabel = strings.seatLabel(starter);
    final currentLabel = strings.seatLabel(currentSeat);
    return Wrap(
      spacing: LoungeTokens.space2,
      runSpacing: LoungeTokens.space2,
      children: [
        _LegendPill(
          icon: Icons.flag_outlined,
          label: strings.startedBy(starterLabel),
        ),
        _LegendPill(
          icon: Icons.local_fire_department_outlined,
          label: strings.onTheTable(currentLabel),
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
