import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/app_metadata.dart';
import '../../../../app/app_routes.dart';
import '../../../../domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import '../../../../domain/classic_hareeg/models/classic_hareeg_setup.dart';
import '../../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../../domain/classic_hareeg/reporting/classic_hareeg_match_report.dart';
import '../../../../domain/classic_hareeg/reporting/match_action_transcript.dart';
import '../../../../domain/classic_hareeg/reporting/match_diagnostic_log.dart';
import '../../../../domain/classic_hareeg/rules/match_progression_rules.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/audio/table_audio.dart';
import '../../../core/cards/card_theme.dart';
import '../../../core/feedback/lounge_toast.dart';
import '../../../core/haptics/table_haptics.dart';
import '../../../core/motion/motion_speed.dart';
import '../../../core/motif/geometric_motif_painter.dart';
import '../../../core/scopes/app_scopes.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../../match_reports/match_report_export_flow.dart';
import '../../match_reports/match_report_exporter.dart';

/// Route payload for [MatchOverScreen].
class MatchOverArguments {
  /// Creates match-over route arguments.
  const MatchOverArguments({
    required this.result,
    required this.progress,
    required this.previousScores,
    required this.roundsPlayed,
    required this.setup,
    required this.finalSnapshot,
    this.eliminatedRound = const {},
    this.diagnostics,
    this.transcript,
  });

  /// Final round result.
  final RoundProgressResult result;

  /// Match progress after the final round.
  final MatchProgressState progress;

  /// Scores before the final round was applied.
  final Map<PlayerSeat, int> previousScores;

  /// One-based count of dealt rounds played in the match.
  final int roundsPlayed;

  /// Setup reused by the rematch action.
  final ClassicHareegSetup setup;

  /// Final match snapshot exported from the match-over flow.
  final ClassicHareegMatchSnapshot finalSnapshot;

  /// Round number in which each seat was eliminated, when known.
  final Map<PlayerSeat, int> eliminatedRound;

  /// Rolling diagnostic event log captured during the match, when available.
  final MatchDiagnosticLog? diagnostics;

  /// Replayable action transcript captured during the match, when available.
  final MatchActionTranscript? transcript;
}

/// Final match summary and rematch surface.
class MatchOverScreen extends StatefulWidget {
  /// Creates a match-over screen.
  const MatchOverScreen({
    required this.arguments,
    this.reportExporter = const MatchReportExporter(),
    super.key,
  });

  /// Route payload.
  final MatchOverArguments arguments;

  /// Report exporter used by the export action.
  final MatchReportExporter reportExporter;

  @override
  State<MatchOverScreen> createState() => _MatchOverScreenState();
}

