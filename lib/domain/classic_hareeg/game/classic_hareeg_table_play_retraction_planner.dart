import '../models/player_seat.dart';
import '../models/table_strictness.dart';
import '../rules/opening_rules.dart';
import '../rules/strictness_rule_profile.dart';
import 'classic_hareeg_action.dart';
import 'classic_hareeg_round.dart';
import 'classic_hareeg_turn_journal.dart';

/// Table-play retraction scenario for the current turn.
enum ClassicHareegTablePlayRetractionScenario {
  /// No reversible table play exists.
  noRetraction,

  /// The queried seat is not the active action-phase seat.
  notCurrentActionTurn,

  /// Table strictness blocks same-turn regular meld and cover retractions.
  blockedByStrictness,

  /// The requested table meld no longer exists.
  targetMissing,

  /// All staged opening melds should be returned.
  allOpeningMelds,

  /// All same-turn regular melds should be returned.
  allTurnMelds,

  /// All same-turn covers should be returned.
  allTurnCovers,

  /// A mixture of same-turn table plays should be returned.
  allMixedTablePlays,

  /// One staged opening meld should be returned.
  specificOpeningMeld,

  /// One same-turn regular meld should be returned.
  specificTurnMeld,

  /// Same-turn covers on one table meld should be returned.
  specificCoverStack,
}

/// Complete retraction decision for either a bulk or specific return action.
class ClassicHareegTablePlayRetractionPlan {
  /// Creates a retraction plan.
  const ClassicHareegTablePlayRetractionPlan({
    required this.scenario,
    required this.isAllowed,
    required this.shouldAdvertise,
    required this.message,
    this.target,
    this.openingMelds = const [],
    this.meldPlays = const [],
    this.coverPlays = const [],
    this.stagedOpeningIndex,
  });

  /// Identified retraction scenario.
  final ClassicHareegTablePlayRetractionScenario scenario;

  /// Whether applying this retraction may proceed.
  final bool isAllowed;

  /// Whether this retraction should be exposed as a legal action.
  final bool shouldAdvertise;

  /// Player-facing explanation.
  final String message;

  /// Specific table-play target, when this is a target retraction.
  final ReturnTablePlayTarget? target;

  /// Staged opening melds included in the retraction.
  final List<PlacedMeld> openingMelds;

  /// Same-turn regular meld plays included in the retraction.
  final List<ClassicHareegTurnMeldPlay> meldPlays;

  /// Same-turn cover plays included in the retraction.
  final List<ClassicHareegTurnCoverPlay> coverPlays;

  /// Index into the journal's staged-opening stack for a specific opening.
  final int? stagedOpeningIndex;
}

