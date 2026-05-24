import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/ui/features/game_table/cue/joker_cue_queue.dart';

/// L0 (cue/animation queue) tests for [JokerCueQueue].
///
/// Targets the regression from commits f5db30d (`fix(ui): clear joker cue
/// queue on round advance`) and 63bfa56 (`fix(audio): stagger startup
/// warmup and add joker / meld cue events`): consecutive joker placements
/// must each get their own dwell window rather than rushing the queue and
/// collapsing into a single flash.
///
/// Uses `fake_async` so the dwell timer fires deterministically and the
/// whole suite finishes in microseconds instead of waiting on real
/// wall-clock seconds.
void main() {
  group('JokerCueQueue', () {
    const dwell = Duration(seconds: 1);

    test(
      'two cues enqueued back-to-back each get their full dwell time',
      () {
        // Original bug: when two jokers landed in the same frame the
        // second cue stomped the first immediately. Assert the second cue
        // only starts after the first cue's dwell elapses, and only ends
        // after another full dwell on top of that.
        fakeAsync((async) {
          final started = <String>[];
          final ended = <String>[];
          final queue = JokerCueQueue<String>(
            onCueStart: started.add,
            onCueEnd: ended.add,
            dwellFor: (_) => dwell,
          );

          queue.enqueueAll(const ['first', 'second']);

          // Both cues enqueued; only the first one starts immediately.
          expect(started, ['first']);
          expect(ended, isEmpty);
          expect(queue.active, 'first');
          expect(queue.pendingCount, 1);

          // Step just shy of the first dwell. The first cue still owns
          // the line; the second has not started.
          async.elapse(dwell - const Duration(milliseconds: 1));
          expect(started, ['first']);
          expect(ended, isEmpty);

          // First dwell elapses: end fires for 'first', start fires for
          // 'second' inside the same tick. Order matters — the bug was
          // that 'second' started before 'first' got any dwell at all.
          async.elapse(const Duration(milliseconds: 1));
          expect(ended, ['first']);
          expect(started, ['first', 'second']);
          expect(queue.active, 'second');
          expect(queue.pendingCount, 0);

          // Second cue must also get a full dwell, not a truncated one.
          async.elapse(dwell - const Duration(milliseconds: 1));
          expect(ended, ['first']);
          async.elapse(const Duration(milliseconds: 1));
          expect(ended, ['first', 'second']);
          expect(queue.isActive, isFalse);
        });
      },
    );

    test(
      'clear() drops pending cues without firing onCueEnd',
      () {
        // Round advance / replaceHumanFeedback semantics: the prior
        // round's queued declarations must vanish silently so the
        // freshly dealt hand never sees a stale chip pop. onCueEnd must
        // not fire for the active cue (the caller is responsible for
        // withdrawing the message in the same setState).
        fakeAsync((async) {
          final started = <String>[];
          final ended = <String>[];
          final queue = JokerCueQueue<String>(
            onCueStart: started.add,
            onCueEnd: ended.add,
            dwellFor: (_) => dwell,
          );

          queue.enqueueAll(const ['a', 'b', 'c']);
          expect(started, ['a']);
          expect(queue.pendingCount, 2);

          queue.clear();
          expect(queue.isActive, isFalse);
          expect(queue.pendingCount, 0);
          expect(queue.active, isNull);

          // Run far past every conceivable dwell; nothing must fire.
          async.elapse(dwell * 10);
          expect(started, ['a']);
          expect(ended, isEmpty);
        });
      },
    );

    test(
      'a third cue enqueued mid-dwell waits until the active cue finishes',
      () {
        // Defends against the subtler half of the same bug: even when
        // cues arrive on separate frames (e.g. a CPU move enqueues one,
        // then the human's follow-up move enqueues another while the
        // first is still on screen), the new cue must not interrupt the
        // active dwell. It joins the tail of the FIFO and waits.
        fakeAsync((async) {
          final started = <String>[];
          final ended = <String>[];
          final queue = JokerCueQueue<String>(
            onCueStart: started.add,
            onCueEnd: ended.add,
            dwellFor: (_) => dwell,
          );

          queue.enqueue('first');
          expect(started, ['first']);

          // Halfway through the first cue's dwell, enqueue a third cue.
          async.elapse(const Duration(milliseconds: 500));
          queue.enqueue('third');
          expect(
            started,
            ['first'],
            reason: '"third" must not start while "first" is still active',
          );
          expect(queue.active, 'first');
          expect(queue.pendingCount, 1);
          expect(queue.pending, ['third']);

          // First dwell elapses — first ends, third begins.
          async.elapse(const Duration(milliseconds: 500));
          expect(ended, ['first']);
          expect(started, ['first', 'third']);
          expect(queue.active, 'third');

          // Third gets its own full dwell, not a truncated one.
          async.elapse(dwell);
          expect(ended, ['first', 'third']);
          expect(queue.isActive, isFalse);
        });
      },
    );
  });
}
