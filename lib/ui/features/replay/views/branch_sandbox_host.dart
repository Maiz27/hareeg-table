import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../cpu/classic_hareeg/cpu_strategy.dart';
import '../../../../data/persistence/preferences_repository.dart';
import '../../../../domain/classic_hareeg/replay/replay_branch_session.dart';
import '../../../../domain/classic_hareeg/replay/replay_reconstruction.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/panels/lounge_panel.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../../game_table/table_session_config.dart';
import '../../game_table/views/game_table_screen.dart';

/// Hosts one branch sandbox over the real table.
///
/// Everything a sandbox owns that the table does not lives here: the
/// [ReplayBranchSession] (divergence, the session-only coach, restart), the
/// exit confirmation, and the single decision about when to leave. The table
/// itself gets a [TableSessionConfig.branch] and no repository of any kind, so
/// there is nothing here that could reach durable storage even by mistake.
///
/// Pushed with the seed already in hand rather than through a named route: a
/// route argument would have to carry a reconstructed frame through
/// `Object?`, and the one caller that can produce one is the replay screen
/// directly above it.
class BranchSandboxHost extends StatefulWidget {
  /// Creates a sandbox host for [frame].
  const BranchSandboxHost({
    required this.frame,
    required this.nextFrame,
    required this.visibility,
    required this.coachEligible,
    required this.preferences,
    super.key,
    this.clock,
    this.onAppliedAction,
  });

  /// Replay frame the sandbox branches from.
  final ReplayFrame frame;

  /// The timeline position after [frame], or null at the end of the recording.
  ///
  /// A branch taken at a round end starts from this frame's deal instead, so
  /// the sandbox never reopens a round that was already scored.
  final ReplayFrame? nextFrame;

  /// Blind or full-visibility, chosen at entry.
  final BranchVisibility visibility;

  /// Whether the archived match had coaching available. The **only**
  /// eligibility source.
  final bool coachEligible;

  /// Presentation preferences the table reads. Never written back: a sandbox
  /// has no route to a preferences store at all.
  final GamePreferences preferences;

  /// Clock the sandbox runs on, or null for the wall clock.
  final DateTime Function()? clock;

  /// Observes every action that applies in this sandbox, or null.
  ///
  /// Null in the app, exactly like [clock]. The host itself only needs to know
  /// *that* something applied, which it takes from the same callback; this
  /// forwards the full record — actor, exact action id, apply result, the
  /// complete resulting state, and for a CPU action its tier and the sorted
  /// legal set it was offered — so a test can compare two visibility runs as
  /// one ordered successful-apply stream. It replaces an earlier strategy
  /// seam that could only see what a CPU *intended*, before success was known.
  final ValueChanged<TableAppliedAction>? onAppliedAction;

  @override
  State<BranchSandboxHost> createState() => _BranchSandboxHostState();
}

class _BranchSandboxHostState extends State<BranchSandboxHost> {
  late ReplayBranchSession _session = _startSession();

  /// Bumped on restart so the table is rebuilt from scratch rather than
  /// updated in place. A restart has to re-deal from the branch point, and a
  /// [GameTableScreen] that kept its state would carry the abandoned run's
  /// controller, cues and flights into the new one.
  int _generation = 0;

  bool _leaving = false;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  ReplayBranchSession _startSession() {
    final session = ReplayBranchSession.start(
      frame: widget.frame,
      nextFrame: widget.nextFrame,
      coachEligible: widget.coachEligible,
      branchStart: _now(),
    );
    if (session == null) {
      // The caller refuses a decided frame before it ever gets here, so this
      // is a programming error rather than a state to degrade around.
      throw StateError(
        'Cannot branch from a frame the match was already decided at.',
      );
    }
    return session;
  }

  void _restart() {
    setState(() {
      _session = _session.restart(branchStart: _now());
      _generation += 1;
    });
  }

  /// The one exit policy, for all four routes.
  ///
  /// Pause-leave, the in-app control, Android system Back and browser Back all
  /// arrive here through [GameTableScreen.onSandboxExit], so "confirm only
  /// after divergence" is decided once rather than four times.
  Future<void> _requestExit() async {
    if (_leaving) {
      return;
    }
    if (!_session.hasDiverged) {
      _pop();
      return;
    }
    _leaving = true;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: LoungeTokens.overlayScrim,
      builder: (context) => const _BranchExitConfirmation(),
    );
    _leaving = false;
    if (!mounted || confirmed != true) {
      return;
    }
    _pop();
  }

  void _pop() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GameTableScreen(
      // Keyed on the run, not the widget: a restart must rebuild the table
      // from the seed rather than reuse the abandoned run's state.
      key: ValueKey('branch-sandbox-$_generation'),
      setup: _session.seed.snapshot.setup,
      session: TableSessionConfig.branch(
        seed: _session.seed,
        visibility: widget.visibility,
        coachEligible: _session.coachEligible,
      ),
      preferences: widget.preferences,
      cpuStrategy: const ClassicHareegCpuStrategy(),
      // A sandbox cannot change a stored preference. There is no control on
      // the surface that calls this, and this is the backstop that says so in
      // one place instead of at every row.
      onPreferencesChanged: (_) {},
      clock: widget.clock,
      onSandboxActionApplied: (applied) {
        widget.onAppliedAction?.call(applied);
        if (_session.hasDiverged) {
          return;
        }
        setState(_session.recordAppliedAction);
      },
      onSandboxExit: () => unawaited(_requestExit()),
      onSandboxRestart: _restart,
      sandboxCoachEnabled: _session.coachEnabled,
      onSandboxCoachToggled: _session.coachEligible
          ? (value) => setState(() => _session.setCoachEnabled(value))
          : null,
    );
  }
}

/// Confirms discarding a diverged sandbox.
class _BranchExitConfirmation extends StatelessWidget {
  const _BranchExitConfirmation();

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(LoungeTokens.space4),
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
                  icon: Icons.logout_rounded,
                  title: strings.branchExitTitle,
                  subtitle: strings.branchSandboxBadge,
                  onClose: () => Navigator.of(context).pop(false),
                  // The app's own string, not MaterialLocalizations': the
                  // shell ships no Material localization delegate for Arabic,
                  // so that route reads "Close" in an Arabic sandbox.
                  closeTooltip: strings.close,
                ),
                const SizedBox(height: LoungeTokens.space4),
                Text(strings.branchExitBody, style: LoungeTokens.bodyMuted),
                const SizedBox(height: LoungeTokens.space5),
                LoungePanelActions(
                  primary: LoungePanelAction(
                    icon: Icons.play_arrow_rounded,
                    label: strings.branchExitCancel,
                    tooltip: strings.branchExitCancel,
                    tone: LoungePanelActionTone.primary,
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                  secondary: LoungePanelAction(
                    icon: Icons.delete_outline_rounded,
                    label: strings.branchExitConfirm,
                    tooltip: strings.branchExitConfirm,
                    tone: LoungePanelActionTone.danger,
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
