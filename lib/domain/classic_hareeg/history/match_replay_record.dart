import '../persistence/persistence_codec.dart';
import '../reporting/match_action_transcript.dart';
import 'match_id.dart';

/// Schema version implemented by the replay record wire format.
const int matchReplayRecordVersion = 1;

/// The heavy replay payload for one completed match.
///
/// One record per completed match, stored as a file and loaded lazily — this is
/// the part that must never be pulled in just to list history. The base
/// snapshot lives inside the transcript, which already pairs a starting state
/// with the ordered actions applied from it.
class MatchReplayRecord {
  /// Creates a replay record.
  MatchReplayRecord({required this.matchId, required this.transcript}) {
    if (!isValidMatchId(matchId)) {
      throw ArgumentError.value(matchId, 'matchId', 'Invalid match id.');
    }
  }

  /// Restores a replay record from JSON-compatible data.
  factory MatchReplayRecord.fromJson(Map<String, Object?> json) {
    final version = asJsonInt(json['version']);
    if (version != matchReplayRecordVersion) {
      throw FormatException(
        'Unsupported replay record version $version; '
        'expected $matchReplayRecordVersion.',
      );
    }

    final matchId = asJsonString(json['matchId']);
    final transcriptJson = asJsonMap(json['transcript']);
    if (matchId == null || transcriptJson == null) {
      throw const FormatException('Invalid replay record.');
    }
    if (!isValidMatchId(matchId)) {
      throw FormatException('Invalid replay record match id "$matchId".');
    }

    return MatchReplayRecord(
      matchId: matchId,
      transcript: MatchActionTranscript.fromJson(transcriptJson),
    );
  }

  /// The match this replay belongs to.
  final String matchId;

  /// Base snapshot plus the ordered actions applied from it.
  final MatchActionTranscript transcript;

  /// Converts the record to JSON-compatible data.
  Map<String, Object?> toJson() => {
    'version': matchReplayRecordVersion,
    'matchId': matchId,
    'transcript': transcript.toJson(),
  };
}
