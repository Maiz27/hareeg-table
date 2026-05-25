import 'dart:async';

import 'package:flutter/foundation.dart';

import 'joker_cue_queue.dart';

/// A typed feedback message published to the south-side feedback chip.
@immutable
class TableFeedbackMessage {
  /// Creates a feedback message.
  const TableFeedbackMessage({required this.text, required this.isError});

  /// Localised message text already resolved by the caller.
  final String text;

  /// Whether the chip should render in the error palette.
  final bool isError;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TableFeedbackMessage &&
        other.text == text &&
        other.isError == isError;
  }

  @override
  int get hashCode => Object.hash(text, isError);
}

/// Centralised owner of every "schedule a cue, then rebuild" mechanism the
/// table screen had previously inlined as ad-hoc `Timer` / `addListener` /
/// `setState` wires.
///
/// The screen used to manage eight independent cue surfaces:
///
/// 1. Joker declaration FIFO ([JokerCueQueue])
/// 2. Human feedback chip (success / error / hint) with a dismissal [Timer]
/// 3. Strict-tier revert-flash card highlight with its own [Timer]
/// 4. Fifty-claim countdown ticker (a `Timer.periodic`)
/// 5. Round-advance timer (post-round overlay dwell before pushing match-over
///    or advancing the next round)
/// 6. Fifty pulse one-shot flash
/// 7. Deal-choreography progress listener
/// 8. Meld-flight controller listener
///
/// Each of those used to call `setState` independently, racing with the others
/// and making the cue lifecycles untestable without rendering the full screen.
///
/// [TableCueChoreographer] folds them into a single [ChangeNotifier]. Callers
/// enqueue typed intents (`replaceFeedback`, `scheduleRevertFlash`,
/// `enqueueJokerCues`, ...) and listen to the choreographer for repaint
/// signals; the screen only needs to wire `choreographer.addListener(setState)`
/// once and consume the public state getters.
///
/// The L0 test seam is the choreographer itself: tests can enqueue intents and
/// step `fake_async` to assert dwell semantics without spinning up Flutter.
class TableCueChoreographer extends ChangeNotifier {
  /// Creates a choreographer.
  ///
  /// - [jokerDwellFor] returns the dwell window for a joker cue. It is looked
  ///   up per cue so callers can scale by the live motion preference. The
  ///   type parameter is intentionally [Object] so the choreographer doesn't
  ///   need to know the joker cue's record shape — the screen plugs its own
  ///   `({PlayerSeat, CardIdentity})` records through.
  /// - [onJokerCueStart] / [onJokerCueEnd] are the side-effects to run when
  ///   the queue activates / withdraws a cue (publish / withdraw the message,
  ///   play a sound, etc.). They fire *inside* the choreographer's notify
  ///   batch so listeners see a single rebuild.
  /// - [isMounted] is consulted before notifying — gates the per-tick
  ///   `Timer.periodic` (fifty ticker) when the screen has been torn down.
  TableCueChoreographer({
    required Duration Function(Object cue) jokerDwellFor,
    required void Function(Object cue) onJokerCueStart,
    required void Function(Object cue) onJokerCueEnd,
    required bool Function() isMounted,
  })  : _isMounted = isMounted,
        _onJokerCueStart = onJokerCueStart,
        _onJokerCueEnd = onJokerCueEnd {
    _jokerQueue = JokerCueQueue<Object>(
      onCueStart: _handleJokerCueStart,
      onCueEnd: _handleJokerCueEnd,
      dwellFor: jokerDwellFor,
    );
  }

  final bool Function() _isMounted;
  final void Function(Object cue) _onJokerCueStart;
  final void Function(Object cue) _onJokerCueEnd;

  late final JokerCueQueue<Object> _jokerQueue;

  // --- Human feedback chip -------------------------------------------------
  TableFeedbackMessage? _feedback;
  Timer? _feedbackTimer;

  /// Currently displayed feedback message, or `null` when idle.
  TableFeedbackMessage? get feedback => _feedback;

  // --- Revert flash --------------------------------------------------------
  String? _revertFlashCardId;
  Timer? _revertFlashTimer;

  /// Card id currently being pulsed by the Strict-tier revert flash, or
  /// `null` when no flash is active.
  String? get revertFlashCardId => _revertFlashCardId;

