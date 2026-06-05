import 'package:flutter/material.dart';

import '../../../../app/app_orientation.dart';
import '../../../../data/persistence/learning_progress_repository.dart';
import '../../../../domain/classic_hareeg/game/classic_hareeg_action.dart';
import '../../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/cards/card_state.dart';
import '../../../core/cards/card_view.dart';
import '../../../core/scopes/app_scopes.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../models/practice_catalog.dart';
import '../practice/practice_action_candidates.dart';
import '../practice/practice_lesson_script.dart';
import '../practice/practice_session.dart';

/// Minimal portrait teaching surface for one guided practice lesson.
///
/// Shows only what the active step needs: the instruction, a compact
/// stock/discard strip, the focused hand, and buttons for the real engine
/// actions the step allows. All legality comes from the lesson's private
/// controller; the screen never touches the active-match store.
class PracticeLessonScreen extends StatefulWidget {
  /// Creates the lesson surface.
  const PracticeLessonScreen({
    required this.script,
    required this.learningRepository,
    super.key,
  });

  /// Lesson being taught.
  final PracticeLessonScript script;

  /// Progress persistence updated when the lesson completes.
  final LearningProgressRepository learningRepository;

  @override
  State<PracticeLessonScreen> createState() => _PracticeLessonScreenState();
}

class _PracticeLessonScreenState extends State<PracticeLessonScreen> {
  late PracticeSession _session;
  final _selectedCardIds = <String>{};
  String? _errorMessage;
  String Function(AppStrings)? _stepNote;

  @override
  void initState() {
    super.initState();
    AppOrientation.usePortrait();
    _session = PracticeSession(script: widget.script);
  }

  void _restart() {
    setState(() {
      _session = PracticeSession(script: widget.script);
      _selectedCardIds.clear();
      _errorMessage = null;
      _stepNote = null;
    });
  }

  void _toggleCard(HareegCard card) {
    setState(() {
      _errorMessage = null;
      if (!_selectedCardIds.remove(card.id)) {
        _selectedCardIds.add(card.id);
      }
    });
  }

  Future<void> _submit(PracticeActionCandidate candidate) async {
    final completedStep = _session.currentStep;
    final result = _session.submit(candidate.actionId);
    setState(() {
      switch (result.status) {
        case PracticeSubmitStatus.rejected:
          _errorMessage = result.message;
        case PracticeSubmitStatus.notAllowed:
          break;
        case PracticeSubmitStatus.accepted:
          _selectedCardIds.clear();
          _errorMessage = null;
        case PracticeSubmitStatus.stepCompleted:
        case PracticeSubmitStatus.lessonCompleted:
          _selectedCardIds.clear();
          _errorMessage = null;
          _stepNote = completedStep?.successNote;
      }
    });
    if (result.status == PracticeSubmitStatus.lessonCompleted) {
      await _persistCompletion();
    }
  }

