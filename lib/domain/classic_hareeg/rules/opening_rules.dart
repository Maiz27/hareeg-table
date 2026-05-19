import '../models/player_seat.dart';
import '../models/playing_card.dart';
import 'meld_validator.dart';

/// Snapshot of a placed meld value at the time it was played.
class PlacedMeld {
  /// Creates a placed meld snapshot.
  const PlacedMeld({
    required this.cards,
    required this.valueSnapshot,
    this.coverValue = 0,
  });

  /// Builds a placed meld from cards after validating them.
  factory PlacedMeld.fromCards(List<HareegCard> cards) {
    final result = ClassicHareegMeldValidator.validate(cards);
    if (!result.isValid) {
      throw ArgumentError(result.message);
    }

    return PlacedMeld(
      cards: List.unmodifiable(cards),
      valueSnapshot: result.value,
    );
  }

  /// Restores a placed meld from persisted JSON-compatible data.
  factory PlacedMeld.fromJson(Map<String, Object?> json) {
    final cardsJson = _asList(json['cards']);
    final valueSnapshot = _asInt(json['valueSnapshot']);
    final coverValue = _asInt(json['coverValue']) ?? 0;
    if (cardsJson == null || valueSnapshot == null) {
      throw const FormatException('Invalid placed meld.');
    }

    return PlacedMeld(
      cards: List.unmodifiable(_cardsFromJson(cardsJson)),
      valueSnapshot: valueSnapshot,
      coverValue: coverValue,
    );
  }

  /// Cards originally placed as the meld.
  final List<HareegCard> cards;

  /// Value captured when the meld was placed.
  final int valueSnapshot;

  /// Later cover value added without recalculating the original meld.
  final int coverValue;

  /// Total table contribution from original meld plus later covers.
  int get totalValue => valueSnapshot + coverValue;

  /// Returns a new snapshot with cover value added.
  PlacedMeld addCoverValue(int value) {
    return PlacedMeld(
      cards: cards,
      valueSnapshot: valueSnapshot,
      coverValue: coverValue + value,
    );
  }

  /// Returns a new snapshot with cover cards appended.
  PlacedMeld addCoverCards(List<HareegCard> coverCards) {
    final addedValue = coverCards.fold<int>(0, (total, card) {
      return total + (card.effectiveIdentity?.rank.value ?? 0);
    });
    return PlacedMeld(
      cards: List.unmodifiable([...cards, ...coverCards]),
      valueSnapshot: valueSnapshot,
      coverValue: coverValue + addedValue,
    );
  }

  /// Converts the meld to JSON-compatible data.
  Map<String, Object?> toJson() {
    return {
      'cards': cards.map((card) => card.toJson()).toList(),
      'valueSnapshot': valueSnapshot,
      'coverValue': coverValue,
    };
  }
}

/// Opening benchmark state for one Classic Hareeg round.
class OpeningState {
  /// Creates opening benchmark state.
  const OpeningState({
    required this.baseRequirement,
    required this.currentRequirement,
    required this.openedSeats,
    this.benchmarkOwner,
    this.isLocked = false,
  });

  /// Creates the initial opening state.
  factory OpeningState.initial(int requirement) {
    return OpeningState(
      baseRequirement: requirement,
      currentRequirement: requirement,
      openedSeats: const {},
    );
  }

  /// Restores opening benchmark state from persisted JSON-compatible data.
  factory OpeningState.fromJson(Map<String, Object?> json) {
    final baseRequirement = _asInt(json['baseRequirement']);
    final currentRequirement = _asInt(json['currentRequirement']);
    final openedSeatNames = _asList(json['openedSeats']);
    if (baseRequirement == null ||
        currentRequirement == null ||
        openedSeatNames == null) {
      throw const FormatException('Invalid opening state.');
    }

    final openedSeats = <PlayerSeat>{};
    for (final seatName in openedSeatNames) {
      final seat = PlayerSeat.fromName(seatName is String ? seatName : null);
      if (seat == null) {
        throw const FormatException('Invalid opened seat.');
      }
      openedSeats.add(seat);
    }

    final owner = PlayerSeat.fromName(_asString(json['benchmarkOwner']));
    final isLocked = json['isLocked'] == true;

    return OpeningState(
      baseRequirement: baseRequirement,
      currentRequirement: currentRequirement,
      openedSeats: Set.unmodifiable(openedSeats),
      benchmarkOwner: owner,
      isLocked: isLocked,
    );
  }

  /// Configured base requirement, such as 51 or 75.
  final int baseRequirement;

  /// Current requirement after benchmark pressure.
  final int currentRequirement;

