import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';

import 'classic_hareeg_match_driver.dart';

/// No CPU, at any difficulty, takes the discard only to hand it straight back.
///
/// A taken discard must be played this turn and can never close the turn, so
/// a pickup the seat cannot keep ends in return-pending-discard and a stock
/// draw. Playtest: an opened seat down to its last cards did this every time
/// the human threw the card that completed its hand — whatever the hand size,
/// whichever planner path (the shared pickup rule or Expert's thin-stock
/// denial) made the call. Whole matches across seeds catch every route.
void main() {
  for (final difficulty in CpuDifficulty.values) {
    test('${difficulty.name}: no take-then-return across whole matches', () {
      final offenders = <String>[];
      for (var seed = 1; seed <= 12; seed++) {
        MatchStep? previous;
        ClassicHareegMatchDriver().run(
          setup: ClassicHareegSetup.defaults().copyWith(
            cpuDifficulty: difficulty,
          ),
          seed: seed,
          onStep: (step) {
            final last = previous;
            if (last != null &&
                last.seat == step.seat &&
                last.roundNumber == step.roundNumber &&
                last.actionId == ClassicHareegActionIds.takeDiscard &&
                step.actionId == ClassicHareegActionIds.returnPendingDiscard) {
              offenders.add(
                'seed $seed round ${step.roundNumber} ${step.seat.name} '
                '(hand ${last.handCounts[step.seat]})',
              );
            }
            previous = step;
          },
        );
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    }, timeout: const Timeout(Duration(minutes: 5)));
  }
}
