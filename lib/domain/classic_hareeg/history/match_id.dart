import 'dart:math';

/// Rule a match id must satisfy.
///
/// Deliberately a subset of the replay file store's logical-key rule, so a
/// match id is always usable directly as a replay key. The domain layer does
/// not import the storage layer to say so — a test asserts the two agree,
/// which keeps the dependency direction clean while still failing loudly if
/// either rule drifts.
///
/// Shape: `m-<base36 milliseconds>-<8 base36 characters>`.
final RegExp matchIdExpression = RegExp(r'^m-[0-9a-z]{1,20}-[0-9a-z]{8}$');

/// Whether [value] is a well-formed match id.
bool isValidMatchId(String value) => matchIdExpression.hasMatch(value);

/// Mints stable, collision-resistant match ids.
///
/// The timestamp prefix keeps ids roughly sortable and debuggable. The random
/// suffix is what actually prevents collisions: a clock reading plus a
/// per-process counter is not enough, because a process restart resets the
/// counter and the clock can repeat across a restart, a timezone change, or an
/// NTP correction — two matches could then mint the same id and the second
/// would overwrite the first's replay.
class MatchIdMinter {
  /// Creates a minter.
  ///
  /// [now] and [random] are injectable so tests are deterministic; production
  /// uses the wall clock and [Random.secure].
  MatchIdMinter({DateTime Function()? now, Random? random})
    : _now = now ?? DateTime.now,
      _random = random ?? Random.secure();

  static const int _suffixLength = 8;
  static const String _alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';

  /// Attempts made before giving up on finding a free id.
  ///
  /// A collision is already vanishingly unlikely; needing more than a handful
  /// of retries means [isTaken] is wrong rather than that we were unlucky.
  static const int maxAttempts = 8;

  final DateTime Function() _now;
  final Random _random;

  /// Mints an id that [isTaken] reports as free.
  ///
  /// [isTaken] must consider **both** existing history summaries and existing
  /// replay keys: an id colliding with either would silently overwrite a stored
  /// match, so a collision is rejected and re-minted rather than accepted.
  ///
  /// Throws [StateError] after [maxAttempts] collisions.
  String mint({required bool Function(String candidate) isTaken}) {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final candidate = _candidate();
      if (!isTaken(candidate)) {
        return candidate;
      }
    }

    throw StateError(
      'Could not mint a free match id after $maxAttempts attempts.',
    );
  }

  /// Mints an id that [isTaken] reports as free, consulting durable storage.
  ///
  /// The async form exists because the only honest answer to "is this id free"
  /// comes from reading history and the replay store, and both are async. A
  /// synchronous minter can check nothing, which is the same as not checking.
  Future<String> reserve({
    required Future<bool> Function(String candidate) isTaken,
  }) async {
    final rejected = <String>{};
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final candidate = mint(isTaken: rejected.contains);
      if (!await isTaken(candidate)) {
        return candidate;
      }
      rejected.add(candidate);
    }

    throw StateError(
      'Could not reserve a free match id after $maxAttempts attempts.',
    );
  }

  String _candidate() {
    final millis = _now().toUtc().millisecondsSinceEpoch;
    final buffer = StringBuffer('m-')
      ..write(millis.toRadixString(36))
      ..write('-');
    for (var index = 0; index < _suffixLength; index++) {
      buffer.write(_alphabet[_random.nextInt(_alphabet.length)]);
    }
    return buffer.toString();
  }
}
