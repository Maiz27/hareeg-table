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
          await Navigator.of(context).pushNamed(
            AppRoutes.practiceReadingPanel,
            arguments: lesson.id,
          );
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
                  _PackHeader(title: pack.title(strings)),
                  const SizedBox(height: LoungeTokens.space3),
                  for (final lesson in PracticeCatalog.lessonsIn(pack))
                    _LessonTile(
                      key: ValueKey('practice-lesson-tile-${lesson.id}'),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(strings.practiceIntro, style: LoungeTokens.bodyMuted),
        const SizedBox(height: LoungeTokens.space4),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.practiceProgress(completed, total),
                    style: LoungeTokens.heading,
                  ),
                  const SizedBox(height: LoungeTokens.space2),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : completed / total,
                      minHeight: 6,
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
            const SizedBox(width: LoungeTokens.space4),
            TextButton.icon(
              onPressed: onReplayIntro,
              icon: const Icon(Icons.replay_outlined, size: 18),
              label: Text(strings.practiceReplayIntro),
              style: TextButton.styleFrom(
                foregroundColor: LoungeTokens.mutedText,
                // The theme minimum is full-width; shrink to row content.
                minimumSize: const Size(0, 40),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PackHeader extends StatelessWidget {
  const _PackHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: LoungeTokens.heading),
        const SizedBox(width: LoungeTokens.space3),
        Expanded(
          child: Divider(
            height: 1,
            color: LoungeTokens.sandLine.withValues(alpha: 0.22),
          ),
        ),
      ],
    );
  }
}

class _LessonTile extends StatelessWidget {
  const _LessonTile({
    super.key,
    required this.lesson,
    required this.status,
    required this.onStart,
    required this.onSkip,
    required this.onUnskip,
  });

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

    return Container(
      margin: const EdgeInsets.only(bottom: LoungeTokens.space3),
      padding: const EdgeInsets.all(LoungeTokens.space4),
      decoration: BoxDecoration(
        color: LoungeTokens.coffeeCharcoal.withValues(alpha: muted ? 0.3 : 0.5),
        borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
        border: Border.all(color: look.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(look.badgeIcon, size: 20, color: look.badgeColor),
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
              if (status == PracticeLessonStatus.skipped)
                TextButton(
                  onPressed: onUnskip,
                  style: TextButton.styleFrom(
                    foregroundColor: LoungeTokens.mutedText,
                    visualDensity: VisualDensity.compact,
                    // The theme minimum is full-width; shrink to row content.
                    minimumSize: const Size(0, 36),
                  ),
                  child: Text(strings.practiceUnskip),
                )
              else if (status == PracticeLessonStatus.notStarted)
                TextButton(
                  onPressed: onSkip,
                  style: TextButton.styleFrom(
                    foregroundColor: LoungeTokens.mutedText,
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size(0, 36),
                  ),
                  child: Text(strings.practiceSkip),
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
    Color badgeColor,
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
        badgeColor: LoungeTokens.mutedText,
        borderColor: restingBorder,
        startIcon: Icons.play_arrow_outlined,
        startLabel: strings.practiceStart,
        statusLabel: strings.practiceStatusNotStarted,
      ),
      PracticeLessonStatus.skipped => (
        muted: true,
        badgeIcon: Icons.remove_circle_outline,
        badgeColor: LoungeTokens.mutedText,
        borderColor: restingBorder,
        startIcon: Icons.play_arrow_outlined,
        startLabel: strings.practiceStart,
        statusLabel: strings.practiceStatusSkipped,
      ),
      PracticeLessonStatus.completed => (
        muted: false,
        badgeIcon: Icons.check_circle,
        badgeColor: LoungeTokens.goldAccent,
        borderColor: LoungeTokens.goldAccent.withValues(alpha: 0.45),
        startIcon: Icons.replay_outlined,
        startLabel: strings.practiceReplay,
        statusLabel: strings.practiceStatusCompleted,
      ),
    };
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
