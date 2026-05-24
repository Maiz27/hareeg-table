import '../models/player_seat.dart';
import '../models/playing_card.dart';
import '../rules/joker_meld_assignment.dart';

export '../rules/joker_meld_assignment.dart' show JokerMeldAssignment;

/// Stable categories for Classic Hareeg action ids.
enum ClassicHareegActionKind {
  /// Draw one card from stock.
  drawStock,

  /// Take the previous player's discard into pending state.
  takeDiscard,

  /// Commit a pending discard as used.
  usePendingDiscard,

  /// Return a pending discard to the discard pile.
  returnPendingDiscard,

  /// Take back uncommitted opening melds.
  returnOpeningMelds,

  /// Take back one specific reversible table play.
  returnTablePlay,

  /// Claim Fifty / Khamsin.
  claimFifty,

  /// Play selected cards as a meld.
  playMeld,

  /// Play selected cards as a meld with an explicit joker identity.
  playMeldWithJoker,

  /// Place cover cards on an existing meld.
  placeCover,

  /// Replace a represented joker on the table.
  replaceJoker,

  /// Discard a plain legal card.
  discard,

  /// Discard a cover/replacement card under a penalty-capable preset.
  discardBlockedCover,

  /// Discard a joker under a final-discard exception.
  discardJoker,

  /// Unknown or malformed action id.
  unknown,
}

/// Parsed meaning of one Classic Hareeg action id.
class ClassicHareegActionDescriptor {
  /// Creates an action descriptor.
  const ClassicHareegActionDescriptor({
    required this.id,
    required this.kind,
    this.cardId,
    this.cardIds = const [],
    this.jokerMeldChoice,
    this.coverTarget,
    this.jokerReplacementTarget,
    this.returnTablePlayTarget,
  });

  /// Raw action id used at the controller seam.
  final String id;

  /// Stable action category.
  final ClassicHareegActionKind kind;

  /// Single card id for discard and joker-replacement actions.
  final String? cardId;

  /// Selected card ids for meld and cover actions.
  final List<String> cardIds;

  /// Explicit joker identity choice for an ambiguous meld.
  final JokerMeldActionChoice? jokerMeldChoice;

  /// Cover target parsed from the action id.
  final CoverActionTarget? coverTarget;

  /// Joker replacement target parsed from the action id.
  final JokerReplacementActionTarget? jokerReplacementTarget;

  /// Table-play return target parsed from the action id.
  final ReturnTablePlayTarget? returnTablePlayTarget;

  /// Whether the action discards one card.
  bool get isDiscard {
    return switch (kind) {
      ClassicHareegActionKind.discard ||
      ClassicHareegActionKind.discardBlockedCover ||
      ClassicHareegActionKind.discardJoker => true,
      _ => false,
    };
  }

  /// Whether the action is a safe plain discard.
  bool get isSafeDiscard => kind == ClassicHareegActionKind.discard;

  /// Whether the action is a mistake-class advertisement.
  ///
  /// True for [ClassicHareegActionKind.discardBlockedCover] and
  /// [ClassicHareegActionKind.discardJoker] — the two discard ids the rules
  /// engine surfaces only because Strict/Table tiers accept them as paid
  /// mistakes. Under tiers where `cpuMistakesAllowed` is false (Coaching,
  /// Standard, Strict), the CPU action surface filters these out so the
  /// runner cannot loop into a repeated penalty.
  bool get isMistake {
    return switch (kind) {
      ClassicHareegActionKind.discardBlockedCover ||
      ClassicHareegActionKind.discardJoker => true,
      _ => false,
    };
  }

  /// Whether the action places selected cards as a meld.
  bool get isMeldPlay {
    return switch (kind) {
      ClassicHareegActionKind.playMeld ||
      ClassicHareegActionKind.playMeldWithJoker => true,
      _ => false,
    };
  }

