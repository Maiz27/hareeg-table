import '../models/playing_card.dart';

/// Recognized Classic Hareeg meld shapes.
enum MeldType {
  /// Same rank, different suits.
  set,

  /// Same suit, consecutive ranks.
  sequence,
}

/// Result of validating a selected group of cards as a meld.
class MeldValidationResult {
  /// Creates a validation result.
  const MeldValidationResult({
    required this.isValid,
    required this.message,
    this.type,
    this.value = 0,
  });

  /// Valid result helper.
  const MeldValidationResult.valid({
    required MeldType this.type,
    required this.value,
    required this.message,
  }) : isValid = true;

  /// Invalid result helper.
  const MeldValidationResult.invalid(this.message)
    : isValid = false,
      type = null,
      value = 0;

  /// Whether the selected group is a legal meld.
  final bool isValid;

  /// Meld type when valid.
  final MeldType? type;

  /// Opening value captured for this meld.
  final int value;

  /// Player-facing explanation suitable for table feedback.
  final String message;
}

/// Validates basic Classic Hareeg set and sequence melds.
abstract final class ClassicHareegMeldValidator {
  /// Validates a selected group of physical cards.
  static MeldValidationResult validate(List<HareegCard> cards) {
    if (cards.length < 3) {
      return const MeldValidationResult.invalid(
        'Select at least three cards for a meld.',
      );
    }

    final identities = <CardIdentity>[];
    for (final card in cards) {
      final identity = card.effectiveIdentity;
      if (identity == null) {
        return const MeldValidationResult.invalid(
          'Choose what each joker represents before validating.',
        );
      }
      identities.add(identity);
    }

    if (_hasDuplicateVisualCards(identities)) {
      return const MeldValidationResult.invalid(
        'A single meld cannot contain duplicate visual cards.',
      );
    }

    final set = _validateSet(identities);
    if (set.isValid) {
      return set;
    }

    final sequence = _validateSequence(identities);
    if (sequence.isValid) {
      return sequence;
    }

    return const MeldValidationResult.invalid(
      'Cards must form a same-rank set or same-suit sequence.',
    );
  }

  static bool _hasDuplicateVisualCards(List<CardIdentity> identities) {
    final keys = <String>{};
    for (final identity in identities) {
      if (!keys.add(identity.key)) {
        return true;
      }
    }
    return false;
  }

  static MeldValidationResult _validateSet(List<CardIdentity> identities) {
    final rank = identities.first.rank;
    if (identities.any((identity) => identity.rank != rank)) {
      return const MeldValidationResult.invalid('Not a set.');
    }

    final suits = identities.map((identity) => identity.suit).toSet();
    if (suits.length != identities.length) {
      return const MeldValidationResult.invalid('A set needs different suits.');
    }

    return MeldValidationResult.valid(
      type: MeldType.set,
      value: identities.fold<int>(0, (total, identity) {
        return total + identity.rank.value;
      }),
      message: 'Valid set.',
    );
  }

  static MeldValidationResult _validateSequence(List<CardIdentity> identities) {
    final suit = identities.first.suit;
    if (identities.any((identity) => identity.suit != suit)) {
      return const MeldValidationResult.invalid('Not a sequence.');
    }

    final lowAceOrders =
        identities.map((identity) => identity.rank.order).toList()..sort();
    final highAceOrders = identities.map((identity) {
      return identity.rank == CardRank.ace ? 14 : identity.rank.order;
    }).toList()..sort();

    if (_isConsecutive(lowAceOrders)) {
      return MeldValidationResult.valid(
        type: MeldType.sequence,
        value: _sequenceValue(lowAceOrders, lowAce: true),
        message: 'Valid low-ace sequence.',
      );
    }

    if (_isConsecutive(highAceOrders)) {
      return MeldValidationResult.valid(
        type: MeldType.sequence,
        value: _sequenceValue(highAceOrders, lowAce: false),
        message: 'Valid high-ace sequence.',
      );
    }

    return const MeldValidationResult.invalid('Not a sequence.');
  }

  static bool _isConsecutive(List<int> orders) {
    for (var index = 1; index < orders.length; index += 1) {
      if (orders[index] != orders[index - 1] + 1) {
        return false;
      }
    }
    return true;
  }

  static int _sequenceValue(List<int> orders, {required bool lowAce}) {
    var total = 0;
    for (final order in orders) {
      if (lowAce && order == 1) {
        total += orders.contains(5) ? 1 : 10;
      } else if (order >= 10) {
        total += 10;
      } else {
        total += order;
      }
    }
    return total;
  }
}
