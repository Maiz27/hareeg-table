import 'audio_cue_registry.dart';
import 'table_sound_event.dart';

/// Per-event cursor that cycles a cue's sample bank in order.
///
/// Owned by the audio gateway so each gateway instance keeps its own
/// rotation. A cue with a single asset returns it every time; a cue with
/// multiple assets advances by one on each pick, wrapping at the end of the
/// bank.
class AudioAssetRotation {
  /// Creates an asset rotation with no cursor state.
  AudioAssetRotation();

  final Map<TableSoundEvent, int> _cursors = {};

  /// Returns the next asset path to play for [event] given its [cue].
  ///
  /// Single-asset cues skip cursor work; multi-asset cues advance the
  /// per-event cursor by one position and wrap modulo the bank size.
  String pickAsset(TableSoundEvent event, AudioCue cue) {
    if (cue.assets.length == 1) {
      return cue.assets.single;
    }
    final next = _cursors[event] ?? 0;
    _cursors[event] = next + 1;
    return cue.assets[next % cue.assets.length];
  }
}
