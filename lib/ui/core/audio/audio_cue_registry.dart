import 'package:flutter/foundation.dart';

import 'table_sound_event.dart';

/// Declarative mapping of one [TableSoundEvent] to its sample-bank and volume.
///
/// A cue with a single asset plays it every time; a cue with multiple assets
/// is cycled by [AudioAssetRotation]. Cues are pure data — they hold no
/// runtime state.
@immutable
class AudioCue {
  /// Creates a cue. Pass one asset for a fixed sound or many for rotation.
  ///
  /// `volume` must be in `[0, 1]`. `assets` must be non-empty; Dart's const-
  /// eval rules do not allow `List.isNotEmpty` / `List.length` inside a const
  /// constructor's assert, so the invariant stays a documented contract. The
  /// registry is statically declared so an empty list would surface at first
  /// lookup via [AudioAssetRotation.pickAsset].
  const AudioCue({required this.assets, required this.volume})
    : assert(
        volume >= 0.0 && volume <= 1.0,
        'AudioCue volume must be in [0, 1]',
      );

  /// Bundled asset paths (relative to the `assets/` folder).
  final List<String> assets;

  /// Playback volume in `[0, 1]`.
  final double volume;
}

/// Single source of truth mapping each [TableSoundEvent] to its [AudioCue].
///
/// Add a new sound by adding one entry; the gateway routes it automatically.
/// Per-event metadata (timing hints, variants under fast motion) belongs on
/// [AudioCue], not on the gateway.
abstract final class AudioCueRegistry {
  /// Returns the cue mapped to [event], or null when no cue is registered.
  static AudioCue? lookup(TableSoundEvent event) => _cues[event];

  /// Returns every distinct asset path referenced by the registry, used by
  /// the preloading sound player to warm SoundPool entries once at boot.
  static Set<String> allAssetPaths() {
    return <String>{
      for (final cue in _cues.values) ...cue.assets,
    };
  }
}

const _prefix = 'sounds/kenney_casino/';

const Map<TableSoundEvent, AudioCue> _cues = {
  TableSoundEvent.splashIntro: AudioCue(
    assets: ['${_prefix}cards-pack-take-out-1.ogg'],
    volume: 0.34,
  ),
  TableSoundEvent.openingShuffle: AudioCue(
    assets: ['${_prefix}card-shuffle.ogg'],
    volume: 0.42,
  ),
  TableSoundEvent.dealCard: AudioCue(
    assets: [
      '${_prefix}card-slide-1.ogg',
      '${_prefix}card-slide-2.ogg',
      '${_prefix}card-slide-3.ogg',
      '${_prefix}card-slide-4.ogg',
      '${_prefix}card-slide-5.ogg',
      '${_prefix}card-slide-6.ogg',
      '${_prefix}card-slide-7.ogg',
      '${_prefix}card-slide-8.ogg',
    ],
    volume: 0.36,
  ),
  TableSoundEvent.drawStock: AudioCue(
    assets: [
      '${_prefix}card-slide-2.ogg',
      '${_prefix}card-slide-5.ogg',
      '${_prefix}card-shove-1.ogg',
    ],
    volume: 0.44,
  ),
  TableSoundEvent.takeDiscard: AudioCue(
    assets: ['${_prefix}card-shove-2.ogg', '${_prefix}card-shove-3.ogg'],
    volume: 0.44,
  ),
  TableSoundEvent.discardCard: AudioCue(
    assets: [
      '${_prefix}card-place-1.ogg',
      '${_prefix}card-place-2.ogg',
      '${_prefix}card-place-3.ogg',
      '${_prefix}card-place-4.ogg',
    ],
    volume: 0.48,
  ),
  TableSoundEvent.meldPlace: AudioCue(
    assets: [
      '${_prefix}card-fan-1.ogg',
      '${_prefix}card-fan-2.ogg',
      '${_prefix}card-place-4.ogg',
    ],
    volume: 0.50,
  ),
  TableSoundEvent.cardReturn: AudioCue(
    assets: ['${_prefix}card-shove-3.ogg', '${_prefix}card-shove-4.ogg'],
    volume: 0.46,
  ),
  TableSoundEvent.fiftyClaim: AudioCue(
    assets: ['${_prefix}cards-pack-open-1.ogg'],
    volume: 0.58,
  ),
  TableSoundEvent.invalidAction: AudioCue(
    assets: ['${_prefix}card-shove-4.ogg'],
    volume: 0.34,
  ),
  TableSoundEvent.roundEnd: AudioCue(
    assets: ['${_prefix}cards-pack-take-out-1.ogg'],
    volume: 0.46,
  ),
};
