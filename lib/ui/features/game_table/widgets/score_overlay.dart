import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../../domain/classic_hareeg/replay/score_book.dart';
import '../../../../domain/classic_hareeg/reporting/match_action_transcript.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/cards/card_theme.dart';
import '../../../core/panels/lounge_panel.dart';
import '../../../core/theme/lounge_tokens.dart';

/// The match score book (design contract 7.5).
///
/// Laid out the way the table keeps score on paper: the players across the
/// top as columns, one row per round down the page, each cell the seat's
/// running total with what that round added beneath it. The round in play is
/// the last, lit row. Earlier rounds are recovered from the match transcript
/// (the live match keeps only current scores), reconstructed in small steps
/// so opening the book never stalls a frame.
class ScoreOverlay extends StatefulWidget {
  /// Creates the score book overlay.
  const ScoreOverlay({
    super.key,
    required this.scores,
    required this.activeSeats,
    required this.starter,
    required this.currentSeat,
    required this.roundNumber,
    required this.onClose,
    this.eliminationScore = 31,
    this.transcript,
  });

  /// Current match totals.
  final Map<PlayerSeat, int> scores;

  /// Seats still in the match.
  final List<PlayerSeat> activeSeats;

  /// Seat that started the current round.
  final PlayerSeat starter;

  /// Seat whose turn it is.
  final PlayerSeat currentSeat;

  /// Round in play.
  final int roundNumber;

  /// Closes the overlay.
  final VoidCallback onClose;

  /// Score at which a seat is out of the match.
  final int eliminationScore;

  /// Reads the recorded actions of the match so far; earlier rounds are
  /// recovered from them. Called once, when the book opens (building the
  /// transcript copies every entry, so it is never done per table rebuild).
  /// Null, or returning null (practice), shows the live round only.
  final MatchActionTranscript? Function()? transcript;

  @override
  State<ScoreOverlay> createState() => _ScoreOverlayState();
}

class _ScoreOverlayState extends State<ScoreOverlay> {
  ScoreBookReader? _reader;
  Map<int, Map<PlayerSeat, int>> _completed = const {};
  int _firstRound = 1;
  Map<PlayerSeat, int> _startScores = const {};

  @override
  void initState() {
    super.initState();
    final transcript = widget.roundNumber > 1
        ? widget.transcript?.call()
        : null;
    if (transcript != null) {
      _reader = ScoreBookReader(transcript);
      _startScores = _reader!.startScores;
      unawaited(_read());
    }
  }

