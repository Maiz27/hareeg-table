import 'package:flutter/material.dart';

import '../../../../app/app_orientation.dart';
import '../../../../app/app_routes.dart';
import '../../../../data/persistence/learning_progress_repository.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/motif/geometric_motif_painter.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../models/practice_catalog.dart';
import '../practice/practice_scripts.dart';

/// Guided practice checklist hub.
///
/// Shows every planned practice lesson with its progress state and gives the
/// player a stable place to start, skip, resume, and replay practice hands.
/// Progress persists locally and is independent of onboarding completion.
class PracticeChecklistScreen extends StatefulWidget {
  /// Creates the practice hub.
  const PracticeChecklistScreen({
    required this.learningRepository,
    super.key,
  });

  /// Onboarding and practice progress persistence.
  final LearningProgressRepository learningRepository;

  @override
  State<PracticeChecklistScreen> createState() =>
      _PracticeChecklistScreenState();
}

class _PracticeChecklistScreenState extends State<PracticeChecklistScreen> {
  LearningProgress _progress = LearningProgress.defaults();

  /// Serializes progress writes so rapid skip/unskip taps cannot land their
  /// repository saves out of order.
  Future<void> _pendingSave = Future<void>.value();

  @override
  void initState() {
    super.initState();
    AppOrientation.usePortrait();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    try {
      final progress = await widget.learningRepository.loadProgress();
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
    // Chain onto the previous write (absorbing its already-logged failure)
    // so saves land in tap order.
    final save = _pendingSave
        .catchError((Object _) {})
        .then((_) => widget.learningRepository.saveProgress(next));
    _pendingSave = save;
    try {
      await save;
    } catch (error, stackTrace) {
      debugPrint('Failed to save practice progress: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _startLesson(PracticeLesson lesson) async {
    if (PracticeScripts.byId(lesson.id) == null) {
      // The lesson's practice pack has not shipped yet.
      final strings = context.strings;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(strings.practiceComingSoon)));
      return;
    }
    try {
      await Navigator.of(context).pushNamed(
        AppRoutes.practiceLesson,
        arguments: lesson.id,
      );
    } finally {
      if (mounted) {
        await _loadProgress();
      }
    }
  }

  void _replayIntro() {
    Navigator.of(context).pushNamed(AppRoutes.onboarding);
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
    final muted = status == PracticeLessonStatus.skipped;

    return Container(
      margin: const EdgeInsets.only(bottom: LoungeTokens.space3),
      padding: const EdgeInsets.all(LoungeTokens.space4),
      decoration: BoxDecoration(
        color: LoungeTokens.coffeeCharcoal.withValues(
          alpha: muted ? 0.3 : 0.5,
        ),
        borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
        border: Border.all(
          color: status == PracticeLessonStatus.completed
              ? LoungeTokens.goldAccent.withValues(alpha: 0.45)
              : LoungeTokens.sandLine.withValues(alpha: 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StatusBadge(status: status),
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
                  _statusLabel(strings),
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
                icon: Icon(
                  status == PracticeLessonStatus.completed
                      ? Icons.replay_outlined
                      : Icons.play_arrow_outlined,
                  size: 18,
                ),
                label: Text(
                  status == PracticeLessonStatus.completed
                      ? strings.practiceReplay
                      : strings.practiceStart,
                ),
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

  String _statusLabel(AppStrings strings) {
    return switch (status) {
      PracticeLessonStatus.notStarted => strings.practiceStatusNotStarted,
      PracticeLessonStatus.skipped => strings.practiceStatusSkipped,
      PracticeLessonStatus.completed => strings.practiceStatusCompleted,
    };
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final PracticeLessonStatus status;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      PracticeLessonStatus.notStarted => (
        Icons.radio_button_unchecked,
        LoungeTokens.mutedText,
      ),
      PracticeLessonStatus.skipped => (
        Icons.remove_circle_outline,
        LoungeTokens.mutedText,
      ),
      PracticeLessonStatus.completed => (
        Icons.check_circle,
        LoungeTokens.goldAccent,
      ),
    };
    return Icon(icon, size: 20, color: color);
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
