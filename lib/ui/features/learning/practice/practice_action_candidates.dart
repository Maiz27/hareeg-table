import '../../../../domain/classic_hareeg/game/classic_hareeg_action.dart';

/// One action the teaching surface can offer as a button right now.
class PracticeActionCandidate {
  /// Creates a candidate.
  const PracticeActionCandidate({required this.action});

  /// Parsed engine action behind the button.
  final ClassicHareegActionDescriptor action;

  /// Raw action id submitted on tap.
  String get actionId => action.id;

  /// Whether this candidate consumes the player's card selection.
  bool get usesSelection {
    return switch (action.kind) {
      ClassicHareegActionKind.drawStock ||
      ClassicHareegActionKind.takeDiscard ||
      ClassicHareegActionKind.usePendingDiscard ||
      ClassicHareegActionKind.returnPendingDiscard ||
      ClassicHareegActionKind.returnOpeningMelds ||
      ClassicHareegActionKind.claimFifty => false,
      _ => true,
    };
  }
}

/// Matches the step's allowed engine actions against the player's current
/// hand selection.
///
/// Selection-free actions (draw, take discard, return pending, claim Fifty)
/// are always offered. Card-bearing actions are offered only when the player's
/// selected card ids exactly match the action's payload, so the surface stays
/// honest: every visible button is one specific legal engine action.
List<PracticeActionCandidate> practiceActionCandidates({
  required List<ClassicHareegActionDescriptor> allowed,
  required Set<String> selectedCardIds,
}) {
  final candidates = <PracticeActionCandidate>[];
  final seenSelectionFreeKinds = <ClassicHareegActionKind>{};

  for (final action in allowed) {
    switch (action.kind) {
      case ClassicHareegActionKind.drawStock:
      case ClassicHareegActionKind.takeDiscard:
      case ClassicHareegActionKind.usePendingDiscard:
      case ClassicHareegActionKind.returnPendingDiscard:
      case ClassicHareegActionKind.returnOpeningMelds:
      case ClassicHareegActionKind.claimFifty:
        if (seenSelectionFreeKinds.add(action.kind)) {
          candidates.add(PracticeActionCandidate(action: action));
        }
      case ClassicHareegActionKind.discard:
      case ClassicHareegActionKind.discardBlockedCover:
      case ClassicHareegActionKind.discardJoker:
        final cardId = action.cardId;
        if (cardId != null &&
            selectedCardIds.length == 1 &&
            selectedCardIds.contains(cardId)) {
          candidates.add(PracticeActionCandidate(action: action));
        }
      case ClassicHareegActionKind.replaceJoker:
        final cardId = action.cardId;
        if (cardId != null &&
            selectedCardIds.length == 1 &&
            selectedCardIds.contains(cardId)) {
          candidates.add(PracticeActionCandidate(action: action));
        }
      case ClassicHareegActionKind.playMeld:
      case ClassicHareegActionKind.playMeldWithJoker:
      case ClassicHareegActionKind.placeCover:
        if (action.cardIds.isNotEmpty &&
            selectedCardIds.length == action.cardIds.length &&
            selectedCardIds.containsAll(action.cardIds)) {
          candidates.add(PracticeActionCandidate(action: action));
        }
      case ClassicHareegActionKind.returnTablePlay:
      case ClassicHareegActionKind.unknown:
        break;
    }
  }

  return candidates;
}