  /// Whether the action can introduce a newly declared joker on the table.
  /// Used by UI flows that diff the table state before/after applyAction —
  /// draw/discard/take-discard never produce a new joker placement.
  bool get canPlaceJoker {
    return switch (kind) {
      ClassicHareegActionKind.playMeld ||
      ClassicHareegActionKind.playMeldWithJoker ||
      ClassicHareegActionKind.placeCover => true,
      _ => false,
    };
  }

  /// Whether the action mutates table cards rather than drawing.
  bool get isTablePlay {
    return switch (kind) {
      ClassicHareegActionKind.playMeld ||
      ClassicHareegActionKind.playMeldWithJoker ||
      ClassicHareegActionKind.placeCover ||
      ClassicHareegActionKind.replaceJoker ||
      ClassicHareegActionKind.returnTablePlay => true,
      _ => false,
    };
  }

  /// Whether a human card selection should be cleared after this action.
  bool get clearsSelection {
    return isDiscard ||
        isTablePlay ||
        kind == ClassicHareegActionKind.returnOpeningMelds ||
        kind == ClassicHareegActionKind.returnPendingDiscard;
  }
}

/// Action ids used by the Classic Hareeg game engine.
///
/// The raw string form is intentionally kept at the controller seam. Callers
/// that need action meaning should use [describe] so parsing and category rules
/// stay local to this module.
abstract final class ClassicHareegActionIds {
  /// Draw one card from stock.
  static const drawStock = 'draw-stock';

  /// Take the previous player's discard into pending state.
  static const takeDiscard = 'take-discard';

  /// Commit a pending discard as used (advances to discard phase).
  static const usePendingDiscard = 'use-pending-discard';

  /// Return a pending discard and draw from stock instead.
  static const returnPendingDiscard = 'return-pending-discard';

  /// Take back uncommitted opening melds that did not satisfy the benchmark.
  static const returnOpeningMelds = 'return-opening-melds';

  /// Take back one specific reversible table play from this turn.
  static const returnTablePlayPrefix = 'return-table-play:';

  /// Claim Fifty / Khamsin from the immediate previous discard.
  static const claimFifty = 'claim-fifty';

  /// Play selected cards as a meld. Card ids follow the prefix, comma-separated.
  static const playMeldPrefix = 'play-meld:';

  /// Play selected cards with an explicit represented identity for one joker.
  static const playMeldWithJokerPrefix = 'play-meld-joker:';

  /// Play selected cards with explicit represented identities for jokers.
  static const playMeldWithJokersPrefix = 'play-meld-jokers:';

  /// Place selected cover cards on an existing meld.
  static const placeCoverPrefix = 'place-cover:';

  /// Replace a represented joker on the table with a matching real card.
  static const replaceJokerPrefix = 'replace-joker:';

  /// Discard action id prefix for plain legal discards.
  static const discardPrefix = 'discard:';

  /// Discard action id prefix for cards that are covers (only legal as final
  /// discard, or under presets that allow cover discards with a penalty).
  static const discardBlockedCoverPrefix = 'discard-blocked-cover:';

  /// Discard action id prefix for jokers (only legal as final discard, or under
  /// presets that allow joker discards with a penalty).
  static const discardJokerPrefix = 'discard-joker:';

