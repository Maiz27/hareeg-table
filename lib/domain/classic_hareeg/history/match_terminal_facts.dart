import '../models/player_seat.dart';
import '../persistence/persistence_codec.dart';
import 'match_standing.dart';

/// Schema version implemented by the terminal-facts wire format.
const int matchTerminalFactsVersion = 1;

/// Everything a completed match's archive needs, captured once at match-over.
///
/// This exists because the facts cannot be recovered later. The match snapshot
/// records no winner, and its active seats are the pre-progression set, so a
/// crash between marking a match terminal and publishing it would otherwise
/// force recovery to stamp its own clock and infer a winner from board state.
/// Both guesses would be wrong, and the resulting history entry would look
/// perfectly valid.
///
/// So these facts are written once, at the moment they are known, and are never
/// recomputed — recovery republishes them verbatim however much later it runs.
class MatchTerminalFacts {
  /// Creates terminal facts.
  MatchTerminalFacts({
    required DateTime completedAt,
    required this.winner,
    required Map<PlayerSeat, int> finalScores,
    required this.roundCount,
    required Map<PlayerSeat, int> eliminationRounds,
    required List<PlayerSeat> seats,
    Set<PlayerSeat> unknownEliminationSeats = const {},
  }) : completedAt = completedAt.toUtc(),
       finalScores = Map.unmodifiable(finalScores),
       eliminationRounds = Map.unmodifiable(eliminationRounds),
       seats = List.unmodifiable(seats),
       unknownEliminationSeats = Set.unmodifiable(unknownEliminationSeats) {
    _validate();
  }

  /// Rejects facts that do not describe a finished match.
  ///
  /// The check that matters is survivor count. A trace that merely *stopped* —
  /// an action cap, a step limit, a driver giving up — leaves several seats
  /// still playing, and nothing else here would notice: scores look plausible,
  /// the "winner" is simply whichever seat had not been eliminated yet, and the
  /// match would publish as a replayable completed game it never was.
  ///
  /// A real Classic Hareeg match ends with exactly one seat standing, and that
  /// seat is the winner. Anything else is an unfinished match wearing a
  /// finished match's clothes.
  void _validate() {
    if (seats.isEmpty) {
      throw ArgumentError.value(seats, 'seats', 'A match needs seats.');
    }
    if (seats.toSet().length != seats.length) {
      throw ArgumentError.value(seats, 'seats', 'Duplicate seat in a match.');
    }
    if (!seats.contains(winner)) {
      throw ArgumentError.value(
        winner,
        'winner',
        'The winner must be one of the match seats.',
      );
    }
    if (roundCount < 1) {
      throw ArgumentError.value(
        roundCount,
        'roundCount',
        'A completed match played at least one round.',
      );
    }

    for (final seat in seats) {
      if (!finalScores.containsKey(seat)) {
        throw ArgumentError.value(
          finalScores,
          'finalScores',
          'Missing a final score for ${seat.name}.',
        );
      }
    }

    for (final entry in eliminationRounds.entries) {
      if (!seats.contains(entry.key)) {
        throw ArgumentError.value(
          eliminationRounds,
          'eliminationRounds',
          '${entry.key.name} was eliminated but did not play.',
        );
      }
      if (entry.value < 1 || entry.value > roundCount) {
        throw ArgumentError.value(
          entry.value,
          'eliminationRounds',
          '${entry.key.name} was eliminated in round ${entry.value}, '
              'outside rounds 1..$roundCount.',
        );
      }
    }

    if (unknownEliminationSeats.any(
      (seat) => !seats.contains(seat) || eliminationRounds.containsKey(seat),
    )) {
      throw ArgumentError(
        'Unknown elimination seats must be distinct match seats without a known round.',
      );
    }
    if (eliminationRounds.containsKey(winner) ||
        unknownEliminationSeats.contains(winner)) {
      throw ArgumentError.value(
        winner,
        'winner',
        'The winner cannot also have been eliminated.',
      );
    }

    final survivors = [
      for (final seat in seats)
        if (!eliminationRounds.containsKey(seat) &&
            !unknownEliminationSeats.contains(seat))
          seat,
    ];
    if (survivors.length != 1 || survivors.single != winner) {
      throw ArgumentError.value(
        survivors.map((seat) => seat.name).toList(),
        'eliminationRounds',
        'A completed match ends with exactly one survivor, the winner '
            '(${winner.name}). This trace left ${survivors.length} seats '
            'still playing, so the match did not finish.',
      );
    }
  }