  // --- Round advance -------------------------------------------------------
  Timer? _roundAdvanceTimer;

  /// True while a round-advance timer is pending. Exposed for tests and for
  /// callers that need to know whether the post-round overlay dwell is still
  /// running.
  bool get hasPendingRoundAdvance => _roundAdvanceTimer != null;

  // --- Fifty ticker --------------------------------------------------------
  Timer? _fiftyTicker;

  /// True while the fifty-countdown ticker is firing.
  bool get isFiftyTickerActive => _fiftyTicker != null;

  // --- Fifty pulse ---------------------------------------------------------
  bool _fiftyPulse = false;
  Timer? _fiftyPulseTimer;

  /// Whether the fifty button is currently in its post-claim pulse window.
  bool get fiftyPulse => _fiftyPulse;

  // --- Joker queue access (read-only) --------------------------------------
  /// True while a joker cue is in its dwell window.
  bool get isJokerCueActive => _jokerQueue.isActive;

  /// Pending joker cues queued behind the active one.
  int get pendingJokerCueCount => _jokerQueue.pendingCount;

  // -------------------------------------------------------------------------
  // Joker cues
  // -------------------------------------------------------------------------

  /// Appends [cues] to the joker FIFO and pumps it. The first newly appended
  /// cue starts immediately if the queue is idle.
  void enqueueJokerCues(Iterable<Object> cues) {
    _jokerQueue.enqueueAll(cues);
    // The queue calls _handleJokerCueStart synchronously inside enqueueAll
    // for the first cue when idle, which already notifies. If nothing was
    // pumped (queue was busy), no listener-visible state changed so we
    // intentionally skip notifying here.
  }

  void _handleJokerCueStart(Object cue) {
    _onJokerCueStart(cue);
    _notifyIfMounted();
  }

  void _handleJokerCueEnd(Object cue) {
    _onJokerCueEnd(cue);
    _notifyIfMounted();
  }

  /// Drains every pending joker cue and cancels the active dwell timer
  /// without firing the active cue's end callback. Mirrors the legacy
  /// `_jokerCueQueue.clear()` semantics — callers withdraw any active
  /// message themselves (typically by replacing the feedback line).
  void clearJokerCues() {
    if (!_jokerQueue.isActive && _jokerQueue.pendingCount == 0) return;
    _jokerQueue.clear();
    _notifyIfMounted();
  }

  // -------------------------------------------------------------------------
  // Feedback chip
  // -------------------------------------------------------------------------

  /// Replaces the feedback chip with [message] (or clears it when `null`)
  /// and schedules its [autoDismissAfter] dwell. Cancels any in-flight
  /// dismissal. Returning to the joker queue: any non-joker feedback drops
  /// the queue so a stale declaration can't pop on top.
  void replaceFeedback(
    TableFeedbackMessage? message, {
    required Duration autoDismissAfter,
  }) {
    _feedbackTimer?.cancel();
    _feedbackTimer = null;
    // Any new feedback supersedes pending joker declarations.
    _jokerQueue.clear();
    _feedback = message;
    if (message == null) {
      _notifyIfMounted();
      return;
    }
    if (autoDismissAfter > Duration.zero) {
      _feedbackTimer = Timer(autoDismissAfter, () {
        // Defensive: only withdraw if this exact message is still on screen.
        if (_feedback == message) {
          _feedback = null;
          _notifyIfMounted();
        } else {
          _feedbackTimer = null;
        }
      });
    }
    _notifyIfMounted();
  }

  /// Sets the feedback chip without scheduling an auto-dismiss. Used by the
  /// joker-cue start callback which manages its own dwell via the FIFO.
  void setFeedbackUnmanaged(TableFeedbackMessage? message) {
    _feedbackTimer?.cancel();
    _feedbackTimer = null;
    _feedback = message;
    _notifyIfMounted();
  }

  /// Withdraws [message] if it is still the active feedback line. Used by
  /// the joker cue end callback so each cue clears the line only when its
  /// own message is still on screen.
  void withdrawFeedbackIf(TableFeedbackMessage message) {
    if (_feedback == message) {
      _feedback = null;
      _notifyIfMounted();
    }
  }

