import 'dart:math';

import '../models/classic_hareeg_setup.dart';
import '../models/player_seat.dart';
import '../models/playing_card.dart';
import '../rules/classic_hareeg_rules.dart';

/// Current turn phase for a dealt Classic Hareeg round.
enum TurnPhase {
  /// Player must draw from stock or take the previous discard.
  draw,

  /// Player may play cards, then must discard unless finishing.
  action;

  /// Parses a saved turn phase name.
  static TurnPhase? fromName(String? name) {
    if (name == null) {
      return null;
    }

    for (final phase in TurnPhase.values) {
      if (phase.name == name) {
        return phase;
      }
    }

    return null;
  }
}

/// Dealt round state for the first playable table slice.
class ClassicHareegRound {
  /// Creates a dealt round snapshot.
  const ClassicHareegRound({
    required this.rules,
    required this.setup,
    required this.seed,
    required this.hands,
    required this.stock,
    required this.discardPile,
    required this.starter,
    required this.currentSeat,
    required this.turnPhase,
    required this.activeSeats,
  });

  /// Deals a new Classic Hareeg round.
  factory ClassicHareegRound.deal({
    required ClassicHareegSetup setup,
    ClassicHareegRules? rules,
    List<PlayerSeat>? activeSeats,
    PlayerSeat? starterOverride,
    int? seed,
  }) {
    final activeRules = rules ?? ClassicHareegRules.defaults();
    final activeSeatList = List<PlayerSeat>.unmodifiable(
      activeSeats ?? PlayerSeat.values,
    );
    if (activeSeatList.isEmpty) {
      throw StateError('Classic Hareeg needs at least one active seat.');
    }

    final deck = _buildDeck(
      setup,
      activeRules,
      activeSeatCount: activeSeatList.length,
    );
    final effectiveSeed = seed ?? Random().nextInt(0x7FFFFFFF);
    final random = Random(effectiveSeed);
    deck.shuffle(random);

    final starter = _chooseStarter(
      setup,
      random,
      activeSeatList,
      starterOverride,
    );
    final hands = <PlayerSeat, List<HareegCard>>{
      for (final seat in PlayerSeat.values) seat: const <HareegCard>[],
    };
    var cursor = 0;

    for (final seat in activeSeatList) {
      final count = seat == starter
          ? activeRules.starterCardCount
          : activeRules.cardsPerPlayer;
      hands[seat] = List.unmodifiable(deck.skip(cursor).take(count));
      cursor += count;
    }

    return ClassicHareegRound(
      rules: activeRules,
      setup: setup,
      seed: effectiveSeed,
      hands: Map.unmodifiable(hands),
      stock: List.unmodifiable(deck.skip(cursor)),
      discardPile: const [],
      starter: starter,
      currentSeat: starter,
      turnPhase: TurnPhase.action,
      activeSeats: activeSeatList,
    );
  }

  /// Rules active for this round.
  final ClassicHareegRules rules;

  /// Setup values used to deal this round.
  final ClassicHareegSetup setup;

  /// Seed used to shuffle this round.
  final int seed;

  /// Cards held by each active seat.
  final Map<PlayerSeat, List<HareegCard>> hands;

  /// Face-down stock.
  final List<HareegCard> stock;

  /// Face-up discard pile.
  final List<HareegCard> discardPile;

  /// Seat that received 15 cards and starts in action phase.
  final PlayerSeat starter;

  /// Seat whose turn is active.
  final PlayerSeat currentSeat;

  /// Current turn phase.
  final TurnPhase turnPhase;

  /// Seats still active in this dealt round.
  final List<PlayerSeat> activeSeats;

  /// Anti-clockwise order beginning from the starter.
  List<PlayerSeat> get turnOrder {
    return _orderedActiveSeats(activeSeats, starter);
  }

  /// Cards for a seat.
  List<HareegCard> handFor(PlayerSeat seat) {
    return hands[seat] ?? const [];
  }

  /// Hand count for a seat.
  int cardCountFor(PlayerSeat seat) {
    return handFor(seat).length;
  }

  /// Top discard, if any.
  HareegCard? get topDiscard {
    if (discardPile.isEmpty) {
      return null;
    }
    return discardPile.last;
  }

  static PlayerSeat _chooseStarter(
    ClassicHareegSetup setup,
    Random random,
    List<PlayerSeat> activeSeats,
    PlayerSeat? starterOverride,
  ) {
    if (starterOverride != null) {
      if (!activeSeats.contains(starterOverride)) {
        throw StateError('Starter must be an active seat.');
      }
      return starterOverride;
    }

    return switch (setup.starterMode) {
      StarterMode.human =>
        activeSeats.contains(PlayerSeat.south)
            ? PlayerSeat.south
            : activeSeats.first,
      StarterMode.random => activeSeats[random.nextInt(activeSeats.length)],
    };
  }

  static List<HareegCard> _buildDeck(
    ClassicHareegSetup setup,
    ClassicHareegRules rules, {
    required int activeSeatCount,
  }) {
    if (setup.deckCount <= 0) {
      throw StateError('Classic Hareeg needs at least one deck to deal.');
    }

    final cards = <HareegCard>[];
    for (var deck = 0; deck < setup.deckCount; deck += 1) {
      for (final suit in CardSuit.values) {
        for (final rank in CardRank.values) {
          cards.add(
            HareegCard.standard(rank: rank, suit: suit, deckIndex: deck),
          );
        }
      }
    }

    for (var joker = 0; joker < setup.jokerCount; joker += 1) {
      cards.add(HareegCard.joker(deckIndex: joker ~/ 2, jokerIndex: joker));
    }

    final requiredCards =
        rules.starterCardCount + (rules.cardsPerPlayer * (activeSeatCount - 1));
    if (cards.length < requiredCards) {
      throw StateError(
        'Classic Hareeg needs at least $requiredCards cards to deal four seats.',
      );
    }

    return cards;
  }
}

List<PlayerSeat> _orderedActiveSeats(
  List<PlayerSeat> activeSeats,
  PlayerSeat starter,
) {
  final order = <PlayerSeat>[starter];
  var next = starter.nextAntiClockwise;
  while (next != starter) {
    if (activeSeats.contains(next)) {
      order.add(next);
    }
    next = next.nextAntiClockwise;
  }
  return List.unmodifiable(order);
}