class _MatchOverScreenState extends State<MatchOverScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entryController;
  late final AnimationController _pulseController;
  bool _entryStarted = false;
  bool _pulseStarted = false;
  bool _cuesScheduled = false;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motion = MotionScope.of(context);
    _entryController.duration = motion.scale(const Duration(milliseconds: 900));
    _pulseController.duration = motion.scale(
      const Duration(milliseconds: 1200),
    );
    if (!_entryStarted) {
      _entryStarted = true;
      unawaited(_entryController.forward());
    }
    if (!_pulseStarted && _shouldPulse(context)) {
      _pulseStarted = true;
      unawaited(_pulseController.forward());
    }
    _scheduleFirstFrameCues();
  }

  @override
  void dispose() {
    _entryController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _scheduleFirstFrameCues() {
    if (_cuesScheduled) {
      return;
    }
    _cuesScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(AudioScope.of(context).play(TableSoundEvent.matchEnd));
      if (_shouldPlaySouthWinHaptic(context)) {
        unawaited(HapticsScope.of(context).fire(TableHapticEvent.matchEnd));
      }
    });
  }

  bool _shouldPulse(BuildContext context) {
    final strictness = StrictnessScope.of(context);
    final motion = MotionScope.of(context);
    return !motion.reduced && strictness != TableStrictness.table;
  }

  bool _shouldPlaySouthWinHaptic(BuildContext context) {
    final winner = widget.arguments.progress.matchWinner;
    final strictness = StrictnessScope.of(context);
    return winner == PlayerSeat.south && strictness != TableStrictness.table;
  }

  Future<void> _exportCompletedMatchReport() async {
    final choice = await showMatchReportConfirmation(
      context,
      highContrast: CardContrastScope.enabledOf(context),
    );
    if (!mounted || choice == null) {
      return;
    }
    final args = widget.arguments;
    final ClassicHareegMatchReport report;
    try {
      final generatedAt = DateTime.now().toUtc();
      report = ClassicHareegMatchReport.completed(
        app: HareegAppMetadata.reportMetadata,
        platform: currentMatchReportPlatform(),
        generatedAt: generatedAt,
        snapshot: args.finalSnapshot,
        roundResult: args.result,
        matchProgress: args.progress,
        diagnostics: args.diagnostics,
        transcript: args.transcript,
      );
    } on Object catch (error, stackTrace) {
      debugPrint('[hareeg:reports] Failed to generate match report: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        showLoungeToast(
          context,
          message: context.strings.matchReportGenerationFailed,
          icon: Icons.error_outline,
          isError: true,
        );
      }
      return;
    }
    switch (choice) {
      case MatchReportExportChoice.share:
        await _shareOrOfferCopy(report);
      case MatchReportExportChoice.copy:
        await _copyMatchReport(report);
    }
  }

  Future<void> _shareOrOfferCopy(ClassicHareegMatchReport report) async {
    final strings = context.strings;
    final attempt = await widget.reportExporter.share(report);
    if (!mounted) {
      return;
    }
    if (attempt.shared) {
      showLoungeToast(
        context,
        message: strings.matchReportShareReady,
        actionLabel: strings.copyReport,
        onActionPressed: () {
          unawaited(_copyMatchReport(report));
        },
      );
      return;
    }
    showLoungeToast(
      context,
      message: strings.matchReportCopyFallback,
      icon: Icons.error_outline,
      isError: true,
      actionLabel: strings.copyReport,
      onActionPressed: () {
        unawaited(_copyMatchReport(report));
      },
    );
  }

  Future<void> _copyMatchReport(ClassicHareegMatchReport report) async {
    final strings = context.strings;
    try {
      await widget.reportExporter.copy(report);
      if (!mounted) {
        return;
      }
      showLoungeToast(context, message: strings.matchReportCopied);
    } on Exception catch (error, stackTrace) {
      debugPrint('[hareeg:reports] Failed to copy match report: $error');
      debugPrintStack(
        label: '[hareeg:reports] Match report copy failure stack.',
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      showLoungeToast(
        context,
        message: strings.matchReportCopyFailed,
        icon: Icons.error_outline,
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final args = widget.arguments;
    final winner = args.progress.matchWinner;
    final shouldPulse = _shouldPulse(context);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: LoungeTokens.feltGreen,
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              _MatchOverBackdrop(
                pulseAnimation: _pulseController,
                pulseEnabled: shouldPulse,
              ),
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  LoungeTokens.space5,
                  LoungeTokens.space5,
                  LoungeTokens.space5,
                  LoungeTokens.space8,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _AnimatedIntro(
                          animation: _entryController,
                          child: _WinnerHeader(
                            winner: winner,
                            result: args.result,
                          ),
                        ),
                        const _SectionBreak(),
                        _AnimatedBlock(
                          animation: _entryController,
                          begin: 0.28,
                          end: 0.62,
                          child: _FinalStandingsTable(arguments: args),
                        ),
                        const _SectionBreak(),
                        _AnimatedBlock(
                          animation: _entryController,
                          begin: 0.48,
                          end: 0.78,
                          child: Text(
                            strings.roundsPlayed(args.roundsPlayed),
                            textAlign: TextAlign.center,
                            style: LoungeTokens.bodyMuted,
                          ),
                        ),
                        const SizedBox(height: LoungeTokens.space6),
                        _AnimatedBlock(
                          animation: _entryController,
                          begin: 0.68,
                          end: 1.0,
                          child: _MatchOverActions(
                            setup: args.setup,
                            onExportReport: () {
                              unawaited(_exportCompletedMatchReport());
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MatchOverBackdrop extends StatelessWidget {
  const _MatchOverBackdrop({
    required this.pulseAnimation,
    required this.pulseEnabled,
  });

  final Animation<double> pulseAnimation;
  final bool pulseEnabled;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: LoungeTokens.feltGreen)),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.18),
            ),
          ),
        ),
        Positioned(
          top: -46,
          right: -54,
          child: _PulseMotif(
            key: pulseEnabled ? const ValueKey('match-over-pulse') : null,
            animation: pulseAnimation,
            enabled: pulseEnabled,
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

class _PulseMotif extends StatelessWidget {
  const _PulseMotif({
    required this.animation,
    required this.enabled,
    super.key,
  });

  final Animation<double> animation;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return const LoungeMotif(
        variant: LoungeMotifVariant.medallion,
        opacity: 0.06,
        strokeWidth: 1.0,
        density: 4,
        size: Size.square(320),
      );
    }
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final value = Curves.easeInOut.transform(animation.value);
        final opacity = 0.06 + (0.06 * (1.0 - (2.0 * value - 1.0).abs()));
        return LoungeMotif(
          variant: LoungeMotifVariant.medallion,
          opacity: opacity,
          strokeWidth: 1.0,
          density: 4,
          size: const Size.square(320),
        );
      },
    );
  }
}

