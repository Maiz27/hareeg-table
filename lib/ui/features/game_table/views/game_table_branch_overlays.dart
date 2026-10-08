part of 'game_table_screen.dart';

// Panels a branch sandbox shows instead of the live table's own overlays.

/// Pause panel for a branch sandbox.
///
/// Deliberately not [PauseOverlay] with rows switched off. Every settings row
/// on the live panel is an `onPreferencesChanged` call, and a sandbox must not
/// be able to write a preference at all — so the panel that could is never
/// built. What is left is what a sandbox actually offers: resume, the
/// session-only coach, a restart from the branch point, and the way out.
class _BranchPauseOverlay extends StatelessWidget {
  const _BranchPauseOverlay({
    required this.onResume,
    required this.onRestart,
    required this.onLeave,
    required this.coachEnabled,
    this.onCoachChanged,
  });

  final VoidCallback onResume;
  final VoidCallback onRestart;
  final VoidCallback onLeave;
  final bool coachEnabled;

  /// Null when the archived match had no coaching, which is what makes the
  /// toggle **absent** rather than present-and-off: a player who was never
  /// eligible has nothing to switch on.
  final ValueChanged<bool>? onCoachChanged;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final coach = onCoachChanged;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onResume,
      child: ColoredBox(
        color: LoungeTokens.overlayScrim,
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: SingleChildScrollView(
                child: LoungePanel(
                  highContrast: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LoungePanelHeader(
                        icon: Icons.science_outlined,
                        title: strings.branchPauseTitle,
                        subtitle: strings.branchSandboxBadge,
                        onClose: onResume,
                        closeTooltip: strings.close,
                      ),
                      if (coach != null) ...[
                        const SizedBox(height: LoungeTokens.space4),
                        MergeSemantics(
                          child: Tooltip(
                            message: strings.branchCoachToggle,
                            // Pointer affordance only: the switch's own title
                            // already names it, and web renders a node's
                            // tooltip as a second copy of its label.
                            excludeFromSemantics: true,
                            child: Material(
                              type: MaterialType.transparency,
                              child: SwitchListTile.adaptive(
                                key: const ValueKey('branch-coach-toggle'),
                                contentPadding: EdgeInsets.zero,
                                value: coachEnabled,
                                onChanged: coach,
                                title: Text(
                                  strings.branchCoachToggle,
                                  style: LoungeTokens.bodyMuted,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: LoungeTokens.space5),
                      LoungePanelActions(
                        primary: LoungePanelAction(
                          icon: Icons.play_arrow_rounded,
                          label: strings.branchResume,
                          tooltip: strings.branchResume,
                          tone: LoungePanelActionTone.primary,
                          onTap: onResume,
                        ),
                        secondary: LoungePanelAction(
                          icon: Icons.logout_rounded,
                          label: strings.branchExitSandbox,
                          tooltip: strings.branchExitSandbox,
                          tone: LoungePanelActionTone.danger,
                          onTap: onLeave,
                        ),
                        tertiary: LoungePanelAction(
                          icon: Icons.restart_alt_rounded,
                          label: strings.branchRestart,
                          tooltip: strings.branchRestart,
                          tone: LoungePanelActionTone.neutral,
                          onTap: onRestart,
                        ),
                      ),
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

/// Completion panel for a finished branch sandbox.
///
/// Exactly two ways out, because those are the only two that make sense for a
/// game that never happened. The live [MatchOverOverlay]'s rematch would deal
/// a fresh **real** match and its export would hand out a report for an
/// experiment, so that surface is not built here rather than built with two
/// buttons greyed out.
class _BranchCompletionOverlay extends StatelessWidget {
  const _BranchCompletionOverlay({
    required this.progress,
    required this.roundsPlayed,
    required this.highContrast,
    required this.onReturnToReplay,
    required this.onRestart,
  });

  final MatchProgressState progress;
  final int roundsPlayed;
  final bool highContrast;
  final VoidCallback onReturnToReplay;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final winner = progress.matchWinner;
    return ColoredBox(
      color: LoungeTokens.overlayScrim,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: LoungePanel(
              highContrast: highContrast,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LoungePanelHeader(
                    icon: Icons.science_outlined,
                    title: strings.branchCompletionTitle,
                    subtitle: winner == null
                        ? strings.branchSandboxBadge
                        : '${strings.replayWinnerLabel}: '
                              '${strings.seatLabel(winner)}',
                    // No close button, deliberately. B51 makes the completion
                    // panel's action list exhaustive at two, and a header
                    // close that returned to the replay would be a third
                    // control publishing a duplicate of one of them.
                    onClose: null,
                    closeTooltip: null,
                  ),
                  const SizedBox(height: LoungeTokens.space4),
                  Text(
                    strings.branchCompletionBody,
                    style: LoungeTokens.bodyMuted,
                  ),
                  const SizedBox(height: LoungeTokens.space3),
                  Text(
                    strings.roundsPlayed(roundsPlayed),
                    style: LoungeTokens.bodyMuted,
                  ),
                  const SizedBox(height: LoungeTokens.space5),
                  LoungePanelActions(
                    primary: LoungePanelAction(
                      icon: Icons.movie_outlined,
                      label: strings.branchReturnToReplay,
                      tooltip: strings.branchReturnToReplay,
                      tone: LoungePanelActionTone.primary,
                      onTap: onReturnToReplay,
                    ),
                    secondary: LoungePanelAction(
                      icon: Icons.restart_alt_rounded,
                      label: strings.branchRestart,
                      tooltip: strings.branchRestart,
                      tone: LoungePanelActionTone.neutral,
                      onTap: onRestart,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Read-only expanded view of one revealed opponent hand, in study mode.
///
/// Viewing only: it carries no action affordance of any kind, and the seat it
/// shows is not South, so nothing here can make an opponent hand playable.
class _StudyHandOverlay extends StatelessWidget {
  const _StudyHandOverlay({
    required this.seat,
    required this.cards,
    required this.theme,
    required this.onClose,
  });

  final PlayerSeat seat;
  final List<HareegCard> cards;
  final HareegCardTheme theme;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onClose,
      child: ColoredBox(
        color: LoungeTokens.overlayScrim,
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: SingleChildScrollView(
                child: LoungePanel(
                  highContrast: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LoungePanelHeader(
                        icon: Icons.visibility_outlined,
                        title: strings.branchStudyHandTitle(seat),
                        subtitle: strings.branchEntryStudy,
                        onClose: onClose,
                        closeTooltip: strings.branchStudyHandClose,
                      ),
                      const SizedBox(height: LoungeTokens.space4),
                      Wrap(
                        key: const ValueKey('study-hand-cards'),
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final card in cards)
                            HareegCardView(
                              theme: theme,
                              card: card,
                              size: const Size(46, 66),
                            ),
                        ],
                      ),
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