  /// Returns a parsed descriptor for [actionId].
  static ClassicHareegActionDescriptor describe(String actionId) {
    final jokerChoice = jokerMeldChoice(actionId);
    if (jokerChoice != null) {
      return ClassicHareegActionDescriptor(
        id: actionId,
        kind: ClassicHareegActionKind.playMeldWithJoker,
        cardIds: jokerChoice.cardIds,
        jokerMeldChoice: jokerChoice,
      );
    }

    final meldCards = meldCardIds(actionId);
    if (meldCards != null) {
      return ClassicHareegActionDescriptor(
        id: actionId,
        kind: ClassicHareegActionKind.playMeld,
        cardIds: meldCards,
      );
    }

    final cover = coverActionTarget(actionId);
    if (cover != null) {
      return ClassicHareegActionDescriptor(
        id: actionId,
        kind: ClassicHareegActionKind.placeCover,
        cardIds: cover.cardIds,
        coverTarget: cover,
      );
    }

    final replacement = jokerReplacementTarget(actionId);
    if (replacement != null) {
      return ClassicHareegActionDescriptor(
        id: actionId,
        kind: ClassicHareegActionKind.replaceJoker,
        cardId: replacement.cardId,
        jokerReplacementTarget: replacement,
      );
    }

    final returnTarget = returnTablePlayTarget(actionId);
    if (returnTarget != null) {
      return ClassicHareegActionDescriptor(
        id: actionId,
        kind: ClassicHareegActionKind.returnTablePlay,
        returnTablePlayTarget: returnTarget,
      );
    }

    for (final (prefix, kind) in const [
      (discardBlockedCoverPrefix, ClassicHareegActionKind.discardBlockedCover),
      (discardJokerPrefix, ClassicHareegActionKind.discardJoker),
      (discardPrefix, ClassicHareegActionKind.discard),
    ]) {
      if (actionId.startsWith(prefix)) {
        return ClassicHareegActionDescriptor(
          id: actionId,
          kind: kind,
          cardId: actionId.substring(prefix.length),
        );
      }
    }

    final exactKind = switch (actionId) {
      drawStock => ClassicHareegActionKind.drawStock,
      takeDiscard => ClassicHareegActionKind.takeDiscard,
      usePendingDiscard => ClassicHareegActionKind.usePendingDiscard,
      returnPendingDiscard => ClassicHareegActionKind.returnPendingDiscard,
      returnOpeningMelds => ClassicHareegActionKind.returnOpeningMelds,
      claimFifty => ClassicHareegActionKind.claimFifty,
      _ => ClassicHareegActionKind.unknown,
    };

    return ClassicHareegActionDescriptor(id: actionId, kind: exactKind);
  }

  /// Returns whether [actionId] has [kind].
  static bool hasKind(String actionId, ClassicHareegActionKind kind) {
    return describe(actionId).kind == kind;
  }

  /// Returns the card id encoded in a discard action id, if present.
  static String? discardCardId(String actionId) {
    final action = describe(actionId);
    return action.isDiscard ? action.cardId : null;
  }

  /// Creates a play-meld action id for selected physical card ids.
  static String playMeldActionId(Iterable<String> cardIds) {
    return '$playMeldPrefix${cardIds.join(',')}';
  }

  /// Returns the card ids encoded in a play-meld action id, if present.
  static List<String>? meldCardIds(String actionId) {
    if (!actionId.startsWith(playMeldPrefix)) {
      return null;
    }
    return actionId
        .substring(playMeldPrefix.length)
        .split(',')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }

  /// Creates a play-meld action id with an explicit joker representation.
  static String playMeldWithJokerIdentityActionId({
    required Iterable<String> cardIds,
    required String jokerId,
    required CardIdentity identity,
  }) {
    return '$playMeldWithJokerPrefix$jokerId:${identity.key}:${cardIds.join(',')}';
  }

  /// Creates a play-meld action id with explicit joker representations.
  static String playMeldWithJokerIdentitiesActionId({
    required Iterable<String> cardIds,
    required Iterable<JokerMeldAssignment> assignments,
  }) {
    final assignmentList = assignments.toList(growable: false);
    if (assignmentList.length == 1) {
      final assignment = assignmentList.single;
      return playMeldWithJokerIdentityActionId(
        cardIds: cardIds,
        jokerId: assignment.jokerId,
        identity: assignment.identity,
      );
    }

    final encodedAssignments = assignmentList
        .map((assignment) {
          return '${assignment.jokerId}=${assignment.identity.key}';
        })
        .join(',');
    return '$playMeldWithJokersPrefix$encodedAssignments:${cardIds.join(',')}';
  }

