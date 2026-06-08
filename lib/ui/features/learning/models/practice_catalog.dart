import '../../../../l10n/app_strings.dart';
import '../practice/core_turn_practice_pack.dart';
import '../practice/finish_fifty_practice_pack.dart';
import '../practice/table_mechanics_practice_pack.dart';
import '../practice/table_strictness_practice_pack.dart';
import 'practice_lesson_delivery.dart';

/// Guided practice packs, in teaching order.
enum PracticePackId {
  /// Vocabulary a brand-new player needs before the Core turn: card values,
  /// meld shapes, and the ace. Conceptual reading panels, no board.
  fundamentals,

  /// Core turn basics every new player needs before normal matches feel fair.
  coreTurn,

  /// Table mechanics that create most of Classic Hareeg's nuance.
  tableMechanics,

  /// High-pressure end states: finishing and Fifty / Khamsin.
  finishAndFifty,

  /// How each strictness tier prices the same trapped-cover throw.
  tableStrictness;

  /// Localized pack title.
  String title(AppStrings strings) {
    return switch (this) {
      PracticePackId.fundamentals => strings.practicePackFundamentalsTitle,
      PracticePackId.coreTurn => strings.practicePackCoreTitle,
      PracticePackId.tableMechanics => strings.practicePackTableTitle,
      PracticePackId.finishAndFifty => strings.practicePackFinishTitle,
      PracticePackId.tableStrictness => strings.practicePackTableStrictnessTitle,
    };
  }
}

/// One guided practice lesson entry in the checklist.
///
/// The id is the stable persistence key used by `LearningProgress`; never
/// rename a shipped id without a migration.
class PracticeLesson {
  /// Creates a catalog entry.
  const PracticeLesson({
    required this.id,
    required this.pack,
    required this.title,
    required this.summary,
    required this.delivery,
  });

  /// Stable lesson id used for progress persistence.
  final String id;

  /// Pack this lesson belongs to.
  final PracticePackId pack;

  /// Localized checklist title.
  final String Function(AppStrings strings) title;

  /// Localized one-line summary of the taught mechanic.
  final String Function(AppStrings strings) summary;

  /// How this lesson is delivered to the player.
  final PracticeLessonDelivery delivery;
}

