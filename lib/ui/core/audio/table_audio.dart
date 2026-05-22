import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

final AudioContext _tableSoundEffectAudioContext = AudioContext(
  android: const AudioContextAndroid(
    contentType: AndroidContentType.sonification,
    usageType: AndroidUsageType.game,
    audioFocus: AndroidAudioFocus.none,
  ),
  iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
);

/// Logical table sound effects.
enum TableSoundEvent {
  /// First-frame brand cue accompanying the splash card fan.
  splashIntro,

  /// Round-opening shuffle / deck preparation.
  openingShuffle,

  /// One dealt card in the opening deal presentation.
  dealCard,

  /// Drawing a card from the stock pile.
  drawStock,

  /// Taking the visible discard.
  takeDiscard,

  /// Placing a card on the discard pile.
  discardCard,

  /// Placing cards onto the table meld area.
  meldPlace,

  /// Returning a card or staged table play.
  cardReturn,

  /// Successful Fifty claim.
  fiftyClaim,

  /// Invalid move feedback.
  invalidAction,

  /// Round result appears.
  roundEnd,
}

/// Low-level sound player seam used by [TableAudio].
abstract interface class TableSoundPlayer {
  /// Performs any cheap setup needed before the first sound.
  Future<void> warmUp();

  /// Plays a bundled Flutter asset path relative to the `assets/` folder.
  Future<void> playAsset(String path, {required double volume});

  /// Releases native resources.
  Future<void> dispose();
}

/// User-facing table audio gateway.
///
/// The native player is created lazily so tests and muted sessions never touch
/// platform audio channels.
class TableAudio {
  /// Creates a table audio gateway.
  TableAudio({this.enabled = false, TableSoundPlayer Function()? playerFactory})
    : _playerFactory = playerFactory ?? _PreloadedAssetSoundPlayer.new;

  /// Creates a permanently muted gateway for widget tests and fallback scopes.
  TableAudio.noop()
    : enabled = false,
      _playerFactory = _NoopSoundPlayer.new,
      _player = _NoopSoundPlayer();

  /// Current runtime toggle.
  bool enabled;

  final TableSoundPlayer Function() _playerFactory;
  TableSoundPlayer? _player;
  // Cursor state for cycling cues. Keyed by event so each cycling cue keeps
  // its own rotation independent of any other.
  final Map<TableSoundEvent, int> _cursors = {};

  /// Warms the native player while respecting the user toggle.
  Future<void> warmUp() async {
    if (!enabled) return;
    try {
      await _ensurePlayer().warmUp();
    } catch (error, stackTrace) {
      _logAudioFailure('warmUp', error, stackTrace);
    }
  }

  /// Plays [event] when table sounds are enabled.
  Future<void> play(TableSoundEvent event) async {
    if (!enabled) return;
    final cue = _kCueRegistry[event];
    if (cue == null) {
      // Unmapped event — log once and skip rather than crash a sound that
      // can never play anyway.
      _logAudioFailure(event.name, StateError('no audio cue'), StackTrace.empty);
      return;
    }
    final asset = _pickAsset(event, cue);
    try {
      await _ensurePlayer().playAsset(asset, volume: cue.volume);
    } catch (error, stackTrace) {
      _logAudioFailure(event.name, error, stackTrace);
    }
  }

  /// Releases any native player resources.
  Future<void> dispose() async {
    final player = _player;
    _player = null;
    await player?.dispose();
  }

  TableSoundPlayer _ensurePlayer() {
    return _player ??= _playerFactory();
  }

  String _pickAsset(TableSoundEvent event, AudioCue cue) {
    if (cue.assets.length == 1) {
      return cue.assets.single;
    }
    final next = _cursors[event] ?? 0;
    _cursors[event] = next + 1;
    return cue.assets[next % cue.assets.length];
  }

