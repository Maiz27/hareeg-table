import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/ui/core/audio/table_audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TableAudio', () {
    test('does not create a native player while disabled', () async {
      var created = 0;
      final audio = TableAudio(
        playerFactory: () {
          created += 1;
          return _RecordingSoundPlayer();
        },
      );

      await audio.play(TableSoundEvent.dealCard);
      await audio.warmUp();

      expect(created, 0);
    });

    test('maps table events to bundled Kenney card sounds', () async {
      final player = _RecordingSoundPlayer();
      final audio = TableAudio(enabled: true, playerFactory: () => player);

      await audio.play(TableSoundEvent.openingShuffle);
      await audio.play(TableSoundEvent.drawStock);
      await audio.play(TableSoundEvent.takeDiscard);
      await audio.play(TableSoundEvent.discardCard);
      await audio.play(TableSoundEvent.meldPlace);
      await audio.play(TableSoundEvent.cardReturn);
      await audio.play(TableSoundEvent.fiftyClaim);
      await audio.play(TableSoundEvent.jokerDeclared);
      await audio.play(TableSoundEvent.roundEnd);
      await audio.play(TableSoundEvent.matchEnd);

      expect(player.paths, [
        'sounds/kenney_casino/card-shuffle.ogg',
        'sounds/kenney_casino/card-slide-2.ogg',
        'sounds/kenney_casino/card-shove-2.ogg',
        'sounds/kenney_casino/card-place-1.ogg',
        'sounds/kenney_casino/card-fan-1.ogg',
        'sounds/kenney_casino/card-shove-3.ogg',
        'sounds/kenney_casino/cards-pack-open-1.ogg',
        'sounds/kenney_casino/cards-pack-take-out-2.ogg',
        'sounds/kenney_casino/cards-pack-take-out-1.ogg',
        'sounds/kenney_casino/cards-pack-open-2.ogg',
      ]);
    });

    test(
      'cycles deal sounds so fast sequences do not repeat one file',
      () async {
        final player = _RecordingSoundPlayer();
        final audio = TableAudio(enabled: true, playerFactory: () => player);

        for (var i = 0; i < 9; i += 1) {
          await audio.play(TableSoundEvent.dealCard);
        }

        expect(player.paths.first, 'sounds/kenney_casino/card-slide-1.ogg');
        expect(player.paths[7], 'sounds/kenney_casino/card-slide-8.ogg');
        expect(player.paths[8], 'sounds/kenney_casino/card-slide-1.ogg');
      },
    );

    test(
      'configures pooled players as non-focus-stealing sound effects',
      () async {
        final previousPlatform = AudioplayersPlatformInterface.instance;
        final previousGlobalPlatform =
            GlobalAudioplayersPlatformInterface.instance;
        final order = <String>[];
        final platform = _FakeAudioplayersPlatform(order: order);
        final globalPlatform = _FakeGlobalAudioplayersPlatform(order: order);
        AudioplayersPlatformInterface.instance = platform;
        GlobalAudioplayersPlatformInterface.instance = globalPlatform;
        final audio = TableAudio(enabled: true);

        try {
          await audio.warmUp();

          final audioContexts = platform.calls
              .where((call) => call.method == 'setAudioContext')
              .map((call) => call.value as AudioContext)
              .toList(growable: false);
          // Pool size is implementation detail (one player per unique cue
          // asset); the load-bearing assertion is that every player is set up
          // as a non-focus-stealing sound effect.
          expect(audioContexts, isNotEmpty);
          expect(
            audioContexts.map((context) => context.android.audioFocus),
            everyElement(AndroidAudioFocus.none),
          );
          expect(
            audioContexts.map((context) => context.android.contentType),
            everyElement(AndroidContentType.sonification),
          );
          expect(
            audioContexts.map((context) => context.android.usageType),
            everyElement(AndroidUsageType.assistanceSonification),
          );
          final globalContexts = globalPlatform.calls
              .where((call) => call.method == 'setGlobalAudioContext')
              .map((call) => call.value as AudioContext)
              .toList(growable: false);
          expect(globalContexts, hasLength(1));
          expect(
            globalContexts.single.android.audioFocus,
            AndroidAudioFocus.none,
          );
          expect(
            order.indexOf('global.setAudioContext'),
            lessThan(order.indexOf('player.create')),
          );
        } finally {
          await audio.dispose();
          AudioplayersPlatformInterface.instance = previousPlatform;
          GlobalAudioplayersPlatformInterface.instance = previousGlobalPlatform;
          await globalPlatform.dispose();
        }
      },
    );
  });
}

class _FakeCall {
  const _FakeCall({required this.id, required this.method, this.value});

  final String id;
  final String method;
  final Object? value;
}

class _FakeAudioplayersPlatform extends AudioplayersPlatformInterface {
  _FakeAudioplayersPlatform({this.order});

  final List<String>? order;
  final calls = <_FakeCall>[];
  final _eventStreams = <String, StreamController<AudioEvent>>{};

  @override
  Future<void> create(String playerId) async {
    order?.add('player.create');
    calls.add(_FakeCall(id: playerId, method: 'create'));
    _eventStreams[playerId] = StreamController<AudioEvent>.broadcast();
  }