  /// Parses an explicit joker-representation meld action id.
  static JokerMeldActionChoice? jokerMeldChoice(String actionId) {
    final multi = _multiJokerMeldChoice(actionId);
    if (multi != null) {
      return multi;
    }

    if (!actionId.startsWith(playMeldWithJokerPrefix)) {
      return null;
    }
    final payload = actionId.substring(playMeldWithJokerPrefix.length);
    final parts = payload.split(':');
    if (parts.length != 3) {
      return null;
    }
    final identity = _identityFromKey(parts[1]);
    if (identity == null) {
      return null;
    }
    final cardIds = parts[2]
        .split(',')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    return JokerMeldActionChoice(
      jokerId: parts[0],
      identity: identity,
      cardIds: cardIds,
    );
  }

  static JokerMeldActionChoice? _multiJokerMeldChoice(String actionId) {
    if (!actionId.startsWith(playMeldWithJokersPrefix)) {
      return null;
    }
    final payload = actionId.substring(playMeldWithJokersPrefix.length);
    final parts = payload.split(':');
    if (parts.length != 2) {
      return null;
    }

    final assignments = <JokerMeldAssignment>[];
    for (final encoded in parts[0].split(',')) {
      final pair = encoded.split('=');
      if (pair.length != 2 || pair[0].isEmpty) {
        return null;
      }
      final identity = _identityFromKey(pair[1]);
      if (identity == null) {
        return null;
      }
      assignments.add(
        JokerMeldAssignment(jokerId: pair[0], identity: identity),
      );
    }
    if (assignments.isEmpty) {
      return null;
    }

    final cardIds = parts[1]
        .split(',')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    return JokerMeldActionChoice.withAssignments(
      assignments: assignments,
      cardIds: cardIds,
    );
  }

  /// Creates a place-cover action id.
  static String placeCoverActionId({
    required PlayerSeat targetSeat,
    required int meldIndex,
    required Iterable<String> cardIds,
  }) {
    return '$placeCoverPrefix${targetSeat.name}:$meldIndex:${cardIds.join(',')}';
  }

  /// Parses a place-cover action id.
  static CoverActionTarget? coverActionTarget(String actionId) {
    if (!actionId.startsWith(placeCoverPrefix)) {
      return null;
    }
    final payload = actionId.substring(placeCoverPrefix.length);
    final parts = payload.split(':');
    if (parts.length != 3) {
      return null;
    }
    final seat = PlayerSeat.fromName(parts[0]);
    final meldIndex = int.tryParse(parts[1]);
    if (seat == null || meldIndex == null) {
      return null;
    }
    final cardIds = parts[2]
        .split(',')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    return CoverActionTarget(
      targetSeat: seat,
      meldIndex: meldIndex,
      cardIds: cardIds,
    );
  }

  /// Creates a specific table-play return action id.
  static String returnTablePlayActionId({
    required PlayerSeat owner,
    required int meldIndex,
  }) {
    return '$returnTablePlayPrefix${owner.name}:$meldIndex';
  }

  /// Parses a specific table-play return action id.
  static ReturnTablePlayTarget? returnTablePlayTarget(String actionId) {
    if (!actionId.startsWith(returnTablePlayPrefix)) {
      return null;
    }
    final payload = actionId.substring(returnTablePlayPrefix.length);
    final parts = payload.split(':');
    if (parts.length != 2) {
      return null;
    }
    final owner = PlayerSeat.fromName(parts[0]);
    final meldIndex = int.tryParse(parts[1]);
    if (owner == null || meldIndex == null) {
      return null;
    }
    return ReturnTablePlayTarget(owner: owner, meldIndex: meldIndex);
  }

  /// Creates a joker replacement action id.
  static String replaceJokerActionId({
    required PlayerSeat targetSeat,
    required int meldIndex,
    required String cardId,
  }) {
    return '$replaceJokerPrefix${targetSeat.name}:$meldIndex:$cardId';
  }

