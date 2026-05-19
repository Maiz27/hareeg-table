/// Suit identity for non-joker cards.
enum CardSuit {
  /// Clubs.
  clubs('C'),

  /// Diamonds.
  diamonds('D'),

  /// Hearts.
  hearts('H'),

  /// Spades.
  spades('S');

  const CardSuit(this.label);

  /// Compact label used on cards.
  final String label;

  /// Parses a saved suit name.
  static CardSuit? fromName(String? name) {
    return _enumByName(CardSuit.values, name);
  }
}

/// Rank identity for non-joker cards.
enum CardRank {
  /// Ace.
  ace('A', 1),

  /// Two.
  two('2', 2),

  /// Three.
  three('3', 3),

  /// Four.
  four('4', 4),

  /// Five.
  five('5', 5),

  /// Six.
  six('6', 6),

  /// Seven.
  seven('7', 7),

  /// Eight.
  eight('8', 8),

  /// Nine.
  nine('9', 9),

  /// Ten.
  ten('10', 10),

  /// Jack.
  jack('J', 11),

  /// Queen.
  queen('Q', 12),

  /// King.
  king('K', 13);

  const CardRank(this.label, this.order);

  /// Compact display label.
  final String label;

  /// Low-ace ordering value.
  final int order;

  /// Parses a saved rank name.
  static CardRank? fromName(String? name) {
    return _enumByName(CardRank.values, name);
  }

  /// Opening and meld value for the rank in the common case.
  int get value {
    return switch (this) {
      CardRank.ace => 10,
      CardRank.jack || CardRank.queen || CardRank.king => 10,
      _ => order,
    };
  }
}

/// Visual identity represented by a real card or table joker.
class CardIdentity {
  /// Creates a non-joker card identity.
  const CardIdentity({required this.rank, required this.suit});

  /// Restores a card identity from persisted JSON-compatible data.
  factory CardIdentity.fromJson(Map<String, Object?> json) {
    final rank = CardRank.fromName(_asString(json['rank']));
    final suit = CardSuit.fromName(_asString(json['suit']));
    if (rank == null || suit == null) {
      throw const FormatException('Invalid card identity.');
    }

    return CardIdentity(rank: rank, suit: suit);
  }

  /// Rank.
  final CardRank rank;

  /// Suit.
  final CardSuit suit;

  /// Stable key that ignores physical deck copy.
  String get key => '${rank.name}-${suit.name}';

  /// Compact player-facing label.
  String get label => '${rank.label}${suit.label}';

  /// Converts the identity to JSON-compatible data.
  Map<String, Object?> toJson() {
    return {'rank': rank.name, 'suit': suit.name};
  }

  @override
  bool operator ==(Object other) {
    return other is CardIdentity && other.rank == rank && other.suit == suit;
  }

  @override
  int get hashCode => Object.hash(rank, suit);
}

/// Physical card in a Classic Hareeg deck.
class HareegCard {
  /// Creates a standard physical card.
  HareegCard.standard({
    required CardRank rank,
    required CardSuit suit,
    required this.deckIndex,
  }) : identity = CardIdentity(rank: rank, suit: suit),
       jokerIndex = null,
       representedIdentity = null;

  /// Creates a physical joker.
  const HareegCard.joker({
    required this.deckIndex,
    required int this.jokerIndex,
    this.representedIdentity,
  }) : identity = null;

  /// Restores a physical card from persisted JSON-compatible data.
  factory HareegCard.fromJson(Map<String, Object?> json) {
    final deckIndex = _asInt(json['deckIndex']);
    if (deckIndex == null) {
      throw const FormatException('Invalid card deck index.');
    }

    final jokerIndex = _asInt(json['jokerIndex']);
    if (jokerIndex != null) {
      final represented = _asMap(json['representedIdentity']) == null
          ? null
          : CardIdentity.fromJson(_asMap(json['representedIdentity'])!);
      return HareegCard.joker(
        deckIndex: deckIndex,
        jokerIndex: jokerIndex,
        representedIdentity: represented,
      );
    }

    final identityJson = _asMap(json['identity']);
    if (identityJson == null) {
      throw const FormatException('Invalid standard card identity.');
    }

    final identity = CardIdentity.fromJson(identityJson);
    return HareegCard.standard(
      rank: identity.rank,
      suit: identity.suit,
      deckIndex: deckIndex,
    );
  }

  /// Non-joker identity, if this is a standard card.
  final CardIdentity? identity;

  /// Physical deck copy index.
  final int deckIndex;

  /// Physical joker index when this card is a joker.
  final int? jokerIndex;

  /// Identity assigned to a placed joker, when known.
  final CardIdentity? representedIdentity;

  /// Whether this card is a joker.
  bool get isJoker => jokerIndex != null;

  /// Identity used for meld and cover behavior when available.
  CardIdentity? get effectiveIdentity => identity ?? representedIdentity;

  /// Stable physical card id.
  String get id {
    final standard = identity;
    if (standard != null) {
      return 'deck-$deckIndex-${standard.key}';
    }
    return 'deck-$deckIndex-joker-$jokerIndex';
  }

  /// Compact player-facing label.
  String get label {
    final standard = identity;
    if (standard != null) {
      return standard.label;
    }

    final represented = representedIdentity;
    if (represented != null) {
      return 'J(${represented.label})';
    }

    return 'Joker';
  }

  /// Returns the same physical joker with a represented identity assigned.
  HareegCard asRepresenting(CardIdentity represented) {
    if (!isJoker) {
      throw StateError('Only jokers can receive a represented identity.');
    }

    return HareegCard.joker(
      deckIndex: deckIndex,
      jokerIndex: jokerIndex ?? 0,
      representedIdentity: represented,
    );
  }

  /// Returns the same physical joker with no represented identity.
  HareegCard withoutRepresentation() {
    if (!isJoker) {
      throw StateError('Only jokers can clear represented identity.');
    }

    return HareegCard.joker(deckIndex: deckIndex, jokerIndex: jokerIndex ?? 0);
  }

  /// Converts the physical card to JSON-compatible data.
  Map<String, Object?> toJson() {
    return {
      'deckIndex': deckIndex,
      'jokerIndex': jokerIndex,
      'identity': identity?.toJson(),
      'representedIdentity': representedIdentity?.toJson(),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is HareegCard && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

T? _enumByName<T extends Enum>(Iterable<T> values, String? name) {
  if (name == null) {
    return null;
  }

  for (final value in values) {
    if (value.name == name) {
      return value;
    }
  }

  return null;
}

int? _asInt(Object? value) {
  return switch (value) {
    int() => value,
    num() when value.isFinite && value % 1 == 0 => value.toInt(),
    String() => int.tryParse(value),
    _ => null,
  };
}

Map<String, Object?>? _asMap(Object? value) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  return null;
}

String? _asString(Object? value) {
  return value is String ? value : null;
}