  void _logAudioFailure(String event, Object error, StackTrace stackTrace) {
    debugPrint('Table audio failed for $event: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

/// Declarative mapping of one [TableSoundEvent] to its sample-bank and volume.
///
/// A cue with a single asset plays it every time; a cue with multiple assets
/// cycles through them in order. The gateway owns the cursor state — cues are
/// pure data.
@immutable
class AudioCue {
  /// Creates a cue. Pass one asset for a fixed sound or many for rotation.
  ///
  /// `volume` must be in `[0, 1]`. `assets` must be non-empty; the const-eval
  /// limit on `List.length` keeps that invariant a doc contract rather than an
  /// assert, but the registry is statically declared so an empty list would
  /// surface at first lookup.
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

const _prefix = 'sounds/kenney_casino/';

/// Single source of truth mapping each [TableSoundEvent] to its [AudioCue].
///
/// Add a new sound by adding one entry here; the gateway routes it
/// automatically. Per-event metadata (e.g. timing hints, variants under fast
/// motion) belongs on [AudioCue], not on the gateway.
const Map<TableSoundEvent, AudioCue> _kCueRegistry = {
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

/// Per-asset preloaded player. One [AudioPlayer] per unique cue asset, each
/// loaded into SoundPool once during [warmUp].
///
/// This is the seam that fixes the Davey frames we were seeing: in lowLatency
/// mode, `play(AssetSource(...))` on a player whose current source differs
/// triggers a fresh Vorbis decoder allocation (Binder calls to mediaserver,
/// buffer pools, the works). By dedicating one player per asset path, the
/// source never changes after warmUp — every subsequent play is a cached
/// SoundPool playback with no decoder churn.
class _PreloadedAssetSoundPlayer implements TableSoundPlayer {
  _PreloadedAssetSoundPlayer();

  final Map<String, AudioPlayer> _players = {};
  // Per-asset load futures — playAsset awaits the specific entry so it only
  // waits for its own sample (~200ms) instead of all 21 in parallel (~1.5s).
  final Map<String, Future<void>> _sourceLoads = {};
  Future<void>? _initFuture;

  @override
  Future<void> warmUp() async {
    // The init phase awaits player creation + lowLatency/audio-context/release
    // mode setup (fast). The setSource calls fire in parallel but their
    // futures are tracked in `_sourceLoads` so [playAsset] can await only
    // its own asset. Without per-asset tracking we'd either block on all 21
    // samples here (splash sound late) or skip the await entirely (releasing
    // = true breaks audioplayers' state machine — `stop()` early-returns and
    // `resume()` no-ops because `released` only flips to false inside the
    // `source` setter).
    _initFuture ??= _initAllPlayers();
    await _initFuture;
  }

  /// Asset path of the cue played the moment the splash screen mounts. Its
  /// sample is loaded before [warmUp] returns so the cue isn't racing the
  /// other 20 SoundPool loads in the device's serial decode queue.
  static const _splashCriticalPath = '${_prefix}cards-pack-take-out-1.ogg';

  Future<void> _initAllPlayers() async {
    final uniquePaths = <String>{
      for (final cue in _kCueRegistry.values) ...cue.assets,
    };
    // Create the AudioPlayer instances synchronously so [playAsset] can find
    // them in the map immediately.
    for (final path in uniquePaths) {
      _players[path] = AudioPlayer();
    }
    // Configure every player's player-mode / audio-context / release-mode in
    // parallel (fast — ~3 method-channel calls each).
    await Future.wait([
      for (final player in _players.values) _configureBasic(player),
    ]);
    // Load the splash cue FIRST and await it. Android's SoundPool decodes its
    // load queue serially on a background thread, so unless we sequence the
    // splash sample ahead of the others it ends up at the back of the queue
    // and only finishes after the splash has handed off to home.
    final splashPlayer = _players[_splashCriticalPath];
    if (splashPlayer != null) {
      final future = _loadSourceSafely(splashPlayer, _splashCriticalPath);
      _sourceLoads[_splashCriticalPath] = future;
      await future;
    }
    // Fire the rest in parallel; tracked so playAsset can await per-asset.
    for (final entry in _players.entries) {
      if (entry.key == _splashCriticalPath) continue;
      _sourceLoads[entry.key] = _loadSourceSafely(entry.value, entry.key);
    }
  }

  Future<void> _configureBasic(AudioPlayer player) async {
    await player.setPlayerMode(PlayerMode.lowLatency);
    await player.setAudioContext(_tableSoundEffectAudioContext);
    await player.setReleaseMode(ReleaseMode.stop);
  }

  Future<void> _loadSourceSafely(AudioPlayer player, String path) async {
    try {
      await player.setSource(AssetSource(path));
    } catch (error, stackTrace) {
      // Asset resolution can fail in unit tests where the asset bundle isn't
      // wired up; the player stays in the map so playAsset can still attempt
      // the call (and surface its own debugPrint if it fails) rather than
      // crashing the audio path.
      debugPrint('Audio: failed to preload $path: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  Future<void> playAsset(String path, {required double volume}) async {
    if (kDebugMode) {
      debugPrint('[audio] play start: $path');
    }
    await warmUp();
    // Wait specifically for this asset's source load. audioplayers' Android
    // `WrappedPlayer` only flips `released` to false inside the `source`
    // setter (via getOrCreatePlayer). Without that flip, both `stop()` and
    // `resume()` short-circuit and nothing plays.
    final loadFuture = _sourceLoads[path];
    if (loadFuture != null) {
      await loadFuture;
    } else {
      debugPrint('[audio] no load future tracked for $path');
    }
    final player = _players[path];
    if (player == null) {
      debugPrint('[audio] no preloaded player for $path');
      return;
    }
    try {
      // audioplayers v6's SoundPool path never resets `playing` /
      // `streamId` after a sample completes (no MediaPlayer-style
      // onCompletion fires from SoundPool), so the next `resume()` silently
      // no-ops. `stop()` clears both flags so `resume()` falls through to
      // `soundPool.play(soundId)` on the cached sample — no codec churn.
      await player.stop();
      await player.setVolume(volume);
      await player.resume();
      if (kDebugMode) {
        debugPrint('[audio] resume returned: $path');
      }
    } catch (error, stackTrace) {
      debugPrint('[audio] play failed for $path: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  Future<void> dispose() async {
    await Future.wait([
      for (final player in _players.values) player.dispose(),
    ]);
    _players.clear();
    _sourceLoads.clear();
  }
}

class _NoopSoundPlayer implements TableSoundPlayer {
  @override
  Future<void> warmUp() async {}

  @override
  Future<void> playAsset(String path, {required double volume}) async {}

  @override
  Future<void> dispose() async {}
}