  @override
  Future<void> dispose(String playerId) async {
    calls.add(_FakeCall(id: playerId, method: 'dispose'));
    await _eventStreams.remove(playerId)?.close();
  }

  @override
  Future<void> emitError(String playerId, String code, String message) async {
    calls.add(_FakeCall(id: playerId, method: 'emitError'));
  }

  @override
  Future<void> emitLog(String playerId, String message) async {
    calls.add(_FakeCall(id: playerId, method: 'emitLog'));
  }

  @override
  Future<int?> getCurrentPosition(String playerId) async {
    calls.add(_FakeCall(id: playerId, method: 'getCurrentPosition'));
    return 0;
  }

  @override
  Future<int?> getDuration(String playerId) async {
    calls.add(_FakeCall(id: playerId, method: 'getDuration'));
    return 0;
  }

  @override
  Stream<AudioEvent> getEventStream(String playerId) {
    calls.add(_FakeCall(id: playerId, method: 'getEventStream'));
    return _eventStreams[playerId]!.stream;
  }

  @override
  Future<void> pause(String playerId) async {
    calls.add(_FakeCall(id: playerId, method: 'pause'));
  }

  @override
  Future<void> release(String playerId) async {
    calls.add(_FakeCall(id: playerId, method: 'release'));
  }

  @override
  Future<void> resume(String playerId) async {
    calls.add(_FakeCall(id: playerId, method: 'resume'));
  }

  @override
  Future<void> seek(String playerId, Duration position) async {
    calls.add(_FakeCall(id: playerId, method: 'seek', value: position));
  }

  @override
  Future<void> setAudioContext(
    String playerId,
    AudioContext audioContext,
  ) async {
    calls.add(
      _FakeCall(id: playerId, method: 'setAudioContext', value: audioContext),
    );
  }

  @override
  Future<void> setBalance(String playerId, double balance) async {
    calls.add(_FakeCall(id: playerId, method: 'setBalance', value: balance));
  }

  @override
  Future<void> setPlaybackRate(String playerId, double playbackRate) async {
    calls.add(
      _FakeCall(id: playerId, method: 'setPlaybackRate', value: playbackRate),
    );
  }

  @override
  Future<void> setPlayerMode(String playerId, PlayerMode playerMode) async {
    calls.add(
      _FakeCall(id: playerId, method: 'setPlayerMode', value: playerMode),
    );
  }

  @override
  Future<void> setReleaseMode(String playerId, ReleaseMode releaseMode) async {
    calls.add(
      _FakeCall(id: playerId, method: 'setReleaseMode', value: releaseMode),
    );
  }

  @override
  Future<void> setSourceBytes(
    String playerId,
    Uint8List bytes, {
    String? mimeType,
  }) async {
    calls.add(_FakeCall(id: playerId, method: 'setSourceBytes', value: bytes));
  }

  @override
  Future<void> setSourceUrl(
    String playerId,
    String url, {
    bool? isLocal,
    String? mimeType,
  }) async {
    calls.add(_FakeCall(id: playerId, method: 'setSourceUrl', value: url));
  }

  @override
  Future<void> setVolume(String playerId, double volume) async {
    calls.add(_FakeCall(id: playerId, method: 'setVolume', value: volume));
  }

  @override
  Future<void> stop(String playerId) async {
    calls.add(_FakeCall(id: playerId, method: 'stop'));
  }
}

class _FakeGlobalCall {
  const _FakeGlobalCall({required this.method, this.value});

  final String method;
  final Object? value;
}

class _FakeGlobalAudioplayersPlatform
    extends GlobalAudioplayersPlatformInterface {
  _FakeGlobalAudioplayersPlatform({this.order});

  final List<String>? order;
  final calls = <_FakeGlobalCall>[];
  final _eventStream = StreamController<GlobalAudioEvent>.broadcast();

  @override
  Future<void> emitGlobalError(String code, String message) async {
    calls.add(const _FakeGlobalCall(method: 'emitGlobalError'));
    _eventStream.addError(Exception('$code: $message'));
  }

  @override
  Future<void> emitGlobalLog(String message) async {
    calls.add(const _FakeGlobalCall(method: 'emitGlobalLog'));
    _eventStream.add(
      GlobalAudioEvent(
        eventType: GlobalAudioEventType.log,
        logMessage: message,
      ),
    );
  }

  @override
  Stream<GlobalAudioEvent> getGlobalEventStream() {
    calls.add(const _FakeGlobalCall(method: 'getGlobalEventStream'));
    return _eventStream.stream;
  }

  @override
  Future<void> init() async {
    order?.add('global.init');
    calls.add(const _FakeGlobalCall(method: 'init'));
  }

  @override
  Future<void> setGlobalAudioContext(AudioContext ctx) async {
    order?.add('global.setAudioContext');
    calls.add(_FakeGlobalCall(method: 'setGlobalAudioContext', value: ctx));
  }

  Future<void> dispose() async {
    await _eventStream.close();
  }
}

class _RecordingSoundPlayer implements TableSoundPlayer {
  final paths = <String>[];
  final volumes = <double>[];
  var warmed = false;
  var disposed = false;

  @override
  Future<void> warmUp() async {
    warmed = true;
  }

  @override
  Future<void> playAsset(String path, {required double volume}) async {
    paths.add(path);
    volumes.add(volume);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}
