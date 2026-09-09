import '../game/classic_hareeg_match_snapshot.dart';
import '../models/player_seat.dart';
import '../persistence/persistence_codec.dart';
import '../reporting/match_recorder.dart';
import 'match_fifty_counters.dart';
import 'match_id.dart';
import 'match_terminal_facts.dart';

/// Schema version implemented by the checkpoint wire format.
const int matchCheckpointVersion = 1;

/// Schema version implemented by the pending-archive wire format.
const int pendingMatchArchiveVersion = 1;

/// Durable state for one resumable match.
///
/// A checkpoint is either **live** — the match is still being played — or
/// **terminal**, meaning the match is over and waiting to enter history. The
/// same record covers both so there is one place to look for "what match is
/// this device in the middle of", and one place to clean up.
class MatchCheckpoint {
  /// Creates a checkpoint.
  MatchCheckpoint({
    required this.matchId,
    required this.snapshot,
    this.recorderState,
    Map<PlayerSeat, int> eliminationRounds = const {},
    this.coachWasEnabled = false,
    this.fiftyCountersComplete = true,
    this.replayIneligible = false,
    this.terminalFacts,
  }) : _liveEliminationRounds = Map.unmodifiable(eliminationRounds) {
    if (!isValidMatchId(matchId)) {
      throw ArgumentError.value(matchId, 'matchId', 'Invalid match id.');
    }
  }

  /// Restores a checkpoint from JSON-compatible data.
  factory MatchCheckpoint.fromJson(Map<String, Object?> json) {
    final version = asJsonInt(json['version']);
    if (version != matchCheckpointVersion) {
      throw FormatException(
        'Unsupported match checkpoint version $version; '
        'expected $matchCheckpointVersion.',
      );
    }

    final matchId = asJsonString(json['matchId']);
    final snapshotJson = asJsonMap(json['snapshot']);
    if (matchId == null || snapshotJson == null) {
      throw const FormatException('Invalid match checkpoint.');
    }
    if (!isValidMatchId(matchId)) {
      throw FormatException('Invalid checkpoint match id "$matchId".');
    }

    // Absent and present-but-wrong-type are different facts. `asJsonMap`
    // collapses them into null, which would read a corrupt recorder as "this
    // match never had one" — quietly downgrading a replayable match instead of
    // reporting that its data is damaged.
    final recorderJson = _optionalMap(json, 'recorderState');
    final terminalJson = _optionalMap(json, 'terminalFacts');

    // Every v1 flag is required. Defaulting a missing one would silently hand
    // back trust the checkpoint had explicitly withdrawn: a lost
    // `replayIneligible` makes a known-incomplete match replayable again, a
    // lost `fiftyCountersComplete` presents unknown counters as measured, and a
    // lost `coachWasEnabled` erases that the player had help.
    final coachWasEnabled = asJsonBool(json['coachWasEnabled']);
    final fiftyCountersComplete = asJsonBool(json['fiftyCountersComplete']);
    final replayIneligible = asJsonBool(json['replayIneligible']);
    if (coachWasEnabled == null ||
        fiftyCountersComplete == null ||
        replayIneligible == null) {
      throw const FormatException(
        'Match checkpoint is missing a required flag '
        '(coachWasEnabled, fiftyCountersComplete, replayIneligible).',
      );
    }

    // The live elimination map is required while live and absent once
    // terminal, where the terminal facts own the frozen copy.
    final isTerminal = terminalJson != null;
    if (!isTerminal && json['eliminationRounds'] == null) {
      throw const FormatException(
        'A live match checkpoint must carry its elimination rounds.',
      );
    }

    return MatchCheckpoint(
      matchId: matchId,
      snapshot: ClassicHareegMatchSnapshot.fromJson(snapshotJson),
      recorderState: recorderJson == null
          ? null
          : MatchRecorderState.fromJson(recorderJson),
      eliminationRounds: isTerminal
          ? const {}
          : _decodeSeatInts(json['eliminationRounds']),
      coachWasEnabled: coachWasEnabled,
      fiftyCountersComplete: fiftyCountersComplete,
      replayIneligible: replayIneligible,
      terminalFacts: isTerminal
          ? MatchTerminalFacts.fromJson(terminalJson)
          : null,
    );
  }

  /// Stable match identity, and the replay record's storage key.
  final String matchId;

  /// Match state to resume from.
  final ClassicHareegMatchSnapshot snapshot;