/// Resolves whether current-turn table plays can be taken back.
abstract final class ClassicHareegTablePlayRetractionPlanner {
  /// Evaluates the bulk "return table plays" action.
  static ClassicHareegTablePlayRetractionPlan evaluateAll({
    required PlayerSeat seat,
    required PlayerSeat currentSeat,
    required TurnPhase phase,
    required TableStrictness strictness,
    required OpeningState openingState,
    required ClassicHareegTurnJournal journal,
  }) {
    final turnCheck = _turnCheck(
      seat: seat,
      currentSeat: currentSeat,
      phase: phase,
      target: null,
    );
    if (turnCheck != null) {
      return turnCheck;
    }

    final openingMelds = !openingState.hasOpened(seat)
        ? journal.openingMeldsView
        : const <PlacedMeld>[];
    final meldPlays = journal.turnMeldsView;
    final coverPlays = journal.coverPlaysView;
    final hasOpeningMelds = openingMelds.isNotEmpty;
    final hasTurnMelds = meldPlays.isNotEmpty;
    final hasTurnCovers = coverPlays.isNotEmpty;

    // Hard table mode blocks retraction of regular meld/cover plays
    // regardless of whether staged opening melds happen to coexist. The
    // per-target paths (evaluateTarget) already fire the block unconditionally
    // for those play types; keep bulk evaluation consistent so a mixed state
    // can never bypass the block.
    if (hasTurnMelds || hasTurnCovers) {
      final strictnessBlock = _strictnessBlock(
        strictness: strictness,
        target: null,
      );
      if (strictnessBlock != null) {
        return strictnessBlock;
      }
    }

    if (!hasOpeningMelds && !hasTurnMelds && !hasTurnCovers) {
      return const ClassicHareegTablePlayRetractionPlan(
        scenario: ClassicHareegTablePlayRetractionScenario.noRetraction,
        isAllowed: false,
        shouldAdvertise: false,
        message: 'There are no uncommitted table plays to take back.',
      );
    }

    final scenario = _bulkScenario(
      hasOpeningMelds: hasOpeningMelds,
      hasTurnMelds: hasTurnMelds,
      hasTurnCovers: hasTurnCovers,
    );
    return ClassicHareegTablePlayRetractionPlan(
      scenario: scenario,
      isAllowed: true,
      shouldAdvertise: true,
      message: _bulkMessage(
        hasOpeningMelds: hasOpeningMelds,
        hasTurnMelds: hasTurnMelds,
        hasCovers: hasTurnCovers,
      ),
      openingMelds: openingMelds,
      meldPlays: meldPlays,
      coverPlays: coverPlays,
    );
  }

  /// Evaluates returning one visible table meld or cover stack.
  static ClassicHareegTablePlayRetractionPlan evaluateTarget({
    required PlayerSeat seat,
    required PlayerSeat currentSeat,
    required TurnPhase phase,
    required TableStrictness strictness,
    required OpeningState openingState,
    required ClassicHareegTurnJournal journal,
    required Map<PlayerSeat, List<PlacedMeld>> tableMelds,
    required ReturnTablePlayTarget target,
  }) {
    final turnCheck = _turnCheck(
      seat: seat,
      currentSeat: currentSeat,
      phase: phase,
      target: target,
    );
    if (turnCheck != null) {
      return turnCheck;
    }

    final targetMeld = _targetMeld(tableMelds, target);
    if (targetMeld == null) {
      return ClassicHareegTablePlayRetractionPlan(
        scenario: ClassicHareegTablePlayRetractionScenario.targetMissing,
        isAllowed: false,
        shouldAdvertise: false,
        message: 'That meld is no longer on table.',
        target: target,
      );
    }

    final coverPlays = journal.coverPlaysFor(
      owner: target.owner,
      meldIndex: target.meldIndex,
    );
    if (coverPlays.isNotEmpty) {
      final strictnessBlock = _strictnessBlock(
        strictness: strictness,
        target: target,
      );
      if (strictnessBlock != null) {
        return strictnessBlock;
      }
      return ClassicHareegTablePlayRetractionPlan(
        scenario: ClassicHareegTablePlayRetractionScenario.specificCoverStack,
        isAllowed: true,
        shouldAdvertise: true,
        message: 'Covers returned to your hand.',
        target: target,
        coverPlays: List.unmodifiable(coverPlays),
      );
    }

    final turnMeldPlay = journal.findTurnMeldFor(
      owner: target.owner,
      targetMeld: targetMeld,
    );
    if (turnMeldPlay != null) {
      final strictnessBlock = _strictnessBlock(
        strictness: strictness,
        target: target,
      );
      if (strictnessBlock != null) {
        return strictnessBlock;
      }
      return ClassicHareegTablePlayRetractionPlan(
        scenario: ClassicHareegTablePlayRetractionScenario.specificTurnMeld,
        isAllowed: true,
        shouldAdvertise: true,
        message: 'Melds returned to your hand.',
        target: target,
        meldPlays: List.unmodifiable([turnMeldPlay]),
      );
    }

    if (!openingState.hasOpened(seat) && target.owner == seat) {
      final stagedIndex = journal.findStagedOpeningIndexByPhysicalCards(
        targetMeld.cards,
      );
      if (stagedIndex != -1) {
        return ClassicHareegTablePlayRetractionPlan(
          scenario:
              ClassicHareegTablePlayRetractionScenario.specificOpeningMeld,
          isAllowed: true,
          shouldAdvertise: true,
          message: 'Opening melds returned to your hand.',
          target: target,
          openingMelds: List.unmodifiable([
            journal.stagedOpeningMeldAt(stagedIndex),
          ]),
          stagedOpeningIndex: stagedIndex,
        );
      }
    }

    return ClassicHareegTablePlayRetractionPlan(
      scenario: ClassicHareegTablePlayRetractionScenario.noRetraction,
      isAllowed: false,
      shouldAdvertise: false,
      message: 'That table play cannot be taken back right now.',
      target: target,
    );
  }

