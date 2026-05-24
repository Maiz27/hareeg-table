import 'dart:async';

/// A FIFO of "cue" items where each item is shown for its own dwell window
/// before the next one starts. Pulled out of [GameTableScreen] so the dwell
/// + clear semantics can be exercised by unit tests.
///
/// Originally introduced for joker declaration chips: when two melds land
/// back-to-back (a CPU planner can play several sets in one turn) both
/// declarations should be visible in order, not collapsed into a single
/// flash. Cues that arrive while one is active are appended and pumped when
/// the active cue's dwell expires.
///
/// The queue does not know how to render the cue — callers supply
/// [onCueStart] (fired synchronously when the cue becomes active so the
/// caller can publish the message / play a sound) and [onCueEnd] (fired when
/// the dwell window expires so the caller can withdraw the message). The
/// queue owns only the FIFO + active-flag + dwell [Timer].
class JokerCueQueue<T> {
  /// Builds an empty queue.
  ///
  /// - [onCueStart] runs synchronously when a queued cue becomes the active
  ///   one. Use it to publish the cue (set state, play a sound).
  /// - [onCueEnd] runs when the cue's dwell timer fires (or never, if the
  ///   queue is [clear]ed first). Use it to withdraw the cue.
  /// - [dwellFor] returns the dwell duration for a given cue. Looked up per
  ///   cue so callers can scale by the current motion preference.
  JokerCueQueue({
    required void Function(T cue) onCueStart,
    required void Function(T cue) onCueEnd,
    required Duration Function(T cue) dwellFor,
  })  : _onCueStart = onCueStart,
        _onCueEnd = onCueEnd,
        _dwellFor = dwellFor;

  final void Function(T cue) _onCueStart;
  final void Function(T cue) _onCueEnd;
  final Duration Function(T cue) _dwellFor;

  final List<T> _pending = <T>[];
  T? _active;
  Timer? _dwellTimer;

  /// Whether a cue is currently in its dwell window.
  bool get isActive => _active != null;

  /// Number of cues waiting behind the active one (does not count the active
  /// cue itself).
  int get pendingCount => _pending.length;

  /// Cues queued behind the active one, in the order they will fire.
  List<T> get pending => List<T>.unmodifiable(_pending);

  /// The currently displayed cue, or `null` when the queue is idle.
  T? get active => _active;

  /// Appends [cues] to the pending list and pumps the queue. If nothing is
  /// active, the first newly appended cue starts immediately.
  void enqueueAll(Iterable<T> cues) {
    final list = cues.toList(growable: false);
    if (list.isEmpty) return;
    _pending.addAll(list);
    _pumpIfIdle();
  }

  /// Single-cue convenience for [enqueueAll].
  void enqueue(T cue) => enqueueAll(<T>[cue]);

  /// Drops every pending cue, cancels the active dwell timer, and marks the
  /// queue idle. [onCueEnd] is NOT called for the active cue — callers that
  /// need to withdraw it should do so themselves (e.g. by clearing the
  /// message in the same `setState` that calls [clear]). This mirrors the
  /// pre-refactor behaviour where `_jokerCueQueue.clear()` /
  /// `_isJokerCueActive = false` ran inside a broader reset.
  void clear() {
    _pending.clear();
    _dwellTimer?.cancel();
    _dwellTimer = null;
    _active = null;
  }

  void _pumpIfIdle() {
    if (_active != null) return;
    if (_pending.isEmpty) return;
    final next = _pending.removeAt(0);
    _active = next;
    _onCueStart(next);
    _dwellTimer = Timer(_dwellFor(next), () => _endActive(next));
  }

  void _endActive(T expected) {
    _dwellTimer = null;
    // Defensive: a clear() between start and timer fire would have nulled
    // [_active]. Bail rather than firing onCueEnd for a withdrawn cue.
    if (!identical(_active, expected)) return;
    _active = null;
    _onCueEnd(expected);
    _pumpIfIdle();
  }
}