class _WinnerHeader extends StatelessWidget {
  const _WinnerHeader({required this.winner, required this.result});

  final PlayerSeat? winner;
  final RoundProgressResult result;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final winnerSeat = winner;
    final headline = winnerSeat == null
        ? strings.matchOver
        : strings.matchWinnerHeadline(winnerSeat);
    final resultLine = switch (result.type) {
      RoundOutcomeType.fiftyFinish => strings.wonByFifty,
      RoundOutcomeType.normalFinish => strings.wonByFinish,
      RoundOutcomeType.draw => strings.roundDrawn,
    };

    return Column(
      children: [
        Text(
          strings.matchOver.toUpperCase(),
          textAlign: TextAlign.center,
          style: LoungeTokens.titleSmall.copyWith(
            color: LoungeTokens.goldAccent,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: LoungeTokens.space5),
        Text(
          headline,
          textAlign: TextAlign.center,
          style: LoungeTokens.display.copyWith(
            color: LoungeTokens.goldAccent,
            fontSize: 38,
            fontWeight: FontWeight.w900,
            height: 1.02,
          ),
        ),
        const SizedBox(height: LoungeTokens.space3),
        Text(
          resultLine,
          textAlign: TextAlign.center,
          style: LoungeTokens.bodyMuted.copyWith(
            color: LoungeTokens.offWhiteText.withValues(alpha: 0.78),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _FinalStandingsTable extends StatelessWidget {
  const _FinalStandingsTable({required this.arguments});

  final MatchOverArguments arguments;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final rows = PlayerSeat.values.toList()
      ..sort((left, right) {
        final scoreOrder = _scoreFor(left).compareTo(_scoreFor(right));
        if (scoreOrder != 0) {
          return scoreOrder;
        }
        final winner = arguments.progress.matchWinner;
        if (left == winner) {
          return -1;
        }
        if (right == winner) {
          return 1;
        }
        return left.index.compareTo(right.index);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.finalStandings.toUpperCase(),
          style: LoungeTokens.titleSmall.copyWith(
            color: LoungeTokens.mutedText,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: LoungeTokens.space3),
        DecoratedBox(
          decoration: BoxDecoration(
            color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: LoungeTokens.sandLine.withValues(alpha: 0.20),
            ),
          ),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                _StandingRow(
                  key: ValueKey('final-standing-${rows[i].name}'),
                  rank: i + 1,
                  seat: rows[i],
                  score: _scoreFor(rows[i]),
                  isWinner: rows[i] == arguments.progress.matchWinner,
                  eliminatedRound: arguments.eliminatedRound[rows[i]],
                  isEliminated: !arguments.progress.activeSeats.contains(
                    rows[i],
                  ),
                ),
                if (i < rows.length - 1)
                  Divider(
                    height: 1,
                    color: LoungeTokens.sandLine.withValues(alpha: 0.14),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  int _scoreFor(PlayerSeat seat) => arguments.progress.scores[seat] ?? 0;
}

class _StandingRow extends StatelessWidget {
  const _StandingRow({
    required this.rank,
    required this.seat,
    required this.score,
    required this.isWinner,
    required this.isEliminated,
    this.eliminatedRound,
    super.key,
  });

  final int rank;
  final PlayerSeat seat;
  final int score;
  final bool isWinner;
  final bool isEliminated;
  final int? eliminatedRound;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final footnote = eliminatedRound == null
        ? strings.eliminated
        : strings.eliminatedInRound(eliminatedRound!);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isWinner
            ? LoungeTokens.selectedGlow.withValues(alpha: 0.36)
            : Colors.transparent,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: LoungeTokens.space3,
          vertical: LoungeTokens.space3,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: Text(
                '$rank.',
                style: LoungeTokens.numericChip.copyWith(
                  color: isWinner
                      ? LoungeTokens.goldAccent
                      : LoungeTokens.mutedText,
                ),
              ),
            ),
            Icon(
              isWinner ? Icons.emoji_events_outlined : Icons.person_outline,
              color: isWinner
                  ? LoungeTokens.goldAccent
                  : LoungeTokens.mutedText.withValues(alpha: 0.70),
              size: 20,
            ),
            const SizedBox(width: LoungeTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.seatLabel(seat),
                    style: LoungeTokens.titleSmall.copyWith(
                      color: isWinner
                          ? LoungeTokens.goldAccent
                          : LoungeTokens.offWhiteText,
                    ),
                  ),
                  if (isEliminated && !isWinner)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(footnote, style: LoungeTokens.bodyMuted),
                    ),
                ],
              ),
            ),
            Text(
              _scoreLabel(score),
              style: LoungeTokens.numericChip.copyWith(
                color: isWinner
                    ? LoungeTokens.goldAccent
                    : LoungeTokens.offWhiteText,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _scoreLabel(int score) => score > 0 ? '+$score' : '$score';
}

class _MatchOverActions extends StatelessWidget {
  const _MatchOverActions({required this.setup, required this.onExportReport});

  final ClassicHareegSetup setup;
  final VoidCallback onExportReport;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          key: const ValueKey('match-over-return-menu'),
          onPressed: () {
            Navigator.of(
              context,
            ).pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
          },
          icon: const Icon(Icons.home_outlined),
          label: Text(strings.returnToMenu),
        ),
        const SizedBox(height: LoungeTokens.space3),
        OutlinedButton.icon(
          key: const ValueKey('match-over-export-report'),
          onPressed: onExportReport,
          icon: const Icon(Icons.file_upload_outlined),
          label: Text(strings.exportMatchReport),
        ),
        const SizedBox(height: LoungeTokens.space3),
        OutlinedButton.icon(
          key: const ValueKey('match-over-rematch'),
          onPressed: () {
            Navigator.of(context).pushNamedAndRemoveUntil(
              AppRoutes.table,
              (route) => false,
              arguments: setup,
            );
          },
          icon: const Icon(Icons.refresh),
          label: Text(strings.newMatchSameSetup),
        ),
      ],
    );
  }
}

class _AnimatedIntro extends StatelessWidget {
  const _AnimatedIntro({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final motion = MotionScope.of(context);
    final fade = CurvedAnimation(
      parent: animation,
      curve: Interval(0.0, 0.44, curve: motion.curve(Curves.easeOutCubic)),
    );
    final scale = CurvedAnimation(
      parent: animation,
      curve: Interval(0.12, 0.54, curve: motion.curve(Curves.easeOutBack)),
    );
    return FadeTransition(
      opacity: fade,
      child: ScaleTransition(
        scale: Tween<double>(
          begin: motion.reduced ? 1.0 : 0.92,
          end: 1.0,
        ).animate(scale),
        child: child,
      ),
    );
  }
}

class _AnimatedBlock extends StatelessWidget {
  const _AnimatedBlock({
    required this.animation,
    required this.begin,
    required this.end,
    required this.child,
  });

  final Animation<double> animation;
  final double begin;
  final double end;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final motion = MotionScope.of(context);
    final curve = CurvedAnimation(
      parent: animation,
      curve: Interval(begin, end, curve: motion.curve(Curves.easeOutCubic)),
    );
    return FadeTransition(opacity: curve, child: child);
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