  Future<void> _persistCompletion() async {
    try {
      final progress = await widget.learningRepository.loadProgress();
      await widget.learningRepository.saveProgress(
        progress.withLessonStatus(
          widget.script.lessonId,
          PracticeLessonStatus.completed,
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Failed to save practice completion: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final lesson = PracticeCatalog.byId(widget.script.lessonId);
    final title = lesson?.title(strings) ?? strings.practiceTitle;

    return Scaffold(
      backgroundColor: LoungeTokens.feltGreen,
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: _session.isComplete
            ? _CompletionPanel(
                onReplay: _restart,
                onBack: () => Navigator.of(context).pop(),
              )
            : _buildLesson(context),
      ),
    );
  }

  Widget _buildLesson(BuildContext context) {
    final strings = context.strings;
    final step = _session.currentStep!;
    final candidates = practiceActionCandidates(
      allowed: _session.allowedActions,
      selectedCardIds: _selectedCardIds,
    );
    final hand = _session.controller.handFor(_session.seat);
    final selectionMatters = _session.allowedActions.any(
      (action) => PracticeActionCandidate(action: action).usesSelection,
    );

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        LoungeTokens.space4,
        LoungeTokens.space4,
        LoungeTokens.space4,
        LoungeTokens.space6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PromptCard(
            stepLabel: strings.practiceStepLabel(
              _session.stepIndex + 1,
              _session.stepCount,
            ),
            prompt: step.prompt(strings),
            hint: step.hint?.call(strings),
            note: _stepNote?.call(strings),
            error: _errorMessage == null
                ? null
                : strings.gameMessage(_errorMessage!),
          ),
          const SizedBox(height: LoungeTokens.space5),
          _TableStrip(session: _session),
          const SizedBox(height: LoungeTokens.space5),
          _HandArea(
            hand: hand,
            selectedCardIds: _selectedCardIds,
            selectable: selectionMatters,
            onTapCard: _toggleCard,
          ),
          const SizedBox(height: LoungeTokens.space5),
          _ActionRow(
            candidates: candidates,
            selectionMatters: selectionMatters,
            hasSelection: _selectedCardIds.isNotEmpty,
            onSubmit: _submit,
          ),
        ],
      ),
    );
  }
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({
    required this.stepLabel,
    required this.prompt,
    this.hint,
    this.note,
    this.error,
  });

  final String stepLabel;
  final String prompt;
  final String? hint;
  final String? note;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(LoungeTokens.space4),
      decoration: BoxDecoration(
        color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
        border: Border.all(
          color: LoungeTokens.goldAccent.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (note != null) ...[
            Row(
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  size: 16,
                  color: LoungeTokens.goldAccent,
                ),
                const SizedBox(width: LoungeTokens.space2),
                Expanded(
                  child: Text(
                    note!,
                    style: LoungeTokens.bodyMuted.copyWith(
                      color: LoungeTokens.goldAccent,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: LoungeTokens.space3),
          ],
          Text(
            stepLabel,
            style: LoungeTokens.bodyMuted.copyWith(
              fontSize: 12,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: LoungeTokens.space2),
          Text(prompt, style: LoungeTokens.body.copyWith(height: 1.4)),
          if (hint != null) ...[
            const SizedBox(height: LoungeTokens.space2),
            Text(
              hint!,
              style: LoungeTokens.bodyMuted.copyWith(fontSize: 13),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: LoungeTokens.space3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 16,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: LoungeTokens.space2),
                Expanded(
                  child: Text(
                    error!,
                    style: LoungeTokens.bodyMuted.copyWith(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Compact stock + discard strip: just enough table for the lesson.
class _TableStrip extends StatelessWidget {
  const _TableStrip({required this.session});

  final PracticeSession session;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = CardThemeScope.of(context);
    final controller = session.controller;
    final topDiscard = controller.topDiscard;
    final pending = controller.pendingDiscard;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LabeledPile(
          label: '${strings.stock} (${controller.stockCount})',
          child: const _StockBack(),
        ),
        const SizedBox(width: LoungeTokens.space6),
        _LabeledPile(
          label: strings.discard,
          child: topDiscard == null
              ? const _EmptyCardSlot()
              : HareegCardView(
                  theme: theme,
                  card: topDiscard,
                  size: _cardSize,
                ),
        ),
        if (pending != null) ...[
          const SizedBox(width: LoungeTokens.space6),
          _LabeledPile(
            label: strings.pendingDiscard,
            child: HareegCardView(
              theme: theme,
              card: pending,
              visualState: CardVisualState.pending,
              size: _cardSize,
            ),
          ),
        ],
      ],
    );
  }
}

const _cardSize = Size(56, 80);

class _LabeledPile extends StatelessWidget {
  const _LabeledPile({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        child,
        const SizedBox(height: LoungeTokens.space2),
        Text(
          label,
          style: LoungeTokens.bodyMuted.copyWith(
            fontSize: 12,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

class _StockBack extends StatelessWidget {
  const _StockBack();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _cardSize.width,
      height: _cardSize.height,
      decoration: BoxDecoration(
        color: LoungeTokens.coffeeCharcoal,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: LoungeTokens.sandLine.withValues(alpha: 0.4),
        ),
      ),
      child: Center(
        child: Icon(
          Icons.style_outlined,
          color: LoungeTokens.sandLine.withValues(alpha: 0.6),
          size: 24,
        ),
      ),
    );
  }
}

class _EmptyCardSlot extends StatelessWidget {
  const _EmptyCardSlot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _cardSize.width,
      height: _cardSize.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: LoungeTokens.sandLine.withValues(alpha: 0.25),
        ),
      ),
    );
  }
}

class _HandArea extends StatelessWidget {
  const _HandArea({
    required this.hand,
    required this.selectedCardIds,
    required this.selectable,
    required this.onTapCard,
  });

  final List<HareegCard> hand;
  final Set<String> selectedCardIds;
  final bool selectable;
  final void Function(HareegCard card) onTapCard;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = CardThemeScope.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.practiceYourHand,
          style: LoungeTokens.bodyMuted.copyWith(
            fontSize: 12,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: LoungeTokens.space3),
        Wrap(
          spacing: LoungeTokens.space2,
          runSpacing: LoungeTokens.space2,
          alignment: WrapAlignment.center,
          children: [
            for (final card in hand)
              GestureDetector(
                onTap: selectable ? () => onTapCard(card) : null,
                child: HareegCardView(
                  theme: theme,
                  card: card,
                  size: _cardSize,
                  visualState: selectedCardIds.contains(card.id)
                      ? CardVisualState.selected
                      : CardVisualState.normal,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.candidates,
    required this.selectionMatters,
    required this.hasSelection,
    required this.onSubmit,
  });

  final List<PracticeActionCandidate> candidates;
  final bool selectionMatters;
  final bool hasSelection;
  final void Function(PracticeActionCandidate candidate) onSubmit;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    if (candidates.isEmpty) {
      // Card-bearing steps offer no button until the selection matches a
      // legal action; nudge the player toward selecting.
      return Text(
        selectionMatters && !hasSelection
            ? strings.practiceSelectHint
            : '',
        textAlign: TextAlign.center,
        style: LoungeTokens.bodyMuted.copyWith(fontSize: 13),
      );
    }
    return Wrap(
      spacing: LoungeTokens.space3,
      runSpacing: LoungeTokens.space2,
      alignment: WrapAlignment.center,
      children: [
        for (final candidate in candidates)
          FilledButton(
            onPressed: () => onSubmit(candidate),
            style: FilledButton.styleFrom(
              // The theme minimum is full-width; hug the label.
              minimumSize: const Size(0, LoungeTokens.tapTargetPrimary),
            ),
            child: Text(_label(strings, candidate)),
          ),
      ],
    );
  }

  String _label(AppStrings strings, PracticeActionCandidate candidate) {
    return switch (candidate.action.kind) {
      ClassicHareegActionKind.drawStock => strings.drawStock,
      ClassicHareegActionKind.takeDiscard => strings.takeDiscard,
      ClassicHareegActionKind.usePendingDiscard => strings.practiceUseDiscard,
      ClassicHareegActionKind.returnPendingDiscard => strings.returnDiscard,
      ClassicHareegActionKind.returnOpeningMelds => strings.takeBackMelds,
      ClassicHareegActionKind.claimFifty => strings.claimFifty,
      ClassicHareegActionKind.discard ||
      ClassicHareegActionKind.discardBlockedCover ||
      ClassicHareegActionKind.discardJoker => strings.discardCard,
      ClassicHareegActionKind.playMeld ||
      ClassicHareegActionKind.playMeldWithJoker => strings.playMeld,
      ClassicHareegActionKind.placeCover => strings.placeCover,
      ClassicHareegActionKind.replaceJoker => strings.replaceJoker,
      ClassicHareegActionKind.returnTablePlay ||
      ClassicHareegActionKind.unknown => candidate.actionId,
    };
  }
}

class _CompletionPanel extends StatelessWidget {
  const _CompletionPanel({required this.onReplay, required this.onBack});

  final VoidCallback onReplay;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Center(
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.all(LoungeTokens.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.check_circle_outline,
              size: 64,
              color: LoungeTokens.goldAccent,
            ),
            const SizedBox(height: LoungeTokens.space4),
            Text(
              strings.practiceLessonCompleteTitle,
              textAlign: TextAlign.center,
              style: LoungeTokens.display,
            ),
            const SizedBox(height: LoungeTokens.space3),
            Text(
              strings.practiceLessonCompleteBody,
              textAlign: TextAlign.center,
              style: LoungeTokens.bodyMuted,
            ),
            const SizedBox(height: LoungeTokens.space6),
            FilledButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.checklist_outlined),
              label: Text(strings.practiceBackToList),
            ),
            const SizedBox(height: LoungeTokens.space3),
            OutlinedButton.icon(
              onPressed: onReplay,
              icon: const Icon(Icons.replay_outlined),
              label: Text(strings.practiceReplayLesson),
              style: OutlinedButton.styleFrom(
                foregroundColor: LoungeTokens.goldAccent,
                side: BorderSide(
                  color: LoungeTokens.goldAccent.withValues(alpha: 0.6),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
