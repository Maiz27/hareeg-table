import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/table_strictness.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/strictness_rule_profile.dart';

void main() {
  group('StrictnessRuleProfile', () {
    group('blocksIllegalMoves', () {
      test('is true for coaching and standard', () {
        expect(TableStrictness.coaching.blocksIllegalMoves, isTrue);
        expect(TableStrictness.standard.blocksIllegalMoves, isTrue);
      });

      test('is false for strict and table', () {
        expect(TableStrictness.strict.blocksIllegalMoves, isFalse);
        expect(TableStrictness.table.blocksIllegalMoves, isFalse);
      });
    });

    group('mistakePenaltyPoints', () {
      test('is zero for blocking tiers', () {
        expect(TableStrictness.coaching.mistakePenaltyPoints, 0);
        expect(TableStrictness.standard.mistakePenaltyPoints, 0);
      });

      test('matches the agreed ladder for permissive tiers', () {
        expect(TableStrictness.strict.mistakePenaltyPoints, 3);
        expect(TableStrictness.table.mistakePenaltyPoints, 17);
      });
    });

    group('removesPlayerOnMistake', () {
      test('is true only for table tier', () {
        expect(TableStrictness.coaching.removesPlayerOnMistake, isFalse);
        expect(TableStrictness.standard.removesPlayerOnMistake, isFalse);
        expect(TableStrictness.strict.removesPlayerOnMistake, isFalse);
        expect(TableStrictness.table.removesPlayerOnMistake, isTrue);
      });
    });

    group('allowsTablePlayRetraction', () {
      test('is true for every tier except table', () {
        expect(TableStrictness.coaching.allowsTablePlayRetraction, isTrue);
        expect(TableStrictness.standard.allowsTablePlayRetraction, isTrue);
        expect(TableStrictness.strict.allowsTablePlayRetraction, isTrue);
        expect(TableStrictness.table.allowsTablePlayRetraction, isFalse);
      });
    });

    group('fiftyClaimNeedsFinishProofForAdvertise', () {
      test('mirrors blocksIllegalMoves', () {
        for (final tier in TableStrictness.values) {
          expect(
            tier.fiftyClaimNeedsFinishProofForAdvertise,
            tier.blocksIllegalMoves,
            reason: 'tier=$tier',
          );
        }
      });
    });

    group('cpuMistakesAllowed', () {
      test('only Table tier accepts CPU mistakes', () {
        // Strict reverts mistakes (penalty + action undone) — letting a CPU
        // trigger that path just burns turns. Only Table tier (full +17 +
        // round removal) is meaningful for CPUs to ever risk.
        for (final tier in TableStrictness.values) {
          expect(
            tier.cpuMistakesAllowed,
            tier == TableStrictness.table,
            reason: 'tier=$tier',
          );
        }
      });
    });
  });
}