/// Static catalog of all planned guided practice lessons.
///
/// The checklist shows every entry from day one; lessons become playable as
/// their practice packs ship (see the PRD implementation tracker).
abstract final class PracticeCatalog {
  /// All lessons in checklist display order.
  static final List<PracticeLesson> lessons = List.unmodifiable([
    // Fundamentals: conceptual reference panels that teach the vocabulary a
    // brand-new player needs before the Core turn. No board, no turn — each
    // is delivered as a reading panel.
    PracticeLesson(
      id: 'card-values',
      pack: PracticePackId.fundamentals,
      title: (s) => s.practiceCardValuesTitle,
      summary: (s) => s.practiceCardValuesSummary,
      delivery: PracticeLessonDelivery.readingPanel(),
    ),
    PracticeLesson(
      id: 'meld-shapes',
      pack: PracticePackId.fundamentals,
      title: (s) => s.practiceMeldShapesTitle,
      summary: (s) => s.practiceMeldShapesSummary,
      delivery: PracticeLessonDelivery.readingPanel(),
    ),
    PracticeLesson(
      id: 'the-ace',
      pack: PracticePackId.fundamentals,
      title: (s) => s.practiceTheAceTitle,
      summary: (s) => s.practiceTheAceSummary,
      delivery: PracticeLessonDelivery.readingPanel(),
    ),
    // Core turn basics, in strict teaching order: the loop, then a first
    // opening that needs nothing but your own hand, then openings that lean
    // on the discard pile, then judging when the pile is a trap, and finally
    // multi-meld staging. Mechanics that assume an already-opened table
    // (pending use-or-return, covers, jokers) live in later packs.
    PracticeLesson(
      id: 'turn-rhythm',
      pack: PracticePackId.coreTurn,
      title: (s) => s.practiceTurnRhythmTitle,
      summary: (s) => s.practiceTurnRhythmSummary,
      delivery: PracticeLessonDelivery.scriptedTable(
        CoreTurnPracticePack.turnRhythm,
      ),
    ),
    PracticeLesson(
      id: 'first-meld',
      pack: PracticePackId.coreTurn,
      title: (s) => s.practiceFirstMeldTitle,
      summary: (s) => s.practiceFirstMeldSummary,
      delivery: PracticeLessonDelivery.scriptedTable(
        CoreTurnPracticePack.firstMeld,
      ),
    ),
    PracticeLesson(
      id: 'discard-opening',
      pack: PracticePackId.coreTurn,
      title: (s) => s.practiceDiscardOpeningTitle,
      summary: (s) => s.practiceDiscardOpeningSummary,
      delivery: PracticeLessonDelivery.scriptedTable(
        CoreTurnPracticePack.discardOpening,
      ),
    ),
    PracticeLesson(
      id: 'bait-discard',
      pack: PracticePackId.coreTurn,
      title: (s) => s.practiceBaitDiscardTitle,
      summary: (s) => s.practiceBaitDiscardSummary,
      delivery: PracticeLessonDelivery.scriptedTable(
        CoreTurnPracticePack.baitDiscard,
      ),
    ),
    PracticeLesson(
      id: 'opening-51',
      pack: PracticePackId.coreTurn,
      title: (s) => s.practiceOpeningTitle,
      summary: (s) => s.practiceOpeningSummary,
      delivery: PracticeLessonDelivery.scriptedTable(
        CoreTurnPracticePack.openingTo51,
      ),
    ),
    // Table mechanics.
    PracticeLesson(
      id: 'pending-discard',
      pack: PracticePackId.tableMechanics,
      title: (s) => s.practicePendingDiscardTitle,
      summary: (s) => s.practicePendingDiscardSummary,
      delivery: PracticeLessonDelivery.scriptedTable(
        TableMechanicsPracticePack.pendingDiscard,
      ),
    ),
    PracticeLesson(
      id: 'benchmark-pressure',
      pack: PracticePackId.tableMechanics,
      title: (s) => s.practiceBenchmarkTitle,
      summary: (s) => s.practiceBenchmarkSummary,
      delivery: PracticeLessonDelivery.scriptedTable(
        TableMechanicsPracticePack.benchmarkPressure,
      ),
    ),
    // Covers teach in two beats: one card on one meld establishes the rule,
    // then stacked covers across two melds show its reach.
    PracticeLesson(
      id: 'set-cover',
      pack: PracticePackId.tableMechanics,
      title: (s) => s.practiceSetCoverTitle,
      summary: (s) => s.practiceSetCoverSummary,
      delivery: PracticeLessonDelivery.scriptedTable(
        TableMechanicsPracticePack.setCover,
      ),
    ),
    PracticeLesson(
      id: 'sequence-cover',
      pack: PracticePackId.tableMechanics,
      title: (s) => s.practiceSequenceCoverTitle,
      summary: (s) => s.practiceSequenceCoverSummary,
      delivery: PracticeLessonDelivery.scriptedTable(
        TableMechanicsPracticePack.sequenceCover,
      ),
    ),
    PracticeLesson(
      id: 'cover-discard-block',
      pack: PracticePackId.tableMechanics,
      title: (s) => s.practiceCoverDiscardTitle,
      summary: (s) => s.practiceCoverDiscardSummary,
      delivery: PracticeLessonDelivery.scriptedTable(
        TableMechanicsPracticePack.coverDiscardBlock,
      ),
    ),
    PracticeLesson(
      id: 'joker-identity',
      pack: PracticePackId.tableMechanics,
      title: (s) => s.practiceJokerIdentityTitle,
      summary: (s) => s.practiceJokerIdentitySummary,
      delivery: PracticeLessonDelivery.scriptedTable(
        TableMechanicsPracticePack.jokerIdentity,
      ),
    ),
    PracticeLesson(
      id: 'joker-replacement',
      pack: PracticePackId.tableMechanics,
      title: (s) => s.practiceJokerReplacementTitle,
      summary: (s) => s.practiceJokerReplacementSummary,
      delivery: PracticeLessonDelivery.scriptedTable(
        TableMechanicsPracticePack.jokerReplacement,
      ),
    ),
    // Finishing & Fifty.
    PracticeLesson(
      id: 'final-discard',
      pack: PracticePackId.finishAndFifty,
      title: (s) => s.practiceFinalDiscardTitle,
      summary: (s) => s.practiceFinalDiscardSummary,
      delivery: PracticeLessonDelivery.scriptedTable(
        FinishFiftyPracticePack.finalDiscard,
      ),
    ),
    PracticeLesson(
      id: 'normal-finish',
      pack: PracticePackId.finishAndFifty,
      title: (s) => s.practiceNormalFinishTitle,
      summary: (s) => s.practiceNormalFinishSummary,
      delivery: PracticeLessonDelivery.scriptedTable(
        FinishFiftyPracticePack.normalFinish,
      ),
    ),
    PracticeLesson(
      id: 'perfect-hand-finish',
      pack: PracticePackId.finishAndFifty,
      title: (s) => s.practicePerfectHandTitle,
      summary: (s) => s.practicePerfectHandSummary,
      delivery: PracticeLessonDelivery.scriptedTable(
        FinishFiftyPracticePack.perfectHandFinish,
      ),
    ),
    PracticeLesson(
      id: 'joker-final-discard',
      pack: PracticePackId.finishAndFifty,
      title: (s) => s.practiceJokerOutTitle,
      summary: (s) => s.practiceJokerOutSummary,
      delivery: PracticeLessonDelivery.scriptedTable(
        FinishFiftyPracticePack.jokerFinalDiscard,
      ),
    ),
    PracticeLesson(
      id: 'fifty-claim',
      pack: PracticePackId.finishAndFifty,
      title: (s) => s.practiceFiftyClaimTitle,
      summary: (s) => s.practiceFiftyClaimSummary,
      delivery: PracticeLessonDelivery.scriptedTable(
        FinishFiftyPracticePack.fiftyClaim,
      ),
    ),
    PracticeLesson(
      id: 'fifty-scoring',
      pack: PracticePackId.finishAndFifty,
      title: (s) => s.practiceFiftyScoringTitle,
      summary: (s) => s.practiceFiftyScoringSummary,
      delivery: PracticeLessonDelivery.scriptedTable(
        FinishFiftyPracticePack.fiftyScoring,
      ),
    ),
    // Table strictness: the reading panel introduces the four tiers, then two
    // scripted demos put the same trapped-cover throw on the stricter tables
    // so the player feels Strict's +3 and Table's +17/round-out for real.
    PracticeLesson(
      id: 'strictness-tiers',
      pack: PracticePackId.tableStrictness,
      title: (s) => s.practiceStrictnessTitle,
      summary: (s) => s.practiceStrictnessSummary,
      delivery: PracticeLessonDelivery.readingPanel(),
    ),
    PracticeLesson(
      id: 'strict-penalty',
      pack: PracticePackId.tableStrictness,
      title: (s) => s.practiceStrictPenaltyTitle,
      summary: (s) => s.practiceStrictPenaltySummary,
      delivery: PracticeLessonDelivery.scriptedTable(
        TableStrictnessPracticePack.strictPenalty,
      ),
    ),
    PracticeLesson(
      id: 'table-penalty',
      pack: PracticePackId.tableStrictness,
      title: (s) => s.practiceTablePenaltyTitle,
      summary: (s) => s.practiceTablePenaltySummary,
      delivery: PracticeLessonDelivery.scriptedTable(
        TableStrictnessPracticePack.tablePenalty,
      ),
    ),
  ]);

  /// All stable lesson ids in display order.
  static List<String> get lessonIds => [
    for (final lesson in lessons) lesson.id,
  ];

  /// Lessons belonging to one pack, preserving catalog order.
  static List<PracticeLesson> lessonsIn(PracticePackId pack) => [
    for (final lesson in lessons)
      if (lesson.pack == pack) lesson,
  ];

  /// Looks up a lesson by stable id.
  static PracticeLesson? byId(String id) {
    for (final lesson in lessons) {
      if (lesson.id == id) {
        return lesson;
      }
    }
    return null;
  }
}
