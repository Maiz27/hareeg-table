import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/classic_hareeg_match_report.dart';

/// Regression for the owner-reported "stuck after an invalid Fifty pickup on
/// the Table tier" bug. Rebuilds the exact exported state: south picked up a
/// Fifty it can never prove (opening requirement is 104), so no meld can be
/// laid down and the claimed card used to be unreturnable — a dead end.
///
/// The fix makes returning the claimed card the explicit give-up gesture,
/// carrying the Table penalty (+17 and out of the round), so the claimant
/// always has a discoverable exit.
void main() {
  ClassicHareegGameController build() {
    final file = File('test/fixtures/stuck_fifty_report.json');
    final report = ClassicHareegMatchReport.fromJson(
      jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
    );
    final clock = DateTime.utc(2026, 1, 1);
    return ClassicHareegGameController.fromSnapshot(
      report.snapshot,
      now: () => clock,
    );
  }

  test('the reported state is a doomed proof turn with no meld plays', () {
    final c = build();
    expect(c.currentSeat, PlayerSeat.south);
    expect(c.isFiftyProofTurn, isTrue);
    expect(c.pendingDiscard?.id, 'deck-1-seven-clubs');
    final legal = c.legalActionIdsFor(PlayerSeat.south);
    // Cannot reach the 104 requirement, so nothing can be laid down.
    expect(
      legal.any((id) => id.startsWith('play-meld') || id.startsWith('cover')),
      isFalse,
      reason: 'no meld can be played at requirement 104',
    );
  });

  test('returning the claimed card gives up the Fifty (+17 and out)', () {
    final c = build();
    expect(
      c.controlActionIdsFor(PlayerSeat.south),
      contains(ClassicHareegActionIds.returnPendingDiscard),
      reason: 'the give-up must be discoverable on the control surface',
    );

    final before = c.scores[PlayerSeat.south] ?? 0;
    final result = c.applyAction(
      ClassicHareegActionIds.returnPendingDiscard,
    );
    expect(result.isSuccess, isTrue);
    expect(c.scores[PlayerSeat.south], before + 17);
    expect(c.removedSeats.contains(PlayerSeat.south), isTrue);
    expect(c.isFiftyProofTurn, isFalse);
    expect(c.currentSeat, isNot(PlayerSeat.south));
  });
}