  /// Durable recorder state, or null for a legacy save that predates it.
  final MatchRecorderState? recorderState;

  /// Whether coaching was available and enabled at any point in the match.
  ///
  /// Sticky: see [withCoachEnabled].
  final bool coachWasEnabled;

  /// Whether the Fifty counters were tracked for the whole match.
  ///
  /// False only for a match migrated from a legacy save. Independent of
  /// replayability — losing a replay file says nothing about whether the
  /// counters were measured.
  final bool fiftyCountersComplete;

  /// Whether this match can never produce a replay record.
  ///
  /// Sticky once set. A match whose transcript is known to be incomplete cannot
  /// become replayable again by playing on, because the missing actions are
  /// gone for good.
  final bool replayIneligible;

  /// Facts captured at match-over, or null while the match is live.
  final MatchTerminalFacts? terminalFacts;

  final Map<PlayerSeat, int> _liveEliminationRounds;

  /// Whether the match is over and waiting to be archived.
  bool get isTerminal => terminalFacts != null;

  /// Match-wide elimination round per eliminated seat.
  ///
  /// Delegates to the terminal facts once the match is terminal, so there is
  /// exactly one serialized copy at each lifecycle state rather than two that
  /// could drift apart.
  Map<PlayerSeat, int> get eliminationRounds =>
      terminalFacts?.eliminationRounds ?? _liveEliminationRounds;

  /// Per-seat Fifty tally, owned by the recorder state.
  ///
  /// Empty when there is no recorder — which is exactly when
  /// [fiftyCountersComplete] is false, so the zeros are readable as "unknown"
  /// rather than "measured none".
  MatchFiftyCounters get fiftyCounters =>
      recorderState?.fiftyCounters ?? MatchFiftyCounters.empty();

  /// Returns a copy with [snapshot] and [recorderState] advanced.
  MatchCheckpoint withProgress({
    required ClassicHareegMatchSnapshot snapshot,
    MatchRecorderState? recorderState,
    Map<PlayerSeat, int>? eliminationRounds,
  }) {
    if (isTerminal) {
      // A finished match cannot gain more play. Allowing it would silently
      // produce a checkpoint that is both terminal and mid-match — saved as
      // already-completed, unresumable, and unable to publish a second time.
      throw StateError(
        'A terminal checkpoint cannot advance. A new match needs a new '
        'checkpoint and a new match id.',
      );
    }

    return _copy(
      snapshot: snapshot,
      recorderState: recorderState ?? this.recorderState,
      eliminationRounds: eliminationRounds == null
          ? _liveEliminationRounds
          : mergeEliminationRounds(_liveEliminationRounds, eliminationRounds),
    );
  }

  /// Returns a copy whose coach flag is the sticky OR of the current value and
  /// [enabled].
  ///
  /// Once true it stays true for the rest of the match: the summary records
  /// whether the player had help, so turning the coach off later does not undo
  /// having used it.
  MatchCheckpoint withCoachEnabled(bool enabled) {
    if (coachWasEnabled || !enabled) {
      return this;
    }
    return _copy(coachWasEnabled: true);
  }

  /// Returns a copy marked permanently ineligible for replay.
  MatchCheckpoint withReplayIneligible() {
    if (replayIneligible) {
      return this;
    }
    return _copy(replayIneligible: true);
  }

  /// Returns the terminal form of this checkpoint.
  ///
  /// The live elimination map is frozen into [facts]; from here on
  /// [eliminationRounds] reads through to it.
  MatchCheckpoint terminalize(MatchTerminalFacts facts) {
    return MatchCheckpoint(
      matchId: matchId,
      snapshot: snapshot,
      recorderState: recorderState,
      eliminationRounds: const {},
      coachWasEnabled: coachWasEnabled,
      fiftyCountersComplete: fiftyCountersComplete,
      replayIneligible: replayIneligible,
      terminalFacts: facts,
    );
  }

  MatchCheckpoint _copy({
    ClassicHareegMatchSnapshot? snapshot,
    MatchRecorderState? recorderState,
    Map<PlayerSeat, int>? eliminationRounds,
    bool? coachWasEnabled,
    bool? replayIneligible,
  }) {
    return MatchCheckpoint(
      matchId: matchId,
      snapshot: snapshot ?? this.snapshot,
      recorderState: recorderState ?? this.recorderState,
      eliminationRounds: eliminationRounds ?? _liveEliminationRounds,
      coachWasEnabled: coachWasEnabled ?? this.coachWasEnabled,
      fiftyCountersComplete: fiftyCountersComplete,
      replayIneligible: replayIneligible ?? this.replayIneligible,
      terminalFacts: terminalFacts,
    );
  }