  // -------------------------------------------------------------------------
  // Revert flash
  // -------------------------------------------------------------------------

  /// Pulses [cardId] for [dwell] then clears the flash. Cancels any pending
  /// flash. Passing `null` clears immediately.
  void scheduleRevertFlash(String? cardId, {required Duration dwell}) {
    _revertFlashTimer?.cancel();
    _revertFlashTimer = null;
    _revertFlashCardId = cardId;
    if (cardId == null) {
      _notifyIfMounted();
      return;
    }
    _revertFlashTimer = Timer(dwell, () {
      if (_revertFlashCardId == cardId) {
        _revertFlashCardId = null;
        _notifyIfMounted();
      } else {
        _revertFlashTimer = null;
      }
    });
    _notifyIfMounted();
  }

  // -------------------------------------------------------------------------
  // Round advance
  // -------------------------------------------------------------------------

  /// Schedules [callback] to fire after [delay]. Cancels any previously
  /// scheduled round-advance. The choreographer never `setState`s for the
  /// caller — [callback] should do whatever rebuild it needs.
  void scheduleRoundAdvance(Duration delay, void Function() callback) {
    _roundAdvanceTimer?.cancel();
    _roundAdvanceTimer = Timer(delay, () {
      _roundAdvanceTimer = null;
      callback();
    });
  }

  /// Cancels any pending round-advance without firing the callback.
  void cancelRoundAdvance() {
    if (_roundAdvanceTimer == null) return;
    _roundAdvanceTimer?.cancel();
    _roundAdvanceTimer = null;
  }

  // -------------------------------------------------------------------------
  // Fifty ticker
  // -------------------------------------------------------------------------

  /// Starts a periodic ticker that calls [onTick] every [period]. While the
  /// ticker is running it also notifies the choreographer's listeners on
  /// every tick so the host widget can rebuild against the live countdown.
  /// If a ticker is already active, this is a no-op.
  void startFiftyTicker({
    required Duration period,
    required void Function() onTick,
  }) {
    if (_fiftyTicker != null) return;
    _fiftyTicker = Timer.periodic(period, (_) {
      onTick();
      _notifyIfMounted();
    });
  }

  /// Stops the periodic ticker.
  void stopFiftyTicker() {
    if (_fiftyTicker == null) return;
    _fiftyTicker?.cancel();
    _fiftyTicker = null;
  }

  // -------------------------------------------------------------------------
  // Fifty pulse
  // -------------------------------------------------------------------------

  /// Flashes the fifty-claim button for [dwell] then clears the pulse flag.
  void scheduleFiftyPulse({required Duration dwell}) {
    _fiftyPulseTimer?.cancel();
    _fiftyPulse = true;
    _fiftyPulseTimer = Timer(dwell, () {
      _fiftyPulse = false;
      _fiftyPulseTimer = null;
      _notifyIfMounted();
    });
    _notifyIfMounted();
  }

  // -------------------------------------------------------------------------
  // Bulk reset / dispose
  // -------------------------------------------------------------------------

  /// Cancels every timer and clears every queued cue. Used on round advance
  /// and fast-forward, where the legacy code drained each cue mechanism
  /// inline. Does NOT notify — callers wrap this in a broader setState that
  /// already triggers a rebuild.
  void resetAll() {
    _feedbackTimer?.cancel();
    _feedbackTimer = null;
    _revertFlashTimer?.cancel();
    _revertFlashTimer = null;
    _roundAdvanceTimer?.cancel();
    _roundAdvanceTimer = null;
    _fiftyPulseTimer?.cancel();
    _fiftyPulseTimer = null;
    _fiftyPulse = false;
    _feedback = null;
    _revertFlashCardId = null;
    _jokerQueue.clear();
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _feedbackTimer = null;
    _revertFlashTimer?.cancel();
    _revertFlashTimer = null;
    _roundAdvanceTimer?.cancel();
    _roundAdvanceTimer = null;
    _fiftyTicker?.cancel();
    _fiftyTicker = null;
    _fiftyPulseTimer?.cancel();
    _fiftyPulseTimer = null;
    _jokerQueue.clear();
    super.dispose();
  }

  void _notifyIfMounted() {
    if (!_isMounted()) return;
    notifyListeners();
  }
}