  /// Parses a joker replacement action id.
  static JokerReplacementActionTarget? jokerReplacementTarget(String actionId) {
    if (!actionId.startsWith(replaceJokerPrefix)) {
      return null;
    }
    final payload = actionId.substring(replaceJokerPrefix.length);
    final parts = payload.split(':');
    if (parts.length != 3) {
      return null;
    }
    final seat = PlayerSeat.fromName(parts[0]);
    final meldIndex = int.tryParse(parts[1]);
    if (seat == null || meldIndex == null || parts[2].isEmpty) {
      return null;
    }
    return JokerReplacementActionTarget(
      targetSeat: seat,
      meldIndex: meldIndex,
      cardId: parts[2],
    );
  }
}

/// Explicit represented joker choice for a meld action.
class JokerMeldActionChoice {
  /// Creates a parsed joker meld choice.
  JokerMeldActionChoice({
    required this.jokerId,
    required this.identity,
    required Iterable<String> cardIds,
  }) : cardIds = List.unmodifiable(cardIds),
       assignments = List.unmodifiable([
         JokerMeldAssignment(jokerId: jokerId, identity: identity),
       ]);

  /// Creates a parsed joker meld choice with multiple joker assignments.
  JokerMeldActionChoice.withAssignments({
    required Iterable<JokerMeldAssignment> assignments,
    required Iterable<String> cardIds,
  }) : assignments = List.unmodifiable(assignments),
       cardIds = List.unmodifiable(cardIds),
       jokerId = assignments.first.jokerId,
       identity = assignments.first.identity;

  /// Physical joker id being assigned.
  final String jokerId;

  /// Represented identity selected for the joker.
  final CardIdentity identity;

  /// All represented identities selected for unresolved jokers in the meld.
  final List<JokerMeldAssignment> assignments;

  /// Physical card ids in the selected meld play.
  final List<String> cardIds;

  /// Action id that encodes this explicit represented-joker choice.
  String get actionId {
    return ClassicHareegActionIds.playMeldWithJokerIdentitiesActionId(
      cardIds: cardIds,
      assignments: assignments,
    );
  }
}

/// Parsed target for placing covers on an existing meld.
class CoverActionTarget {
  /// Creates a parsed cover action target.
  const CoverActionTarget({
    required this.targetSeat,
    required this.meldIndex,
    required this.cardIds,
  });

  /// Seat that owns the meld being extended.
  final PlayerSeat targetSeat;

  /// Index of the meld in the owner's table area.
  final int meldIndex;

  /// Physical cover card ids to place.
  final List<String> cardIds;
}

/// Parsed target for replacing a represented table joker.
class JokerReplacementActionTarget {
  /// Creates a parsed joker replacement target.
  const JokerReplacementActionTarget({
    required this.targetSeat,
    required this.meldIndex,
    required this.cardId,
  });

  /// Seat that owns the meld containing the represented joker.
  final PlayerSeat targetSeat;

  /// Index of the meld in the owner's table area.
  final int meldIndex;

  /// Physical replacement card id from the current player's hand.
  final String cardId;
}

/// Parsed target for returning one reversible table play.
class ReturnTablePlayTarget {
  /// Creates a parsed table-play return target.
  const ReturnTablePlayTarget({required this.owner, required this.meldIndex});

  /// Seat that owns the affected meld.
  final PlayerSeat owner;

  /// Index of the meld in the owner's table area.
  final int meldIndex;
}

CardIdentity? _identityFromKey(String key) {
  final parts = key.split('-');
  if (parts.length != 2) {
    return null;
  }
  final rank = CardRank.fromName(parts[0]);
  final suit = CardSuit.fromName(parts[1]);
  if (rank == null || suit == null) {
    return null;
  }
  return CardIdentity(rank: rank, suit: suit);
}
