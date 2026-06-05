import '../../../../l10n/app_strings.dart';

/// Guided practice packs, in teaching order.
enum PracticePackId {
  /// Core turn basics every new player needs before normal matches feel fair.
  coreTurn,

  /// Table mechanics that create most of Classic Hareeg's nuance.
  tableMechanics,

  /// High-pressure end states: finishing and Fifty / Khamsin.
  finishAndFifty;

  /// Localized pack title.
  String title(AppStrings strings) {
    return switch (this) {
      PracticePackId.coreTurn => strings.practicePackCoreTitle,
      PracticePackId.tableMechanics => strings.practicePackTableTitle,
      PracticePackId.finishAndFifty => strings.practicePackFinishTitle,
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
  });

  /// Stable lesson id used for progress persistence.
  final String id;

  /// Pack this lesson belongs to.
  final PracticePackId pack;

  /// Localized checklist title.
  final String Function(AppStrings strings) title;

  /// Localized one-line summary of the taught mechanic.
  final String Function(AppStrings strings) summary;
}

/// Static catalog of all planned guided practice lessons.
///
/// The checklist shows every entry from day one; lessons become playable as
/// their practice packs ship (see the PRD implementation tracker).
abstract final class PracticeCatalog {
  /// All lessons in checklist display order.
  static final List<PracticeLesson> lessons = List.unmodifiable([
    // Core turn basics.
    PracticeLesson(
      id: 'turn-rhythm',
      pack: PracticePackId.coreTurn,
      title: (s) => s.practiceTurnRhythmTitle,
      summary: (s) => s.practiceTurnRhythmSummary,
    ),
    PracticeLesson(
      id: 'pending-discard',
      pack: PracticePackId.coreTurn,
      title: (s) => s.practicePendingDiscardTitle,
      summary: (s) => s.practicePendingDiscardSummary,
    ),
    PracticeLesson(
      id: 'meld-picker',
      pack: PracticePackId.coreTurn,
      title: (s) => s.practiceMeldPickerTitle,
      summary: (s) => s.practiceMeldPickerSummary,
    ),
    PracticeLesson(
      id: 'opening-51',
      pack: PracticePackId.coreTurn,
      title: (s) => s.practiceOpeningTitle,
      summary: (s) => s.practiceOpeningSummary,
    ),
    // Table mechanics.
    PracticeLesson(
      id: 'benchmark-pressure',
      pack: PracticePackId.tableMechanics,
      title: (s) => s.practiceBenchmarkTitle,
      summary: (s) => s.practiceBenchmarkSummary,
    ),
    PracticeLesson(
      id: 'sequence-cover',
      pack: PracticePackId.tableMechanics,
      title: (s) => s.practiceSequenceCoverTitle,
      summary: (s) => s.practiceSequenceCoverSummary,
    ),
    PracticeLesson(
      id: 'set-cover',
      pack: PracticePackId.tableMechanics,
      title: (s) => s.practiceSetCoverTitle,
      summary: (s) => s.practiceSetCoverSummary,
    ),
    PracticeLesson(
      id: 'cover-discard-block',
      pack: PracticePackId.tableMechanics,
      title: (s) => s.practiceCoverDiscardTitle,
      summary: (s) => s.practiceCoverDiscardSummary,
    ),
    PracticeLesson(
      id: 'joker-identity',
      pack: PracticePackId.tableMechanics,
      title: (s) => s.practiceJokerIdentityTitle,
      summary: (s) => s.practiceJokerIdentitySummary,
    ),
    PracticeLesson(
      id: 'joker-replacement',
      pack: PracticePackId.tableMechanics,
      title: (s) => s.practiceJokerReplacementTitle,
      summary: (s) => s.practiceJokerReplacementSummary,
    ),
    // Finishing & Fifty.
    PracticeLesson(
      id: 'final-discard',
      pack: PracticePackId.finishAndFifty,
      title: (s) => s.practiceFinalDiscardTitle,
      summary: (s) => s.practiceFinalDiscardSummary,
    ),
    PracticeLesson(
      id: 'normal-finish',
      pack: PracticePackId.finishAndFifty,
      title: (s) => s.practiceNormalFinishTitle,
      summary: (s) => s.practiceNormalFinishSummary,
    ),
    PracticeLesson(
      id: 'fifty-claim',
      pack: PracticePackId.finishAndFifty,
      title: (s) => s.practiceFiftyClaimTitle,
      summary: (s) => s.practiceFiftyClaimSummary,
    ),
    PracticeLesson(
      id: 'fifty-scoring',
      pack: PracticePackId.finishAndFifty,
      title: (s) => s.practiceFiftyScoringTitle,
      summary: (s) => s.practiceFiftyScoringSummary,
    ),
    PracticeLesson(
      id: 'strictness-tiers',
      pack: PracticePackId.finishAndFifty,
      title: (s) => s.practiceStrictnessTitle,
      summary: (s) => s.practiceStrictnessSummary,
    ),
  ]);

  /// All stable lesson ids in display order.
  static List<String> get lessonIds =>
      [for (final lesson in lessons) lesson.id];

  /// Lessons belonging to one pack, preserving catalog order.
  static List<PracticeLesson> lessonsIn(PracticePackId pack) =>
      [for (final lesson in lessons) if (lesson.pack == pack) lesson];

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
