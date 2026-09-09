import '../models/player_seat.dart';
import '../persistence/persistence_codec.dart';

/// Schema version implemented by the standing wire format.
const int matchStandingVersion = 1;

/// One seat's place in a completed match's finish order.
class MatchStandingEntry {
  /// Creates a standing entry.
  const MatchStandingEntry({
    required this.seat,
    required this.rank,
    required this.finalScore,
    this.eliminatedInRound,
  });

  /// The seat.
  final PlayerSeat seat;

  /// One-based finish position. 1 is the winner; 0 means unrecorded legacy
  /// placement, never an inferred tie-break between unknown eliminations.
  final int rank;

  /// The seat's score when the match ended.
  final int finalScore;

  /// Round this seat was eliminated in, or null for the winner.
  final int? eliminatedInRound;
}

/// A completed match's finish order.
///
/// Finish order is not score order. A seat that survived to round nine placed
/// above one knocked out in round three even if the survivor's final score is
/// worse — surviving longer *is* doing better in an elimination game.
class MatchStanding {
  /// Creates a standing from an already-ordered list of entries.
  MatchStanding(Iterable<MatchStandingEntry> entries)
    : entries = List.unmodifiable(entries);

  /// Computes finish order from match facts.
  ///
  /// The winner ranks first. Everyone else is ordered by elimination round
  /// descending — a later elimination outlasted an earlier one — then by lower
  /// final score, then by the seat's declared order so the result is stable
  /// rather than dependent on map iteration.
  factory MatchStanding.fromMatchFacts({
    required PlayerSeat winner,
    required Map<PlayerSeat, int> finalScores,
    required Map<PlayerSeat, int> eliminationRounds,
    required List<PlayerSeat> seats,
    Set<PlayerSeat> unknownEliminationSeats = const {},
  }) {
    if (!seats.contains(winner)) {
      throw ArgumentError.value(
        winner,
        'winner',
        'The winning seat must be one of the match seats.',
      );
    }

    final ranked = <PlayerSeat>[winner];
    final rest =
        [
          for (final seat in seats)
            if (seat != winner) seat,
        ]..sort((a, b) {
          // Outlasting is the primary signal: a higher elimination round means the
          // seat was still playing when the other was already out.
          final roundA = eliminationRounds[a] ?? 0;
          final roundB = eliminationRounds[b] ?? 0;
          if (roundA != roundB) {
            return roundB.compareTo(roundA);
          }

          final scoreA = finalScores[a] ?? 0;
          final scoreB = finalScores[b] ?? 0;
          if (scoreA != scoreB) {
            return scoreA.compareTo(scoreB);
          }

          // Declared seat order, so two seats knocked out in the same round with
          // the same score still produce one deterministic answer.
          return a.index.compareTo(b.index);
        });

    ranked.addAll(rest);

    return MatchStanding([
      for (var index = 0; index < ranked.length; index++)
        MatchStandingEntry(
          seat: ranked[index],
          rank: unknownEliminationSeats.contains(ranked[index]) ? 0 : index + 1,
          finalScore: finalScores[ranked[index]] ?? 0,
          eliminatedInRound: ranked[index] == winner
              ? null
              : eliminationRounds[ranked[index]],
        ),
    ]);
  }

  /// Restores a standing from JSON-compatible data.
  factory MatchStanding.fromJson(Map<String, Object?> json) {
    final version = asJsonInt(json['version']);
    if (version != matchStandingVersion) {
      throw FormatException(
        'Unsupported match standing version $version; '
        'expected $matchStandingVersion.',
      );
    }

    final rawEntries = asJsonList(json['entries']);
    if (rawEntries == null) {
      throw const FormatException('Invalid match standing.');
    }

    final entries = <MatchStandingEntry>[];
    for (final raw in rawEntries) {
      final map = asJsonMap(raw);
      if (map == null) {
        throw const FormatException('Invalid match standing entry.');
      }
      final seat = PlayerSeat.fromName(asJsonString(map['seat']));
      final rank = asJsonInt(map['rank']);
      final finalScore = asJsonInt(map['finalScore']);
      if (seat == null || rank == null || finalScore == null) {
        throw const FormatException('Invalid match standing entry.');
      }
      entries.add(
        MatchStandingEntry(
          seat: seat,
          rank: rank,
          finalScore: finalScore,
          eliminatedInRound: asJsonInt(map['eliminatedInRound']),
        ),
      );
    }

    return MatchStanding(entries);
  }

  /// Entries in finish order, best first.
  final List<MatchStandingEntry> entries;

  /// The winning seat.
  PlayerSeat get winner => entries.first.seat;

  /// One-based placement for [seat], or null when the seat did not play.
  int? placementOf(PlayerSeat seat) {
    for (final entry in entries) {
      if (entry.seat == seat) {
        return entry.rank == 0 ? null : entry.rank;
      }
    }
    return null;
  }

  /// Converts the standing to JSON-compatible data.
  Map<String, Object?> toJson() => {
    'version': matchStandingVersion,
    'entries': [
      for (final entry in entries)
        {
          'seat': entry.seat.name,
          'rank': entry.rank,
          'finalScore': entry.finalScore,
          if (entry.eliminatedInRound != null)
            'eliminatedInRound': entry.eliminatedInRound,
        },
    ],
  };
}
