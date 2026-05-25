import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/ui/features/game_table/cue/table_cue_choreographer.dart';

/// L0 tests for [TableCueChoreographer].
///
/// The choreographer is the consolidated owner of every "schedule a cue,
/// then rebuild" mechanism that used to be scattered across the
/// `_GameTableScreenState` class (feedback chip, revert flash, fifty
/// ticker, fifty pulse, round-advance, joker FIFO). These tests exercise
/// the dwell + cancel semantics without rendering Flutter so the cue
/// pipelines stay observable from L0 test layer.
///
/// Uses `fake_async` so dwell timers fire deterministically.
void main() {
  group('TableCueChoreographer', () {
    const joker = Duration(seconds: 1);
    const feedbackDwell = Duration(milliseconds: 1400);
    const revertDwell = Duration(milliseconds: 1100);

    TableCueChoreographer build({
      void Function(Object cue)? onJokerStart,
      void Function(Object cue)? onJokerEnd,
    }) {
      return TableCueChoreographer(
        jokerDwellFor: (_) => joker,
        onJokerCueStart: onJokerStart ?? (_) {},
        onJokerCueEnd: onJokerEnd ?? (_) {},
        isMounted: () => true,
      );
    }

    test(
      'feedback dismissal and joker cue serialize without overlap',
      () {
        // Two competing intents: a feedback toast and a joker cue,
        // both arriving on the same frame. The legacy code had the joker
        // start callback inline `_feedbackTimer = null` to ensure no
        // stale dwell timer dropped the joker message early; the
        // choreographer must preserve that ordering.
        fakeAsync((async) {
          final started = <String>[];
          final ended = <String>[];
          final cues = build(
            onJokerStart: (cue) {
              started.add(cue.toString());
              // Joker start callback publishes its message via
              // setFeedbackUnmanaged in real usage; mirror that.
            },
            onJokerEnd: (cue) => ended.add(cue.toString()),
          );

          // First intent: a success feedback message that will auto-dismiss.
          cues.replaceFeedback(
            const TableFeedbackMessage(text: 'success', isError: false),
            autoDismissAfter: feedbackDwell,
          );
          expect(cues.feedback?.text, 'success');

          // Second intent: a joker cue lands a beat later. The
          // choreographer's enqueueJokerCues should NOT cancel the
          // existing feedback dwell timer — that's the host's job via
          // setFeedbackUnmanaged in the start callback. But it should
          // serialize joker cues across their own dwell.
          cues.enqueueJokerCues(const ['joker-a', 'joker-b']);
          expect(started, ['joker-a']);
          expect(cues.isJokerCueActive, isTrue);
          expect(cues.pendingJokerCueCount, 1);

          // Step past joker-a's dwell; joker-a ends and joker-b starts
          // back-to-back without overlap.
          async.elapse(joker);
          expect(ended, ['joker-a']);
          expect(started, ['joker-a', 'joker-b']);
          expect(cues.isJokerCueActive, isTrue);

          // joker-b also gets a full dwell.
          async.elapse(joker - const Duration(milliseconds: 1));
          expect(ended, ['joker-a']);
          async.elapse(const Duration(milliseconds: 1));
          expect(ended, ['joker-a', 'joker-b']);
          expect(cues.isJokerCueActive, isFalse);

          cues.dispose();
        });
      },
    );

    test(
      'timer-driven intents complete: feedback auto-dismisses and revert '
      'flash clears after its dwell',
      () {
        // Confirms the two timer-driven cues (feedback and revert flash)
        // each clear their state after exactly their configured dwell.
        fakeAsync((async) {
          final cues = build();
          var rebuilds = 0;
          cues.addListener(() => rebuilds += 1);

          cues.replaceFeedback(
            const TableFeedbackMessage(text: 'hint', isError: false),
            autoDismissAfter: feedbackDwell,
          );
          cues.scheduleRevertFlash('card-7', dwell: revertDwell);
          expect(cues.feedback?.text, 'hint');
          expect(cues.revertFlashCardId, 'card-7');
          // Two intents, each notified once on schedule.
          expect(rebuilds, 2);

          // Step just short of either dwell — nothing fires.
          async.elapse(revertDwell - const Duration(milliseconds: 1));
          expect(cues.revertFlashCardId, 'card-7');
          expect(cues.feedback?.text, 'hint');

          // Revert flash clears first (shorter dwell).
          async.elapse(const Duration(milliseconds: 1));
          expect(cues.revertFlashCardId, isNull);
          expect(cues.feedback?.text, 'hint');
          expect(rebuilds, 3);

          // Feedback dismissal follows.
          async.elapse(feedbackDwell - revertDwell);
          expect(cues.feedback, isNull);
          expect(rebuilds, 4);

          cues.dispose();
        });
      },
    );

    test(
      'replaceFeedback cancels pending joker cues (legacy clear()) so a '
      'stale declaration cannot pop on top of an error toast',
      () {
        // In the legacy code, `_replaceHumanFeedback` called
        // `_jokerCueQueue.clear()` explicitly so a +N rejection or
        // hint toast would never get clobbered by a deferred joker
        // chip. The choreographer must preserve that — replacing the
        // feedback drains the joker FIFO.
        fakeAsync((async) {
          final started = <String>[];
          final ended = <String>[];
          final cues = build(
            onJokerStart: (cue) => started.add(cue.toString()),
            onJokerEnd: (cue) => ended.add(cue.toString()),
          );

          cues.enqueueJokerCues(const ['j-a', 'j-b', 'j-c']);
          expect(started, ['j-a']);
          expect(cues.pendingJokerCueCount, 2);

          // Replace the feedback (e.g. the human triggers an invalid
          // action): the queue must drop without firing any further
          // start callbacks, and onCueEnd must NOT fire for the
          // withdrawn active cue (matches legacy clear() semantics —
          // the active message is whatever replaceFeedback published).
          cues.replaceFeedback(
            const TableFeedbackMessage(text: 'rejected', isError: true),
            autoDismissAfter: feedbackDwell,
          );
          expect(cues.feedback?.text, 'rejected');
          expect(cues.feedback?.isError, isTrue);
          expect(cues.isJokerCueActive, isFalse);
          expect(cues.pendingJokerCueCount, 0);

          // Run far past every joker dwell — none of the pending cues
          // should ever pump now.
          async.elapse(joker * 5);
          expect(started, ['j-a']);
          expect(ended, isEmpty);

          cues.dispose();
        });
      },
    );

    test(
      'round-advance timer fires its callback after the configured delay',
      () {
        fakeAsync((async) {
          final cues = build();
          var fired = 0;
          cues.scheduleRoundAdvance(
            const Duration(seconds: 2),
            () => fired += 1,
          );
          expect(cues.hasPendingRoundAdvance, isTrue);
          async.elapse(const Duration(milliseconds: 1999));
          expect(fired, 0);
          async.elapse(const Duration(milliseconds: 1));
          expect(fired, 1);
          expect(cues.hasPendingRoundAdvance, isFalse);
          cues.dispose();
        });
      },
    );

    test(
      'scheduling a second round-advance cancels the first',
      () {
        // Defensive: the legacy code re-armed `_roundAdvanceTimer` from
        // multiple call-sites (humanEliminated vs. nextSnapshot path,
        // openMatchOver re-entry). The choreographer must keep at most
        // one timer alive.
        fakeAsync((async) {
          final cues = build();
          var firstFired = 0;
          var secondFired = 0;
          cues.scheduleRoundAdvance(
            const Duration(seconds: 2),
            () => firstFired += 1,
          );
          cues.scheduleRoundAdvance(
            const Duration(seconds: 5),
            () => secondFired += 1,
          );
          async.elapse(const Duration(seconds: 3));
          expect(firstFired, 0,
              reason: 'first timer should have been cancelled');
          expect(secondFired, 0);
          async.elapse(const Duration(seconds: 2));
          expect(firstFired, 0);
          expect(secondFired, 1);
          cues.dispose();
        });
      },
    );

    test(
      'fifty pulse flashes for its dwell then clears',
      () {
        fakeAsync((async) {
          final cues = build();
          cues.scheduleFiftyPulse(dwell: const Duration(milliseconds: 600));
          expect(cues.fiftyPulse, isTrue);
          async.elapse(const Duration(milliseconds: 599));
          expect(cues.fiftyPulse, isTrue);
          async.elapse(const Duration(milliseconds: 1));
          expect(cues.fiftyPulse, isFalse);
          cues.dispose();
        });
      },
    );

    test(
      'fifty ticker fires onTick on the configured period and notifies '
      'listeners',
      () {
        fakeAsync((async) {
          final cues = build();
          var ticks = 0;
          var rebuilds = 0;
          cues.addListener(() => rebuilds += 1);
          cues.startFiftyTicker(
            period: const Duration(milliseconds: 500),
            onTick: () => ticks += 1,
          );
          async.elapse(const Duration(milliseconds: 1500));
          expect(ticks, 3);
          expect(rebuilds, 3);
          cues.stopFiftyTicker();
          async.elapse(const Duration(seconds: 1));
          expect(ticks, 3, reason: 'stopped ticker must not fire again');
          cues.dispose();
        });
      },
    );

    test(
      'resetAll drains every timer and queue without firing callbacks',
      () {
        // Used by fast-forward + advanceToNextRound. The legacy code
        // cleared each surface individually; resetAll must remain
        // equivalent in side-effects (no end callbacks, no late timers).
        fakeAsync((async) {
          final cues = build(
            onJokerEnd: (_) => fail('onJokerEnd must not fire from resetAll'),
          );
          var roundAdvanced = 0;

          cues.replaceFeedback(
            const TableFeedbackMessage(text: 'm', isError: false),
            autoDismissAfter: feedbackDwell,
          );
          cues.scheduleRevertFlash('c', dwell: revertDwell);
          cues.scheduleFiftyPulse(dwell: const Duration(seconds: 1));
          cues.enqueueJokerCues(const ['j-a', 'j-b']);
          cues.scheduleRoundAdvance(
            const Duration(seconds: 3),
            () => roundAdvanced += 1,
          );
          expect(cues.feedback, isNotNull);
          expect(cues.revertFlashCardId, 'c');
          expect(cues.fiftyPulse, isTrue);
          expect(cues.isJokerCueActive, isTrue);
          expect(cues.hasPendingRoundAdvance, isTrue);

          cues.resetAll();
          expect(cues.feedback, isNull);
          expect(cues.revertFlashCardId, isNull);
          expect(cues.fiftyPulse, isFalse);
          expect(cues.isJokerCueActive, isFalse);
          expect(cues.pendingJokerCueCount, 0);
          expect(cues.hasPendingRoundAdvance, isFalse);

          // Run far past every dwell — nothing must fire.
          async.elapse(const Duration(seconds: 10));
          expect(roundAdvanced, 0);

          cues.dispose();
        });
      },
    );
  });
}