  /// Restores terminal facts from JSON-compatible data.
  factory MatchTerminalFacts.fromJson(Map<String, Object?> json) {
    final version = asJsonInt(json['version']);
    if (version != matchTerminalFactsVersion) {
      throw FormatException(
        'Unsupported terminal facts version $version; '
        'expected $matchTerminalFactsVersion.',
      );
    }

    final completedAtRaw = asJsonString(json['completedAt']);
    final winner = PlayerSeat.fromName(asJsonString(json['winner']));
    final roundCount = asJsonInt(json['roundCount']);
    if (completedAtRaw == null || winner == null || roundCount == null) {
      throw const FormatException('Invalid terminal facts.');
    }

    final completedAt = DateTime.tryParse(completedAtRaw);
    if (completedAt == null) {
      throw FormatException('Invalid terminal facts timestamp.');
    }

    final rawSeats = asJsonList(json['seats']);
    if (rawSeats == null) {
      throw const FormatException('Invalid terminal facts seats.');
    }
    final seats = <PlayerSeat>[];
    for (final raw in rawSeats) {
      final seat = PlayerSeat.fromName(asJsonString(raw));
      if (seat == null) {
        throw const FormatException('Invalid terminal facts seat.');
      }
      seats.add(seat);
    }

    try {
      return MatchTerminalFacts(
        completedAt: completedAt,
        winner: winner,
        finalScores: _decodeSeatInts(json['finalScores']),
        roundCount: roundCount,
        eliminationRounds: _decodeSeatInts(json['eliminationRounds']),
        seats: seats,
        unknownEliminationSeats: {
          for (final name
              in asJsonList(json['unknownEliminationSeats']) ?? const [])
            PlayerSeat.fromName(asJsonString(name)) ??
                (throw const FormatException(
                  'Invalid unknown elimination seat.',
                )),
        },
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid terminal facts: ${error.message}');
    }
  }

  /// When the match completed, in UTC.
  final DateTime completedAt;

  /// The winning seat.
  final PlayerSeat winner;

  /// Final score per seat.
  final Map<PlayerSeat, int> finalScores;

  /// Rounds dealt during the match.
  final int roundCount;

  /// Match-wide elimination round per eliminated seat.
  ///
  /// While the match is live this map is owned by the checkpoint. Once the
  /// match is terminal it is frozen here, and the checkpoint delegates to it —
  /// there is exactly one serialized copy at each lifecycle state.
  final Map<PlayerSeat, int> eliminationRounds;

  /// Seats that played the match.
  final List<PlayerSeat> seats;

  /// Seats already eliminated before a legacy save was migrated. Their actual
  /// elimination rounds and relative placements were never recorded.
  final Set<PlayerSeat> unknownEliminationSeats;

  /// Finish order derived from these facts.
  MatchStanding get standing => MatchStanding.fromMatchFacts(
    winner: winner,
    finalScores: finalScores,
    eliminationRounds: eliminationRounds,
    seats: seats,
    unknownEliminationSeats: unknownEliminationSeats,
  );

  /// Converts the facts to JSON-compatible data.
  Map<String, Object?> toJson() => {
    'version': matchTerminalFactsVersion,
    'completedAt': completedAt.toIso8601String(),
    'winner': winner.name,
    'finalScores': {
      for (final entry in finalScores.entries) entry.key.name: entry.value,
    },
    'roundCount': roundCount,
    'eliminationRounds': {
      for (final entry in eliminationRounds.entries)
        entry.key.name: entry.value,
    },
    'seats': [for (final seat in seats) seat.name],
    if (unknownEliminationSeats.isNotEmpty)
      'unknownEliminationSeats': [
        for (final seat in unknownEliminationSeats) seat.name,
      ],
  };

  static Map<PlayerSeat, int> _decodeSeatInts(Object? raw) {
    final map = asJsonMap(raw);
    if (map == null) {
      throw const FormatException('Invalid terminal facts seat map.');
    }

    final decoded = <PlayerSeat, int>{};
    for (final entry in map.entries) {
      final seat = PlayerSeat.fromName(entry.key);
      final value = asJsonInt(entry.value);
      if (seat == null || value == null) {
        throw FormatException('Invalid terminal facts entry "${entry.key}".');
      }
      decoded[seat] = value;
    }
    return decoded;
  }
}
