import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/ui/features/learning/models/practice_catalog.dart';
import 'package:hareeg_table/ui/features/learning/models/practice_lesson_registry.dart';
import 'package:hareeg_table/ui/features/learning/practice/practice_board.dart';
import 'package:hareeg_table/ui/features/learning/practice/practice_board_grammar.dart';

import '../../../support/practice_lesson_harness.dart';

void main() {
  group('every scripted lesson declares a clean starting hand', () {
    for (final lesson in PracticeCatalog.lessons) {
      final script = PracticeLessonRegistry.scriptFor(lesson.id);
      if (script == null) {
        continue; // Reading-panel lessons have no board to audit.
      }
      test('${lesson.id}: fillers form no unintended meld', () {
        expect(
          script.taughtMelds,
          isNotNull,
          reason: 'a scripted lesson must declare its teaching cards so the '
              'grammar can prove the rest of the hand is filler',
        );
        final audit = script.auditInitialBoard();
        expect(audit, isNotNull);
        expect(
          audit!.failures,
          isEmpty,
          reason: audit.failures.join('\n'),
        );
      });
    }
  });

  group('the composition audit catches a stray filler meld', () {
    final heartRun = [
      practiceCard(CardRank.nine, CardSuit.hearts),
      practiceCard(CardRank.ten, CardSuit.hearts),
      practiceCard(CardRank.jack, CardSuit.hearts),
    ];
    final strayKings = [
      practiceCard(CardRank.king, CardSuit.spades),
      practiceCard(CardRank.king, CardSuit.diamonds),
      practiceCard(CardRank.king, CardSuit.hearts),
    ];

    test('a stray set among the fillers fails the audit and names it', () {
      final snapshot = PracticeBoard.build(
        southHand: [...heartRun, ...strayKings],
        topDiscard: practiceCard(CardRank.two, CardSuit.clubs),
      );
      final audit = PracticeBoardGrammar.auditSnapshot(
        snapshot,
        const PracticeBoardAuditSpec(),
        taughtMelds: [{for (final card in heartRun) card.id}],
      );

      expect(audit.passed, isFalse);
      expect(audit.failures.single, contains('unintended meld'));
      // The stray kings are named; the taught run is not flagged.
      for (final king in strayKings) {
        expect(audit.failures.single, contains(king.id));
      }
    });

    test('the same taught run with meld-free fillers passes', () {
      final snapshot = PracticeBoard.build(
        southHand: [
          ...heartRun,
          practiceCard(CardRank.two, CardSuit.clubs),
          practiceCard(CardRank.four, CardSuit.diamonds),
          practiceCard(CardRank.six, CardSuit.spades),
        ],
        topDiscard: practiceCard(CardRank.two, CardSuit.hearts),
      );
      final audit = PracticeBoardGrammar.auditSnapshot(
        snapshot,
        const PracticeBoardAuditSpec(),
        taughtMelds: [{for (final card in heartRun) card.id}],
      );

      expect(audit.passed, isTrue);
    });
  });
}
