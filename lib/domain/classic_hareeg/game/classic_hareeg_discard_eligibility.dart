import '../models/classic_hareeg_setup.dart';
import '../models/playing_card.dart';
import '../rules/cover_rules.dart';
import '../rules/joker_rules.dart';
import '../rules/mistake_preset_rules.dart';
import 'classic_hareeg_action.dart';

/// Discard scenario identified for a physical card.
enum ClassicHareegDiscardScenario {
  /// Plain discard with no table restriction.
  normal,

  /// Final discard that may use otherwise blocked cards.
  finalDiscard,

  /// Normal joker discard, blocked in every preset.
  normalJoker,

  /// Card is a cover for at least one table meld.
  cover,

  /// Card can replace a represented table joker.
  jokerReplacement,

  /// Card is both a cover and a represented-joker replacement.
  coverAndJokerReplacement,
}

/// Complete discard eligibility for one physical card in the current state.
class ClassicHareegDiscardEligibility {
  /// Creates a discard eligibility result.
  const ClassicHareegDiscardEligibility({
    required this.card,
    required this.scenario,
    required this.isAllowed,
    required this.shouldAdvertise,
    required this.actionPrefix,
    required this.message,
    required this.isFinalDiscard,
    this.mistakeType,
    this.mistakeResolution,
  });

  /// Physical card being evaluated.
  final HareegCard card;

  /// Named discard scenario.
  final ClassicHareegDiscardScenario scenario;

  /// Whether applying the advertised action may proceed.
  final bool isAllowed;

  /// Whether this card should appear in legal action ids.
  final bool shouldAdvertise;

  /// Action id prefix for this discard scenario.
  final String actionPrefix;

  /// Player-facing explanation for the decision.
  final String message;

  /// Whether this discard would be the player's final discard.
  final bool isFinalDiscard;

  /// Mistake type required to allow this discard, if any.
  final MistakeType? mistakeType;

  /// Preset-specific mistake behavior, if this is a mistake scenario.
  final MistakeResolution? mistakeResolution;

  /// Whether the discard proceeds only after applying a mistake preset.
  bool get appliesMistake => mistakeResolution?.isAllowed ?? false;

  /// Full action id for this card and scenario.
  String get actionId => '$actionPrefix${card.id}';
}

/// Plans discard eligibility as a rich scenario instead of scattered booleans.
abstract final class ClassicHareegDiscardEligibilityPlanner {
  /// Resolves discard eligibility for [card].
  static ClassicHareegDiscardEligibility evaluate({
    required RulePreset preset,
    required Iterable<List<HareegCard>> tableMelds,
    required HareegCard card,
    required bool isFinalDiscard,
    required bool blocksJokerReplacement,
  }) {
    if (isFinalDiscard) {
      return ClassicHareegDiscardEligibility(
        card: card,
        scenario: ClassicHareegDiscardScenario.finalDiscard,
        isAllowed: true,
        shouldAdvertise: true,
        actionPrefix: ClassicHareegActionIds.discardPrefix,
        message: 'Final discard may use this card.',
        isFinalDiscard: true,
      );
    }

    if (!ClassicHareegJokerRules.canDiscard(card, isFinalDiscard: false)) {
      final resolution = ClassicHareegMistakePresetRules.resolve(
        preset: preset,
        mistake: MistakeType.normalJokerDiscard,
      );
      return ClassicHareegDiscardEligibility(
        card: card,
        scenario: ClassicHareegDiscardScenario.normalJoker,
        isAllowed: false,
        shouldAdvertise: false,
        actionPrefix: ClassicHareegActionIds.discardJokerPrefix,
        message: resolution.message,
        isFinalDiscard: false,
        mistakeType: MistakeType.normalJokerDiscard,
        mistakeResolution: resolution,
      );
    }

    final coverResult = ClassicHareegCoverRules.canDiscard(
      tableMelds: tableMelds,
      candidate: card,
      isFinalDiscard: false,
    );
    final isCover = !coverResult.canDiscard;
    if (isCover || blocksJokerReplacement) {
      final resolution = ClassicHareegMistakePresetRules.resolve(
        preset: preset,
        mistake: MistakeType.illegalCoverDiscard,
      );
      final scenario = switch ((isCover, blocksJokerReplacement)) {
        (true, true) => ClassicHareegDiscardScenario.coverAndJokerReplacement,
        (true, false) => ClassicHareegDiscardScenario.cover,
        (false, true) => ClassicHareegDiscardScenario.jokerReplacement,
        (false, false) => ClassicHareegDiscardScenario.normal,
      };
      return ClassicHareegDiscardEligibility(
        card: card,
        scenario: scenario,
        isAllowed: resolution.isAllowed,
        shouldAdvertise: resolution.isAllowed,
        actionPrefix: ClassicHareegActionIds.discardBlockedCoverPrefix,
        message: resolution.isAllowed
            ? resolution.message
            : _blockedTableCardMessage(
                isCover: isCover,
                blocksJokerReplacement: blocksJokerReplacement,
                coverMessage: coverResult.message,
              ),
        isFinalDiscard: false,
        mistakeType: MistakeType.illegalCoverDiscard,
        mistakeResolution: resolution,
      );
    }

    return ClassicHareegDiscardEligibility(
      card: card,
      scenario: ClassicHareegDiscardScenario.normal,
      isAllowed: true,
      shouldAdvertise: true,
      actionPrefix: ClassicHareegActionIds.discardPrefix,
      message: 'Card can be discarded.',
      isFinalDiscard: false,
    );
  }
}

String _blockedTableCardMessage({
  required bool isCover,
  required bool blocksJokerReplacement,
  required String coverMessage,
}) {
  if (isCover && blocksJokerReplacement) {
    return 'This card is a cover or joker replacement and cannot be discarded normally.';
  }
  if (isCover) {
    return coverMessage;
  }
  return 'This card can replace a table joker and cannot be discarded normally.';
}