  static ClassicHareegTablePlayRetractionPlan? _turnCheck({
    required PlayerSeat seat,
    required PlayerSeat currentSeat,
    required TurnPhase phase,
    required ReturnTablePlayTarget? target,
  }) {
    if (seat == currentSeat && phase == TurnPhase.action) {
      return null;
    }

    return ClassicHareegTablePlayRetractionPlan(
      scenario: ClassicHareegTablePlayRetractionScenario.notCurrentActionTurn,
      isAllowed: false,
      shouldAdvertise: false,
      message: target == null
          ? 'There are no uncommitted table plays to take back.'
          : 'That table play cannot be taken back right now.',
      target: target,
    );
  }

  static ClassicHareegTablePlayRetractionPlan? _strictnessBlock({
    required TableStrictness strictness,
    required ReturnTablePlayTarget? target,
  }) {
    if (strictness.allowsTablePlayRetraction) {
      return null;
    }

    return ClassicHareegTablePlayRetractionPlan(
      scenario: ClassicHareegTablePlayRetractionScenario.blockedByStrictness,
      isAllowed: false,
      shouldAdvertise: false,
      message: 'This table tier does not allow taking back table plays.',
      target: target,
    );
  }

  static ClassicHareegTablePlayRetractionScenario _bulkScenario({
    required bool hasOpeningMelds,
    required bool hasTurnMelds,
    required bool hasTurnCovers,
  }) {
    final categoryCount =
        (hasOpeningMelds ? 1 : 0) +
        (hasTurnMelds ? 1 : 0) +
        (hasTurnCovers ? 1 : 0);
    if (categoryCount > 1) {
      return ClassicHareegTablePlayRetractionScenario.allMixedTablePlays;
    }
    if (hasTurnCovers) {
      return ClassicHareegTablePlayRetractionScenario.allTurnCovers;
    }
    if (hasTurnMelds) {
      return ClassicHareegTablePlayRetractionScenario.allTurnMelds;
    }
    return ClassicHareegTablePlayRetractionScenario.allOpeningMelds;
  }

  static String _bulkMessage({
    required bool hasOpeningMelds,
    required bool hasTurnMelds,
    required bool hasCovers,
  }) {
    final categoryCount =
        (hasOpeningMelds ? 1 : 0) +
        (hasTurnMelds ? 1 : 0) +
        (hasCovers ? 1 : 0);
    if (categoryCount > 1) {
      return 'Table plays returned to your hand.';
    }
    if (hasCovers) {
      return 'Covers returned to your hand.';
    }
    if (hasTurnMelds) {
      return 'Melds returned to your hand.';
    }
    return 'Opening melds returned to your hand.';
  }

  static PlacedMeld? _targetMeld(
    Map<PlayerSeat, List<PlacedMeld>> tableMelds,
    ReturnTablePlayTarget target,
  ) {
    final melds = tableMelds[target.owner];
    if (melds == null ||
        target.meldIndex < 0 ||
        target.meldIndex >= melds.length) {
      return null;
    }
    return melds[target.meldIndex];
  }
}