  /// First opener while benchmark is unlocked.
  final PlayerSeat? benchmarkOwner;

  /// Whether the benchmark is permanently locked.
  final bool isLocked;

  /// Seats that have opened this round.
  final Set<PlayerSeat> openedSeats;

  /// Whether a seat has opened.
  bool hasOpened(PlayerSeat seat) {
    return openedSeats.contains(seat);
  }

  /// Converts opening benchmark state to JSON-compatible data.
  Map<String, Object?> toJson() {
    return {
      'baseRequirement': baseRequirement,
      'currentRequirement': currentRequirement,
      'benchmarkOwner': benchmarkOwner?.name,
      'isLocked': isLocked,
      'openedSeats': openedSeats.map((seat) => seat.name).toList(),
    };
  }
}

List<HareegCard> _cardsFromJson(List<Object?> cardsJson) {
  final cards = <HareegCard>[];
  for (final cardJson in cardsJson) {
    final cardMap = _asMap(cardJson);
    if (cardMap == null) {
      throw const FormatException('Invalid placed meld card.');
    }
    cards.add(HareegCard.fromJson(cardMap));
  }
  return cards;
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

List<Object?>? _asList(Object? value) {
  if (value is List) {
    return value;
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

String? _asString(Object? value) {
  return value is String ? value : null;
}

/// Result of checking an opening attempt.
class OpeningValidationResult {
  /// Creates an opening validation result.
  const OpeningValidationResult({
    required this.isValid,
    required this.value,
    required this.message,
  });

  /// Whether the opening attempt is legal.
  final bool isValid;

  /// Combined value of the proposed opening melds.
  final int value;

  /// Player-facing explanation.
  final String message;
}

/// Classic Hareeg opening and benchmark rules.
abstract final class ClassicHareegOpeningRules {
  /// Validates a proposed opening from one or more new melds.
  static OpeningValidationResult validateOpening({
    required OpeningState state,
    required PlayerSeat seat,
    required List<PlacedMeld> melds,
    bool containsCovers = false,
  }) {
    if (state.hasOpened(seat)) {
      return const OpeningValidationResult(
        isValid: false,
        value: 0,
        message: 'This player has already opened.',
      );
    }

    if (containsCovers) {
      return const OpeningValidationResult(
        isValid: false,
        value: 0,
        message: 'Covers cannot satisfy opening.',
      );
    }

    if (melds.isEmpty) {
      return const OpeningValidationResult(
        isValid: false,
        value: 0,
        message: 'Opening needs at least one meld.',
      );
    }

    final value = melds.fold<int>(0, (total, meld) => total + meld.totalValue);
    if (value < state.currentRequirement) {
      return OpeningValidationResult(
        isValid: false,
        value: value,
        message: 'Opening value $value is below ${state.currentRequirement}.',
      );
    }

    return OpeningValidationResult(
      isValid: true,
      value: value,
      message: 'Opening value $value is sufficient.',
    );
  }

  /// Applies a valid opening and returns the next benchmark state.
  static OpeningState applyOpening({
    required OpeningState state,
    required PlayerSeat seat,
    required List<PlacedMeld> melds,
    bool containsCovers = false,
  }) {
    final validation = validateOpening(
      state: state,
      seat: seat,
      melds: melds,
      containsCovers: containsCovers,
    );
    if (!validation.isValid) {
      throw StateError(validation.message);
    }

    final openedSeats = {...state.openedSeats, seat};
    final owner = state.benchmarkOwner;

    if (owner == null) {
      return OpeningState(
        baseRequirement: state.baseRequirement,
        currentRequirement: validation.value > state.baseRequirement
            ? validation.value
            : state.baseRequirement,
        benchmarkOwner: seat,
        openedSeats: Set.unmodifiable(openedSeats),
      );
    }

    return OpeningState(
      baseRequirement: state.baseRequirement,
      currentRequirement: state.currentRequirement,
      benchmarkOwner: owner,
      isLocked: seat != owner || state.isLocked,
      openedSeats: Set.unmodifiable(openedSeats),
    );
  }

  /// Records extra table value from the benchmark owner before the lock.
  static OpeningState recordBenchmarkContribution({
    required OpeningState state,
    required PlayerSeat seat,
    required int value,
  }) {
    if (state.isLocked || state.benchmarkOwner != seat || value <= 0) {
      return state;
    }

    return OpeningState(
      baseRequirement: state.baseRequirement,
      currentRequirement: state.currentRequirement + value,
      benchmarkOwner: state.benchmarkOwner,
      openedSeats: state.openedSeats,
    );
  }
}
