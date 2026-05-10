/// Immutable configuration for a Classic Hareeg ruleset.
///
/// This type belongs to the pure-Dart rules boundary and must not depend on
/// Flutter widgets, platform APIs, persistence, or CPU strategy code.
class ClassicHareegRules {
  /// Creates a Classic Hareeg ruleset configuration.
  const ClassicHareegRules({
    required this.seatCount,
    required this.cardsPerPlayer,
    required this.starterCardCount,
    required this.openingRequirement,
    required this.fiftyClaimSeconds,
    required this.eliminationScore,
  });

  /// Documented default rule values for the first Classic Hareeg release.
  factory ClassicHareegRules.defaults() {
    return const ClassicHareegRules(
      seatCount: 4,
      cardsPerPlayer: 14,
      starterCardCount: 15,
      openingRequirement: 51,
      fiftyClaimSeconds: 4,
      eliminationScore: 31,
    );
  }

  /// Number of active seats at a full Classic Hareeg table.
  final int seatCount;

  /// Number of cards dealt to each non-starter seat.
  final int cardsPerPlayer;

  /// Number of cards dealt to the starter, who skips the first draw.
  final int starterCardCount;

  /// Minimum opening value before benchmark pressure is applied.
  final int openingRequirement;

  /// Default time window for the immediate next player to claim Fifty.
  final int fiftyClaimSeconds;

  /// Score at which a player is eliminated from the match.
  final int eliminationScore;
}
