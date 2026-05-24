import '../models/playing_card.dart';

/// Explicit represented identity for one physical joker in a meld.
class JokerMeldAssignment {
  /// Creates a joker assignment.
  const JokerMeldAssignment({required this.jokerId, required this.identity});

  /// Physical joker id being assigned.
  final String jokerId;

  /// Represented identity selected for the joker.
  final CardIdentity identity;
}
