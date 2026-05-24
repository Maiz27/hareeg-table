import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_score_ledger.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/match_progression_rules.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/mistake_preset_rules.dart';

void main() {
  group('ClassicHareegScoreLedger', () {
    test(
      'applies immediate mistake penalties without mutating input scores',
      () {
        final original = {PlayerSeat.south: 5};
        final penalty = ClassicHareegMistakePresetRules.resolve(
          strictness: TableStrictness.strict,
          mistake: MistakeType.wrongFiftyClaim,
        );

        final next = ClassicHareegScoreLedger.applyPenalty(
          scores: original,
          seat: PlayerSeat.south,
          resolution: penalty,
        );

        expect(original[PlayerSeat.south], 5);
        expect(next[PlayerSeat.south], 8);
        expect(next[PlayerSeat.east], 0);
      },
    );

    test('current scores include completed-round progress', () {
      const progress = MatchProgressState(
        scores: {
          PlayerSeat.south: 14,
          PlayerSeat.east: -3,
          PlayerSeat.north: 6,
          PlayerSeat.west: 8,
        },
        activeSeats: PlayerSeat.values,
        nextStarter: PlayerSeat.east,
      );

      final view = ClassicHareegScoreLedger.view(
        scores: const {PlayerSeat.south: 0, PlayerSeat.east: 0},
        progress: progress,
      );

      expect(view.previousScores[PlayerSeat.south], 0);
      expect(view.previousScores[PlayerSeat.north], 0);
      expect(view.currentScores[PlayerSeat.south], 14);
      expect(view.currentScores[PlayerSeat.east], -3);
      expect(view.progress, same(progress));
    });
  });
}
