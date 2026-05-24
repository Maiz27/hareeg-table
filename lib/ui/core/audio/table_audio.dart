import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'audio_asset_rotation.dart';
import 'audio_cue_registry.dart';
import 'table_sound_event.dart';

export 'audio_cue_registry.dart' show AudioCue;
export 'table_sound_event.dart';

final AudioContext _tableSoundEffectAudioContext = AudioContext(
  android: const AudioContextAndroid(
    contentType: AndroidContentType.sonification,
    usageType: AndroidUsageType.game,
    audioFocus: AndroidAudioFocus.none,
  ),
  iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
);

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
/// platform audio channels. Cue lookup lives in [AudioCueRegistry] and cursor
/// state in [AudioAssetRotation] so this class stays focused on lifecycle and
/// dispatch.
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
  final AudioAssetRotation _rotation = AudioAssetRotation();

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
    final cue = AudioCueRegistry.lookup(event);
    if (cue == null) {
      // Unmapped event — log once and skip rather than crash a sound that
      // can never play anyway.
      _logAudioFailure(event.name, StateError('no audio cue'), StackTrace.empty);
      return;
    }
    final asset = _rotation.pickAsset(event, cue);
    try {
      await _ensurePlayer().playAsset(asset, volume: cue.volume);
    } catch (error, stackTrace) {
      _logAudioFailure(event.name, error, stackTrace);
    }
  }

  /// Releases any native player resources.
  ///
  /// Catches and logs any failure from the inner player so disposal never
  /// throws back to callers — the app shell only fires this on shutdown and
  /// shouldn't have to defend against half-released native resources.
  Future<void> dispose() async {
    final player = _player;
    _player = null;
    if (player == null) return;
    try {
      await player.dispose();
    } catch (error, stackTrace) {
      debugPrint('TableAudio: dispose failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  TableSoundPlayer _ensurePlayer() {
    return _player ??= _playerFactory();
  }

  void _logAudioFailure(String event, Object error, StackTrace stackTrace) {
    debugPrint('Table audio failed for $event: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

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
  // Last applied volume per player; lets [playAsset] skip the setVolume
  // platform-channel call when the value hasn't changed since the prior play.
  final Map<String, double> _lastVolume = {};
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
  static const _splashCriticalPath =
      'sounds/kenney_casino/cards-pack-take-out-1.ogg';

  /// Grace period after warmup begins before non-splash players start
  /// configuring + loading. The splash → home → setup transition kicks off
  /// during this window; deferring the heavier setup avoids contention with
  /// route-transition frames.
  static const _warmupStartupGrace = Duration(milliseconds: 1200);

  /// Gap between each non-splash player's configure + load step. Wider gaps
  /// keep mediaserver IPC from piling up during navigation; total warmup
  /// stretches to ~`gap × N` ms but each frame stays cheap.
  static const _warmupStepGap = Duration(milliseconds: 60);

  Future<void> _initAllPlayers() async {
    final uniquePaths = AudioCueRegistry.allAssetPaths();
    // Create the AudioPlayer instances synchronously so [playAsset] can find
    // them in the map immediately. This is one platform-channel `create` call
    // per player — cheap individually, but the configure + setSource steps
    // are deferred onto the chain so they don't blast the main thread at
    // launch.
    for (final path in uniquePaths) {
      _players[path] = AudioPlayer();
    }
    // Configure + load the splash sample synchronously so the splash audio
    // cue isn't racing anything else.
    final splashPlayer = _players[_splashCriticalPath];
    if (splashPlayer != null) {
      await _configureBasic(splashPlayer);
      final future = _loadSourceSafely(splashPlayer, _splashCriticalPath);
      _sourceLoads[_splashCriticalPath] = future;
      await future;
    }
    // Defer configure + setSource for every other player onto a chain that
    // starts after [_warmupStartupGrace] and spaces each step by
    // [_warmupStepGap]. Each step is ~4 platform-channel calls (3 configure +
    // 1 setSource); spreading them out keeps the splash → home → setup
    // transitions free of mediaserver IPC pressure.
    _scheduleStaggeredLoads(
      [
        for (final entry in _players.entries)
          if (entry.key != _splashCriticalPath) entry,
      ],
      startupGrace: _warmupStartupGrace,
      gap: _warmupStepGap,
    );
  }

  void _scheduleStaggeredLoads(
    List<MapEntry<String, AudioPlayer>> entries, {
    required Duration startupGrace,
    required Duration gap,
  }) {
    final completers = <String, Completer<void>>{
      for (final entry in entries) entry.key: Completer<void>(),
    };
    // Publish per-asset futures synchronously so playAsset can await them
    // even before the load future actually runs.
    for (final entry in entries) {
      _sourceLoads[entry.key] = completers[entry.key]!.future;
    }
    Future<void> chain = Future<void>.delayed(startupGrace);
    for (final entry in entries) {
      final localPath = entry.key;
      final localPlayer = entry.value;
      chain = chain.then((_) async {
        try {
          await _configureBasic(localPlayer);
          await _loadSourceSafely(localPlayer, localPath);
        } finally {
          if (!completers[localPath]!.isCompleted) {
            completers[localPath]!.complete();
          }
        }
        await Future<void>.delayed(gap);
      });
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
      if (_lastVolume[path] != volume) {
        await player.setVolume(volume);
        _lastVolume[path] = volume;
      }
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
    // `eagerError: false` so a failure on one player still lets the rest run
    // to completion; the try/catch absorbs the aggregated rejection so the
    // finally always reaches the map clears.
    try {
      await Future.wait(
        [for (final player in _players.values) player.dispose()],
        eagerError: false,
      );
    } catch (error, stackTrace) {
      debugPrint('Audio: one or more players failed to dispose: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _players.clear();
      _sourceLoads.clear();
      _lastVolume.clear();
    }
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