  /// Converts the checkpoint to JSON-compatible data.
  Map<String, Object?> toJson() => {
    'version': matchCheckpointVersion,
    'matchId': matchId,
    'snapshot': snapshot.toJson(),
    if (recorderState != null) 'recorderState': recorderState!.toJson(),
    // Omitted when terminal so the frozen copy on the terminal facts is the
    // only one on the wire.
    if (terminalFacts == null)
      'eliminationRounds': {
        for (final entry in _liveEliminationRounds.entries)
          entry.key.name: entry.value,
      },
    'coachWasEnabled': coachWasEnabled,
    'fiftyCountersComplete': fiftyCountersComplete,
    'replayIneligible': replayIneligible,
    if (terminalFacts != null) 'terminalFacts': terminalFacts!.toJson(),
  };

  /// Reads an optional nested object, telling absent apart from malformed.
  static Map<String, Object?>? _optionalMap(
    Map<String, Object?> json,
    String key,
  ) {
    // Key presence, not value nullness. An omitted key is the documented
    // absence — a legacy save with no recorder, or a live match with no
    // terminal facts. A key that is present and explicitly null is neither: it
    // is a record that once held something and no longer does, which is
    // corruption and must be reported rather than read as "never had one".
    if (!json.containsKey(key)) {
      return null;
    }

    final map = asJsonMap(json[key]);
    if (map == null) {
      throw FormatException(
        'Checkpoint field "$key" is present but is not an object.',
      );
    }
    return map;
  }

  static Map<PlayerSeat, int> _decodeSeatInts(Object? raw) {
    final map = asJsonMap(raw);
    if (map == null) {
      throw const FormatException('Invalid checkpoint elimination rounds.');
    }

    final decoded = <PlayerSeat, int>{};
    for (final entry in map.entries) {
      final seat = PlayerSeat.fromName(entry.key);
      final value = asJsonInt(entry.value);
      if (seat == null || value == null) {
        throw FormatException('Invalid elimination entry "${entry.key}".');
      }
      decoded[seat] = value;
    }
    return decoded;
  }
}

/// Merges a controller's per-round elimination view into the match-wide map.
///
/// A controller only knows about eliminations from its own round, so resuming a
/// match hands us a map covering the current round alone. Merging keeps the
/// earliest round each seat went out in: an elimination cannot un-happen, and
/// lowering the round would make a seat look like it lasted less long than it
/// did, which silently corrupts finish order.
Map<PlayerSeat, int> mergeEliminationRounds(
  Map<PlayerSeat, int> existing,
  Map<PlayerSeat, int> incoming,
) {
  final merged = Map<PlayerSeat, int>.of(existing);
  for (final entry in incoming.entries) {
    final current = merged[entry.key];
    if (current == null || entry.value < current) {
      merged[entry.key] = entry.value;
    }
  }
  return merged;
}

/// A completed match waiting for publication to history.
///
/// A pointer, not a payload: the archive input lives on the terminal
/// checkpoint. Duplicating the completion facts here would create a second copy
/// to keep in sync, and a disagreement between them would have no right answer.
class PendingMatchArchive {
  /// Creates a pending archive.
  PendingMatchArchive({required this.matchId}) {
    if (!isValidMatchId(matchId)) {
      throw ArgumentError.value(matchId, 'matchId', 'Invalid match id.');
    }
  }

  /// Restores a pending archive from JSON-compatible data.
  factory PendingMatchArchive.fromJson(Map<String, Object?> json) {
    final version = asJsonInt(json['version']);
    if (version != pendingMatchArchiveVersion) {
      throw FormatException(
        'Unsupported pending archive version $version; '
        'expected $pendingMatchArchiveVersion.',
      );
    }

    final matchId = asJsonString(json['matchId']);
    if (matchId == null || !isValidMatchId(matchId)) {
      throw const FormatException('Invalid pending archive.');
    }

    return PendingMatchArchive(matchId: matchId);
  }

  /// The match awaiting publication.
  final String matchId;

  /// Converts the pending archive to JSON-compatible data.
  Map<String, Object?> toJson() => {
    'version': pendingMatchArchiveVersion,
    'matchId': matchId,
  };
}