  Future<void> _read() async {
    final reader = _reader;
    if (reader == null) return;
    var more = true;
    while (more && mounted) {
      more = reader.step();
      if (!mounted) return;
      setState(() {
        _completed = reader.completedTotals(
          currentRound: widget.roundNumber,
          currentScores: widget.scores,
        );
        _firstRound = reader.firstRound;
      });
      if (more) await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  void dispose() {
    _reader?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final highContrast = CardContrastScope.enabledOf(context);
    final seats = widget.scores.keys.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final lines = buildScoreBookLines(
      completed: _completed,
      firstRound: _reader == null ? widget.roundNumber : _firstRound,
      currentRound: widget.roundNumber,
      currentScores: widget.scores,
      startScores: _startScores,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onClose,
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
                        maxWidth: 600,
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
                              icon: Icons.menu_book_outlined,
                              title: strings.scoresTitle,
                              subtitle: strings.roundToPlay(
                                widget.roundNumber,
                                widget.currentSeat,
                              ),
                              onClose: widget.onClose,
                              closeTooltip: strings.close,
                            ),
                            const SizedBox(height: LoungeTokens.space3),
                            // The rows scroll when the panel is shorter than
                            // the book; the players' header and the legend
                            // stay pinned.
                            Flexible(
                              fit: FlexFit.loose,
                              child: _ScoreBook(
                                seats: seats,
                                lines: lines,
                                activeSeats: widget.activeSeats,
                                starter: widget.starter,
                                currentSeat: widget.currentSeat,
                                eliminationScore: widget.eliminationScore,
                              ),
                            ),
                            const SizedBox(height: LoungeTokens.space3),
                            _LegendRow(
                              starter: widget.starter,
                              currentSeat: widget.currentSeat,
                              eliminationScore: widget.eliminationScore,
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

/// The ruled page of the score book.
class _ScoreBook extends StatelessWidget {
  const _ScoreBook({
    required this.seats,
    required this.lines,
    required this.activeSeats,
    required this.starter,
    required this.currentSeat,
    required this.eliminationScore,
  });

  final List<PlayerSeat> seats;
  final List<ScoreBookLine> lines;
  final List<PlayerSeat> activeSeats;
  final PlayerSeat starter;
  final PlayerSeat currentSeat;
  final int eliminationScore;

  static const _labelWidth = 48.0;

  @override
  Widget build(BuildContext context) {
    final ruling = LoungeTokens.sandLine.withValues(alpha: 0.14);
    return DecoratedBox(
      decoration: BoxDecoration(
        // Paper of the book: warm ivory ink on a deep felt page.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            LoungeTokens.feltSpotlight.withValues(alpha: 0.55),
            LoungeTokens.feltGreen.withValues(alpha: 0.45),
          ],
        ),
        borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
        border: Border.all(color: LoungeTokens.sandLine.withValues(alpha: 0.2)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Players across the top: medallion with the current total, name,
            // and a flag on the round's starter.
            Container(
              padding: const EdgeInsets.fromLTRB(
                0,
                LoungeTokens.space3,
                0,
                LoungeTokens.space2,
              ),
              decoration: BoxDecoration(
                color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.35),
                border: Border(
                  bottom: BorderSide(
                    color: LoungeTokens.sandLine.withValues(alpha: 0.35),
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(width: _labelWidth),
                  for (final seat in seats)
                    Expanded(
                      child: _SeatHeader(
                        seat: seat,
                        total: lines.last.totals[seat] ?? 0,
                        eliminationScore: eliminationScore,
                        isCurrent: seat == currentSeat,
                        isStarter: seat == starter,
                        eliminated: !activeSeats.contains(seat),
                      ),
                    ),
                ],
              ),
            ),
            Flexible(
              fit: FlexFit.loose,
              child: SingleChildScrollView(
                reverse: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final line in lines)
                      _BookRow(
                        line: line,
                        seats: seats,
                        ruling: ruling,
                        labelWidth: _labelWidth,
                        eliminationScore: eliminationScore,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeatHeader extends StatelessWidget {
  const _SeatHeader({
    required this.seat,
    required this.total,
    required this.eliminationScore,
    required this.isCurrent,
    required this.isStarter,
    required this.eliminated,
  });

  final PlayerSeat seat;
  final int total;
  final int eliminationScore;
  final bool isCurrent;
  final bool isStarter;
  final bool eliminated;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Opacity(
      opacity: eliminated ? 0.5 : 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The seat's medallion: its ring shows how close the running total
          // (the book's live row) has come to elimination.
          _SeatMedallion(
            seat: seat,
            danger: eliminationScore <= 0
                ? 0
                : (total / eliminationScore).clamp(0.0, 1.0),
            active: isCurrent && !eliminated,
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              strings.seatLabel(seat),
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: LoungeTokens.titleSmall.copyWith(
                fontSize: 12,
                letterSpacing: 0.2,
                color: isCurrent
                    ? LoungeTokens.goldAccent
                    : LoungeTokens.offWhiteText,
                decoration: eliminated ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (isStarter || eliminated)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Tooltip(
                message: eliminated ? strings.out : strings.starter,
                child: Icon(
                  eliminated ? Icons.block : Icons.flag_outlined,
                  size: 12,
                  color: eliminated
                      ? LoungeTokens.invalidAction
                      : LoungeTokens.sandLine,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SeatMedallion extends StatelessWidget {
  const _SeatMedallion({
    required this.seat,
    required this.danger,
    required this.active,
  });

  final PlayerSeat seat;
  final double danger;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final ring = Color.lerp(
      LoungeTokens.sandLine.withValues(alpha: 0.45),
      LoungeTokens.fiftyFlame,
      ((danger - 0.3) / 0.7).clamp(0.0, 1.0),
    )!;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.3, -0.45),
          colors: [Color(0xFF3A2A1C), LoungeTokens.coffeeCharcoal],
        ),
        border: Border.all(
          width: 2,
          color: active ? LoungeTokens.goldAccent : ring,
        ),
        boxShadow: [
          if (active)
            BoxShadow(
              color: LoungeTokens.goldAccent.withValues(alpha: 0.4),
              blurRadius: 12,
            ),
        ],
      ),
      child: Icon(
        seat == PlayerSeat.south
            ? Icons.person_outline
            : Icons.smart_toy_outlined,
        size: 18,
        color: active ? LoungeTokens.goldAccent : LoungeTokens.sandLine,
      ),
    );
  }
}

class _BookRow extends StatelessWidget {
  const _BookRow({
    required this.line,
    required this.seats,
    required this.ruling,
    required this.labelWidth,
    required this.eliminationScore,
  });

  final ScoreBookLine line;
  final List<PlayerSeat> seats;
  final Color ruling;
  final double labelWidth;
  final int eliminationScore;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        gradient: line.live
            ? LinearGradient(
                colors: [
                  LoungeTokens.goldAccent.withValues(alpha: 0.14),
                  LoungeTokens.goldAccent.withValues(alpha: 0.04),
                ],
              )
            : null,
        border: Border(bottom: BorderSide(color: ruling)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Center(
              child: Text(
                line.live
                    ? strings.scoreBookNow
                    : strings.scoreBookRound(line.roundNumber),
                style: LoungeTokens.overline.copyWith(
                  fontSize: line.live ? 10 : 11,
                  letterSpacing: line.live ? 0.6 : 1,
                  color: line.live
                      ? LoungeTokens.goldAccent
                      : LoungeTokens.mutedText,
                ),
              ),
            ),
          ),
          for (final seat in seats)
            Expanded(
              child: _BookCell(
                seatName: strings.seatLabel(seat),
                total: line.totals[seat] ?? 0,
                delta: line.deltas[seat],
                eliminationScore: eliminationScore,
              ),
            ),
        ],
      ),
    );
  }
}

class _BookCell extends StatelessWidget {
  const _BookCell({
    required this.seatName,
    required this.total,
    required this.delta,
    required this.eliminationScore,
  });

  final String seatName;
  final int total;
  final int? delta;
  final int eliminationScore;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final out = total >= eliminationScore;
    final danger = eliminationScore <= 0
        ? 0.0
        : (total / eliminationScore).clamp(0.0, 1.0);
    final totalColor = out
        ? LoungeTokens.invalidAction
        : Color.lerp(
            LoungeTokens.offWhiteText,
            const Color(0xFFFFB08A),
            ((danger - 0.6) / 0.4).clamp(0.0, 1.0),
          )!;
    final d = delta;
    return Semantics(
      label: strings.scoreBookCell(seatName, total, d ?? 0),
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$total',
            style: LoungeTokens.numericChip.copyWith(
              fontSize: 16,
              color: totalColor,
              decoration: out ? TextDecoration.lineThrough : null,
            ),
          ),
          if (d != null)
            Text(
              // A true minus sign: typographically right, and distinct from
              // a running total that has itself gone negative.
              d == 0
                  ? '·'
                  : d > 0
                  ? '+$d'
                  : '\u2212${-d}',
              style: LoungeTokens.numericChip.copyWith(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: d > 0
                    ? LoungeTokens.sandLine.withValues(alpha: 0.85)
                    : LoungeTokens.mutedText,
              ),
            ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.starter,
    required this.currentSeat,
    required this.eliminationScore,
  });

  final PlayerSeat starter;
  final PlayerSeat currentSeat;
  final int eliminationScore;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Wrap(
      spacing: LoungeTokens.space2,
      runSpacing: LoungeTokens.space2,
      children: [
        _LegendPill(
          icon: Icons.flag_outlined,
          label: strings.startedBy(strings.seatLabel(starter)),
        ),
        _LegendPill(
          icon: Icons.play_arrow_rounded,
          label: strings.onTheTable(strings.seatLabel(currentSeat)),
        ),
        _LegendPill(
          icon: Icons.local_fire_department_outlined,
          label: strings.scoreBookOutAt(eliminationScore),
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
        vertical: 5,
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
          Text(label, style: LoungeTokens.bodyMuted.copyWith(fontSize: 12)),
        ],
      ),
    );
  }
}
