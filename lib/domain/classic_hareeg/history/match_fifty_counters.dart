import '../models/player_seat.dart';
import '../persistence/persistence_codec.dart';

/// Schema version implemented by the Fifty counter wire format.
const int matchFiftyCountersVersion = 1;

/// Per-seat Fifty attempt and success tally for one match.
///
/// Accumulated live at the action seam, never reconstructed afterwards: the
/// diagnostic log these events also reach is capped, so a long match drops its
/// early Fifty events and any count derived from it would silently undercount.
///
/// An **attempt** is a successfully applied explicit claim-fifty action. A
/// **success** is such a claim later proven in the claimant's favour. An
/// invalid claim is not an attempt, and a plain windowed take that happens to
/// be a Fifty is not a success — neither is an explicit claim.
class MatchFiftyCounters {
  /// Creates a tally.
  ///
  /// Throws [ArgumentError] for a negative value or for a seat whose successes
  /// exceed its attempts. That invariant is enforced rather than clamped: a
  /// tally that violates it was miscounted, and quietly repairing it would hide
  /// the counting bug.
  MatchFiftyCounters({
    Map<PlayerSeat, int> attempts = const {},
    Map<PlayerSeat, int> successes = const {},
  }) : _attempts = _validated(attempts, 'attempts'),
       _successes = _validated(successes, 'successes') {
    for (final seat in PlayerSeat.values) {
      final seatAttempts = _attempts[seat] ?? 0;
      final seatSuccesses = _successes[seat] ?? 0;
      if (seatSuccesses > seatAttempts) {
        throw ArgumentError.value(
          seatSuccesses,
          'successes',
          'Seat ${seat.name} has more Fifty successes than attempts '
              '($seatSuccesses > $seatAttempts).',
        );
      }
    }
  }

  /// An empty tally.
  factory MatchFiftyCounters.empty() => MatchFiftyCounters();

  /// Restores a tally from JSON-compatible data.
  ///
  /// Throws [FormatException] for an unsupported version or a malformed value.
  /// Invalid values are rejected, never clamped.
  factory MatchFiftyCounters.fromJson(Map<String, Object?> json) {
    final version = asJsonInt(json['version']);
    if (version != matchFiftyCountersVersion) {
      throw FormatException(
        'Unsupported Fifty counters version $version; '
        'expected $matchFiftyCountersVersion.',
      );
    }

    try {
      return MatchFiftyCounters(
        attempts: _decodeSeatCounts(json['attempts']),
        successes: _decodeSeatCounts(json['successes']),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid Fifty counters: ${error.message}');
    }
  }

  final Map<PlayerSeat, int> _attempts;
  final Map<PlayerSeat, int> _successes;

  /// Fifty attempts made by [seat].
  int attemptsFor(PlayerSeat seat) => _attempts[seat] ?? 0;

  /// Fifty successes achieved by [seat].
  int successesFor(PlayerSeat seat) => _successes[seat] ?? 0;

  /// Returns a tally with one more attempt recorded for [seat].
  MatchFiftyCounters withAttempt(PlayerSeat seat) {
    return MatchFiftyCounters(
      attempts: {..._attempts, seat: attemptsFor(seat) + 1},
      successes: _successes,
    );
  }

  /// Returns a tally with one more success recorded for [seat].
  ///
  /// The success is only recordable when an attempt is already on record for
  /// that seat, which upholds the successes-never-exceed-attempts invariant at
  /// the point of counting rather than at the point of decoding.
  MatchFiftyCounters withSuccess(PlayerSeat seat) {
    if (successesFor(seat) >= attemptsFor(seat)) {
      throw StateError(
        'Cannot record a Fifty success for ${seat.name} without a '
        'matching recorded attempt.',
      );
    }

    return MatchFiftyCounters(
      attempts: _attempts,
      successes: {..._successes, seat: successesFor(seat) + 1},
    );
  }

  /// Converts the tally to JSON-compatible data.
  Map<String, Object?> toJson() => {
    'version': matchFiftyCountersVersion,
    'attempts': {
      for (final entry in _attempts.entries)
        if (entry.value != 0) entry.key.name: entry.value,
    },
    'successes': {
      for (final entry in _successes.entries)
        if (entry.value != 0) entry.key.name: entry.value,
    },
  };

  static Map<PlayerSeat, int> _validated(
    Map<PlayerSeat, int> source,
    String label,
  ) {
    for (final entry in source.entries) {
      if (entry.value < 0) {
        throw ArgumentError.value(
          entry.value,
          label,
          'Fifty $label for ${entry.key.name} cannot be negative.',
        );
      }
    }
    return Map<PlayerSeat, int>.unmodifiable(source);
  }

  static Map<PlayerSeat, int> _decodeSeatCounts(Object? raw) {
    final map = asJsonMap(raw);
    if (map == null) {
      throw const FormatException('Invalid Fifty counter map.');
    }

    final counts = <PlayerSeat, int>{};
    for (final entry in map.entries) {
      final seat = PlayerSeat.fromName(entry.key);
      final value = asJsonInt(entry.value);
      if (seat == null || value == null) {
        throw FormatException('Invalid Fifty counter entry "${entry.key}".');
      }
      counts[seat] = value;
    }
    return counts;
  }
}
