import 'dart:convert';

import '../game/classic_hareeg_game_controller.dart';
import '../game/classic_hareeg_match_snapshot.dart';
import '../replay/match_replay_timeline.dart';
import '../reporting/match_action_transcript.dart';
import 'match_checkpoint.dart';

/// Repairs old recorded checkpoints whose board was rolled back independently
/// of the transcript. Only adopt the replayed position when its legacy rollback
/// equals the saved board. Never replace a save with an unrelated replay frame.
Future<ClassicHareegMatchSnapshot?> recoverRecordedPosition(
  MatchCheckpoint checkpoint,
) async {
  final saved = checkpoint.snapshot;
  final recorder = checkpoint.recorderState;
  if (checkpoint.isTerminal ||
      checkpoint.replayIneligible ||
      saved.turnJournal != null ||
      saved.roundSeedAlgorithm != null ||
      recorder?.initialSnapshot == null ||
      recorder!.entries.isEmpty) {
    return null;
  }
  // A save-next-round checkpoint already describes the next deal, not the
  // transcript's last turn. There is no rolled-back play to recover there.
  if (recorder.entries.last.roundNumber < saved.roundNumber) return null;
  final outcome = await IncrementalTimelineBuild(
    MatchActionTranscript(
      initialSnapshot: recorder.initialSnapshot!,
      entries: recorder.entries,
    ),
    timeBudget: const Duration(milliseconds: 8),
  ).run();
  if (outcome is! ReplayTimelineBuilt) return null;
  final position = outcome.timeline.finalSnapshot;
  if (position.roundNumber != saved.roundNumber ||
      outcome.timeline.matchWinner != null) {
    return null;
  }
  final controller = ClassicHareegGameController.fromSnapshot(
    position,
    now: () => outcome.timeline.frames.last.clock,
  );
  Map<String, Object?> normalized(ClassicHareegMatchSnapshot snapshot) =>
      snapshot.toJson()
        ..remove('savedAt')
        ..remove('fiftyWindowOpenedAt')
        ..remove('roundSeedAlgorithm')
        ..remove('turnJournal');
  // Codec key order is canonical; every state field other than the replay's
  // synthetic clock and newly introduced metadata is included in the guard.
  if (jsonEncode(normalized(controller.toSnapshot())) !=
      jsonEncode(normalized(saved))) {
    return null;
  }
  return ClassicHareegMatchSnapshot.fromJson({
    ...position.toJson(),
    'savedAt': saved.savedAt.toIso8601String(),
    'fiftyWindowOpenedAt': saved.fiftyWindowOpenedAt?.toIso8601String(),
  });
}
