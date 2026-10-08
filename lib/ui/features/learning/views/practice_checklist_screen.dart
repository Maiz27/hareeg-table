import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/app_orientation.dart';
import '../../../../app/app_routes.dart';
import '../../../../data/persistence/learning_progress_repository.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/motif/geometric_motif_painter.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../models/practice_catalog.dart';
import '../models/practice_lesson_registry.dart';
import '../progress/learning_progress_workflow.dart';
import 'onboarding_screen.dart';

/// Guided practice checklist hub.
///
/// Shows every planned practice lesson with its progress state and gives the
/// player a stable place to start, skip, resume, and replay practice hands.
/// Progress persists locally and is independent of onboarding completion.
class PracticeChecklistScreen extends StatefulWidget {
  /// Creates the practice hub.
  const PracticeChecklistScreen({required this.learningRepository, super.key});

  /// Onboarding and practice progress persistence.
  final LearningProgressRepository learningRepository;

  @override
  State<PracticeChecklistScreen> createState() =>
      _PracticeChecklistScreenState();
}

class _PracticeChecklistScreenState extends State<PracticeChecklistScreen> {
  late final LearningProgressWorkflow _learningWorkflow;
  LearningProgress _progress = LearningProgress.defaults();

  @override
  void initState() {
    super.initState();
    _learningWorkflow = LearningProgressWorkflow(widget.learningRepository);
    AppOrientation.usePortrait();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    try {
      final progress = await _learningWorkflow.load();
      if (!mounted) {
        return;
      }
      setState(() => _progress = progress);
    } catch (error, stackTrace) {
      debugPrint('Failed to load practice progress: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _setStatus(
    PracticeLesson lesson,
    PracticeLessonStatus status,
  ) async {
    final next = _progress.withLessonStatus(lesson.id, status);
    setState(() => _progress = next);
    try {
      await _learningWorkflow.setLessonStatus(lesson.id, status);
    } catch (error, stackTrace) {
      debugPrint('Failed to save practice progress: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _startLesson(PracticeLesson lesson) async {
    final delivery = PracticeLessonRegistry.deliveryFor(lesson.id);
    if (!delivery.isAvailable) {
      // The lesson's practice pack has not shipped yet.
      final strings = context.strings;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(strings.practiceComingSoon)));
      return;
    }
    try {
      if (delivery.isReadingPanel) {
        // Reading panels dispatch by lesson id: the bespoke strictness-tiers
        // panel keeps its hand-built tier screen; every other reading panel
        // renders through the generic reference-panel screen.
        if (lesson.id == PracticeLessonRegistry.strictnessTiersLessonId) {
          await Navigator.of(context).pushNamed(AppRoutes.strictnessExplainer);
        } else {
          await Navigator.of(
            context,
          ).pushNamed(AppRoutes.practiceReadingPanel, arguments: lesson.id);
        }
      } else {
        await Navigator.of(
          context,
        ).pushNamed(AppRoutes.practiceLesson, arguments: lesson.id);
      }
    } finally {
      if (mounted) {
        await _loadProgress();
      }
    }
  }

  Future<void> _replayIntro() async {
    // The shared repository serializes its own load-modify-save updates, so a
    // just-tapped skip can no longer be lost when onboarding writes the same
    // key. No manual settle is needed before navigating.
    unawaited(
      Navigator.of(context).pushNamed(
        AppRoutes.onboarding,
        arguments: OnboardingScreen.fromPracticeArgument,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final lessonIds = PracticeCatalog.lessonIds;
    final completed = _progress.completedCount(lessonIds);

    return Scaffold(
      backgroundColor: LoungeTokens.feltGreen,
      appBar: AppBar(title: Text(strings.practiceTitle)),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const _PracticeBackdrop(),
            ListView(
              padding: const EdgeInsets.fromLTRB(
                LoungeTokens.space5,
                LoungeTokens.space5,
                LoungeTokens.space5,
                LoungeTokens.space8,
              ),
              children: [
                _PracticeHeader(
                  completed: completed,
                  total: lessonIds.length,
                  onReplayIntro: _replayIntro,
                ),
                const SizedBox(height: LoungeTokens.space5),
                for (final pack in PracticePackId.values) ...[
                  _PackHeader(
                    title: pack.title(strings),
                    completed: _progress.completedCount([
                      for (final l in PracticeCatalog.lessonsIn(pack)) l.id,
                    ]),
                    total: PracticeCatalog.lessonsIn(pack).length,
                  ),
                  const SizedBox(height: LoungeTokens.space3),
                  for (final lesson in PracticeCatalog.lessonsIn(pack))
                    _LessonTile(
                      key: ValueKey('practice-lesson-tile-${lesson.id}'),
                      number: lessonIds.indexOf(lesson.id) + 1,
                      lesson: lesson,
                      status: _progress.statusFor(lesson.id),
                      onStart: () => _startLesson(lesson),
                      onSkip: () =>
                          _setStatus(lesson, PracticeLessonStatus.skipped),
                      onUnskip: () =>
                          _setStatus(lesson, PracticeLessonStatus.notStarted),
                    ),
                  if (pack != PracticePackId.values.last)
                    const SizedBox(height: LoungeTokens.space5),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PracticeHeader extends StatelessWidget {
  const _PracticeHeader({
    required this.completed,
    required this.total,
    required this.onReplayIntro,
  });

  final int completed;
  final int total;
  final VoidCallback onReplayIntro;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final fraction = total == 0 ? 0.0 : completed / total;

    // A progress card: the lessons done as a ring, lit like the table.
    return Container(
      padding: const EdgeInsets.all(LoungeTokens.space4),
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.8, -0.6),
          radius: 1.4,
          colors: [
            LoungeTokens.goldAccent.withValues(alpha: 0.12),
            LoungeTokens.coffeeCharcoal.withValues(alpha: 0.55),
          ],
        ),
        borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
        border: Border.all(
          color: LoungeTokens.sandLine.withValues(alpha: 0.22),
        ),
        boxShadow: LoungeTokens.elevationL2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox.square(
                dimension: 64,
                child: CustomPaint(
                  painter: _ProgressRingPainter(fraction: fraction),
                  child: Center(
                    child: Text(
                      '$completed',
                      style: LoungeTokens.numericDisplay.copyWith(fontSize: 22),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: LoungeTokens.space4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.practiceProgress(completed, total),
                      style: LoungeTokens.heading,
                    ),
                    const SizedBox(height: LoungeTokens.space1),
                    // Kept as the linear readout too: it is what assistive
                    // tech and the existing tests read as progress.
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: fraction,
                        minHeight: 4,
                        backgroundColor: LoungeTokens.coffeeCharcoal.withValues(
                          alpha: 0.5,
                        ),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          LoungeTokens.goldAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: LoungeTokens.space3),
          Text(strings.practiceIntro, style: LoungeTokens.bodyMuted),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: onReplayIntro,
              icon: const Icon(Icons.replay_outlined, size: 18),
              label: Text(strings.practiceReplayIntro),
              style: TextButton.styleFrom(
                foregroundColor: LoungeTokens.goldAccent,
                // The theme minimum is full-width; shrink to row content.
                minimumSize: const Size(0, 40),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressRingPainter extends CustomPainter {
  const _ProgressRingPainter({required this.fraction});

  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(4);
    canvas.drawArc(
      rect,
      0,
      6.2832,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = LoungeTokens.sandLine.withValues(alpha: 0.16),
    );
    if (fraction > 0) {
      canvas.drawArc(
        rect,
        -1.5708,
        6.2832 * fraction,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..color = LoungeTokens.goldAccent,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter oldDelegate) =>
      oldDelegate.fraction != fraction;
}

class _PackHeader extends StatelessWidget {
  const _PackHeader({
    required this.title,
    required this.completed,
    required this.total,
  });

  final String title;
  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: LoungeTokens.heading),
        const SizedBox(width: LoungeTokens.space3),
        Expanded(
          child: Container(
            height: 1,
            color: LoungeTokens.sandLine.withValues(alpha: 0.22),
          ),
        ),
        const SizedBox(width: LoungeTokens.space3),
        Text(
          '$completed/$total',
          style: LoungeTokens.numericChip.copyWith(
            fontSize: 12,
            color: completed == total && total > 0
                ? LoungeTokens.goldAccent
                : LoungeTokens.mutedText,
          ),
        ),
      ],
    );
  }
}

class _LessonTile extends StatelessWidget {
  const _LessonTile({
    super.key,
    required this.number,
    required this.lesson,
    required this.status,
    required this.onStart,
    required this.onSkip,
    required this.onUnskip,
  });

  /// Position of the lesson across the whole course, shown on its medallion.
  final int number;
  final PracticeLesson lesson;
  final PracticeLessonStatus status;
  final VoidCallback onStart;
  final VoidCallback onSkip;
  final VoidCallback onUnskip;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final look = _lookFor(strings);
    final muted = look.muted;
    final skipped = status == PracticeLessonStatus.skipped;

    return Container(
      margin: const EdgeInsets.only(bottom: LoungeTokens.space3),
      padding: const EdgeInsets.all(LoungeTokens.space4),
      decoration: BoxDecoration(
        color: LoungeTokens.coffeeCharcoal.withValues(alpha: muted ? 0.3 : 0.5),
        borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
        border: Border.all(color: look.borderColor),
        boxShadow: muted ? null : LoungeTokens.elevationL2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LessonMedallion(
                number: number,
                status: status,
                icon: look.badgeIcon,
              ),
              const SizedBox(width: LoungeTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lesson.title(strings),
                      style: LoungeTokens.body.copyWith(
                        fontWeight: FontWeight.w700,
                        color: muted
                            ? LoungeTokens.mutedText
                            : LoungeTokens.offWhiteText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lesson.summary(strings),
                      style: LoungeTokens.bodyMuted.copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: LoungeTokens.space3),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  look.statusLabel,
                  overflow: TextOverflow.ellipsis,
                  style: LoungeTokens.bodyMuted.copyWith(
                    fontSize: 12,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              // Skip and unskip toggle each other; a completed lesson offers
              // neither.
              if (status != PracticeLessonStatus.completed)
                TextButton(
                  onPressed: skipped ? onUnskip : onSkip,
                  style: TextButton.styleFrom(
                    foregroundColor: LoungeTokens.mutedText,
                    visualDensity: VisualDensity.compact,
                    // The theme minimum is full-width; shrink to row content.
                    minimumSize: const Size(0, 36),
                  ),
                  child: Text(
                    skipped ? strings.practiceUnskip : strings.practiceSkip,
                  ),
                ),
              const SizedBox(width: LoungeTokens.space2),
              OutlinedButton.icon(
                onPressed: onStart,
                icon: Icon(look.startIcon, size: 18),
                label: Text(look.startLabel),
                style: OutlinedButton.styleFrom(
                  foregroundColor: LoungeTokens.goldAccent,
                  side: BorderSide(
                    color: LoungeTokens.goldAccent.withValues(alpha: 0.5),
                  ),
                  visualDensity: VisualDensity.compact,
                  minimumSize: const Size(0, 36),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Status-driven presentation, derived in one exhaustive switch so a new
  /// status cannot ship half-styled.
  ({
    bool muted,
    IconData badgeIcon,
    Color borderColor,
    IconData startIcon,
    String startLabel,
    String statusLabel,
  })
  _lookFor(AppStrings strings) {
    final restingBorder = LoungeTokens.sandLine.withValues(alpha: 0.16);
    return switch (status) {
      PracticeLessonStatus.notStarted => (
        muted: false,
        badgeIcon: Icons.radio_button_unchecked,
        borderColor: restingBorder,
        startIcon: Icons.play_arrow_outlined,
        startLabel: strings.practiceStart,
        statusLabel: strings.practiceStatusNotStarted,
      ),
      PracticeLessonStatus.skipped => (
        muted: true,
        badgeIcon: Icons.remove_circle_outline,
        borderColor: restingBorder,
        startIcon: Icons.play_arrow_outlined,
        startLabel: strings.practiceStart,
        statusLabel: strings.practiceStatusSkipped,
      ),
      PracticeLessonStatus.completed => (
        muted: false,
        badgeIcon: Icons.check_circle,
        borderColor: LoungeTokens.goldAccent.withValues(alpha: 0.45),
        startIcon: Icons.replay_outlined,
        startLabel: strings.practiceReplay,
        statusLabel: strings.practiceStatusCompleted,
      ),
    };
  }
}

/// A lesson's number on a lacquered medallion; gold with a check once done,
/// faded when skipped.
class _LessonMedallion extends StatelessWidget {
  const _LessonMedallion({
    required this.number,
    required this.status,
    required this.icon,
  });

  final int number;
  final PracticeLessonStatus status;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final done = status == PracticeLessonStatus.completed;
    final skipped = status == PracticeLessonStatus.skipped;
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: done
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE8B95A), LoungeTokens.goldAccent],
              )
            : const RadialGradient(
                center: Alignment(-0.3, -0.4),
                colors: [Color(0xFF3A2A1C), LoungeTokens.coffeeCharcoal],
              ),
        border: Border.all(
          color: done
              ? LoungeTokens.goldAccent
              : LoungeTokens.sandLine.withValues(alpha: skipped ? 0.18 : 0.4),
        ),
      ),
      child: done
          ? Icon(icon, size: 18, color: LoungeTokens.coffeeCharcoal)
          : skipped
          ? Icon(icon, size: 16, color: LoungeTokens.mutedText)
          : Text(
              '$number',
              style: LoungeTokens.numericChip.copyWith(
                fontSize: 13,
                color: LoungeTokens.sandLine,
              ),
            ),
    );
  }
}

class _PracticeBackdrop extends StatelessWidget {
  const _PracticeBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -44,
          right: -48,
          child: LoungeMotif(
            variant: LoungeMotifVariant.medallion,
            opacity: 0.052,
            strokeWidth: 1.0,
            density: 4,
            size: const Size.square(220),
          ),
        ),
      ],
    );
  }
}
