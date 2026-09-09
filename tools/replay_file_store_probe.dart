/// Runtime probe for the replay file store.
///
/// This is an alternate entrypoint, not part of the shipped app. It exists
/// because the interesting properties of the store — that Android really puts
/// payloads under the no-backup directory, that the *native* handler rejects a
/// traversal key even when Dart validation is bypassed, and that a payload
/// survives process death — cannot be observed from a unit test.
///
/// Nothing runs on launch. Each phase is a separate button so the files a
/// phase leaves behind are still there for `adb` to inspect before the next
/// phase runs.
///
/// Run it with:
///
/// ```
/// flutter run -d <emulator-id> --target=tools/replay_file_store_probe.dart --no-pub
/// flutter run -d web-server --web-port 7357 --target=tools/replay_file_store_probe.dart --no-pub
/// ```
///
/// `docs/testing/replay-file-store-verification.md` carries the full sequence,
/// including when to pause, inject, force-stop, and clean up.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hareeg_table/data/persistence/key_value_store_factory.dart';
import 'package:hareeg_table/data/persistence/replay_file_store.dart';
import 'package:hareeg_table/data/persistence/replay_file_store_factory.dart';

const MethodChannel _rawChannel = MethodChannel('hareeg_table/local_storage');

const String _alphaKey = 'probe-alpha';
const String _betaKey = 'probe-beta';

/// A key whose file name is occupied by a directory during phase B.
const String _deltaKey = 'probe-delta';

const String _alphaPayload =
    'حريقة على الطاولة\n'
    'round one 🏆\n'
    'joker 🃏 fifty 🔥\n'
    r'{"quoted":"a\\b"}';

const String _shorterAlphaPayload = 'short';

void main() {
  runApp(const _ProbeApp());
}

/// One reported probe step.
class _Step {
  _Step.pass(this.label) : passed = true, detail = null;

  _Step.fail(this.label, this.detail) : passed = false;

  _Step.info(this.label) : passed = null, detail = null;

  final String label;
  final bool? passed;
  final String? detail;

  String get prefix => switch (passed) {
    true => 'PASS',
    false => 'FAIL',
    null => 'INFO',
  };
}

class _ProbeApp extends StatefulWidget {
  const _ProbeApp();

  @override
  State<_ProbeApp> createState() => _ProbeAppState();
}

class _ProbeAppState extends State<_ProbeApp> {
  final ReplayFileStore _store = createDefaultReplayFileStore();
  final List<_Step> _steps = <_Step>[];

  String _phase = 'none';
  bool _running = false;

  void _emit(_Step step) {
    debugPrint('[probe] ${step.prefix} ${step.label}'
        '${step.detail == null ? '' : ' — ${step.detail}'}');
    setState(() => _steps.add(step));
  }

  void _check(String label, bool condition, [String? detail]) {
    _emit(condition ? _Step.pass(label) : _Step.fail(label, detail ?? 'failed'));
  }

  Future<void> _run(String phase, Future<void> Function() body) async {
    setState(() {
      _phase = phase;
      _steps.clear();
      _running = true;
    });

    try {
      await body();
    } catch (error) {
      _emit(_Step.fail('phase $phase aborted', '$error'));
    } finally {
      setState(() => _running = false);
    }
  }

  /// Setup. Leaves both replay files in place — deletes nothing at the end,
  /// so `adb` can inspect the real directory afterwards.
  Future<void> _phaseA() async {
    var removed = 0;
    for (final key in await _store.listKeys()) {
      if (key.startsWith('probe-')) {
        await _store.deleteFile(key);
        removed++;
      }
    }
    _emit(_Step.info('A1 cleared $removed pre-existing probe key(s)'));

    final residual = (await _store.listKeys())
        .where((key) => key.startsWith('probe-'))
        .toList();
    _check('A2 store holds no probe key', residual.isEmpty, '$residual');

    _check('A3 absent read returns null', await _store.readFile(_alphaKey) == null);

    await _store.writeFile(_alphaKey, _alphaPayload);
    _check('A4 wrote $_alphaKey', true);

    final readBack = await _store.readFile(_alphaKey);
    _check(
      'A5 read back byte-identical (arabic + emoji + newlines)',
      readBack == _alphaPayload,
      'got ${readBack?.length} chars, expected ${_alphaPayload.length}',
    );

    await _store.writeFile(_betaKey, 'beta payload');
    final listed = await _store.listKeys();
    _check(
      'A6 listKeys is [$_alphaKey, $_betaKey]',
      listed.join(',') == '$_alphaKey,$_betaKey',
      '$listed',
    );

    await _store.writeFile(_alphaKey, _shorterAlphaPayload);
    final overwritten = await _store.readFile(_alphaKey);
    _check(
      'A7 shorter overwrite leaves no stale tail',
      overwritten == _shorterAlphaPayload,
      '$overwritten',
    );

    // Restore the long payload so the resume phase has something distinctive
    // to read after a force-stop.
    await _store.writeFile(_alphaKey, _alphaPayload);
    _check('A8 restored the long $_alphaKey payload', true);

    final keyValue = createDefaultKeyValueStore();
    await keyValue.saveString('probe.kv', 'kv still works');
    final kvValue = await keyValue.loadString('probe.kv');
    _check(
      'A9 key/value round trip on the same channel is unaffected',
      kvValue == 'kv still works',
      '$kvValue',
    );
    await keyValue.remove('probe.kv');

    _emit(_Step.info('A10 both replay files left in place for adb inspection'));
  }

  /// List guard. Run after injecting foreign entries into the real directory.
  ///
  /// It asks the store *and* the raw channel, because the Dart store filters
  /// too — only the raw answer proves the native handler is the one doing the
  /// skipping.
  Future<void> _phaseB() async {
    final listed = await _store.listKeys();
    _check(
      'B1 store listKeys is [$_alphaKey, $_betaKey]',
      listed.join(',') == '$_alphaKey,$_betaKey',
      '$listed',
    );

    // A directory can occupy a replay file name. Reading it must report absent
    // and deleting it must report "did not exist" and leave it alone — the
    // alternative is recursively deleting something that was never a replay.
    final collision = await _store.readFile(_deltaKey);
    _check(
      'B3 directory collision on $_deltaKey reads as absent',
      collision == null,
      '$collision',
    );

    final deletedCollision = await _store.deleteFile(_deltaKey);
    _check(
      'B4 directory collision reports "did not exist" and is not removed',
      deletedCollision == false,
      '$deletedCollision',
    );

    if (kIsWeb) {
      _emit(_Step.info('B5 raw channel check not applicable on web'));
      return;
    }

    final raw = await _rawChannel.invokeListMethod<String>('listFiles');
    _check(
      'B5 raw native listFiles already excludes the injected entries',
      raw != null && raw.join(',') == '$_alphaKey,$_betaKey',
      '$raw',
    );
  }

  /// Native guard, bypassing the Dart key validation entirely.
  Future<void> _phaseC() async {
    if (kIsWeb) {
      _emit(_Step.info('C0 not applicable on web: there is no method channel'));
      return;
    }

    const unsafeKeys = <String>['../escape', 'a/b', '.hidden', 'a b', ''];
    var step = 1;

    for (final key in unsafeKeys) {
      for (final method in <String>['readFile', 'writeFile', 'deleteFile']) {
        final arguments = <String, Object?>{
          'key': key,
          if (method == 'writeFile') 'value': 'payload',
        };

        String outcome;
        try {
          await _rawChannel.invokeMethod<Object?>(method, arguments);
          outcome = 'returned normally';
        } on PlatformException catch (error) {
          outcome = error.code;
        } catch (error) {
          outcome = '$error';
        }

        _check(
          'C$step native $method("$key") -> invalid_key',
          outcome == 'invalid_key',
          outcome,
        );
        step++;
      }
    }

    String unknownOutcome;
    try {
      final value = await _rawChannel.invokeMethod<String>(
        'readFile',
        <String, Object?>{'key': 'probe-never-written'},
      );
      unknownOutcome = value == null ? 'null' : 'value';
    } on PlatformException catch (error) {
      unknownOutcome = error.code;
    }
    _check(
      'C$step native readFile(valid unknown key) -> null, not an error',
      unknownOutcome == 'null',
      unknownOutcome,
    );
  }

  /// Resume. Reads only — no write, no cleanup, no clean-store assertion.
  Future<void> _phaseD() async {
    final restored = await _store.readFile(_alphaKey);
    _check(
      'D1 $_alphaKey survived the process restart byte-identical',
      restored == _alphaPayload,
      restored == null ? 'absent' : '${restored.length} chars',
    );
  }

  /// Cleanup.
  Future<void> _phaseE() async {
    for (final key in <String>[_alphaKey, _betaKey]) {
      final removed = await _store.deleteFile(key);
      _emit(_Step.info('E: deleted $key -> $removed'));
    }

    final remaining = await _store.listKeys();
    final probeKeys = remaining.where((key) => key.startsWith('probe-')).toList();
    _check('E1 no probe key remains', probeKeys.isEmpty, '$probeKeys');
    _emit(
      _Step.info(
        'E2 remaining listed keys: $remaining '
        '(injected non-key entries, if any, must be removed with adb)',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final failures = _steps.where((step) => step.passed == false).length;

    return MaterialApp(
      title: 'Replay file store probe',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: Text('Replay probe — phase $_phase'),
          backgroundColor: failures > 0 ? Colors.red.shade900 : null,
        ),
        body: Column(
          children: <Widget>[
            Wrap(
              spacing: 8,
              children: <Widget>[
                _phaseButton('A setup', () => _run('A', _phaseA)),
                _phaseButton('B list guard', () => _run('B', _phaseB)),
                _phaseButton('C native guard', () => _run('C', _phaseC)),
                _phaseButton('D resume', () => _run('D', _phaseD)),
                _phaseButton('E cleanup', () => _run('E', _phaseE)),
              ],
            ),
            const Divider(),
            Text(
              _steps.isEmpty
                  ? 'No phase has run yet.'
                  : '$failures failure(s) in ${_steps.length} step(s)',
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _steps.length,
                itemBuilder: (context, index) {
                  final step = _steps[index];
                  return ListTile(
                    dense: true,
                    leading: Text(step.prefix),
                    title: Text(step.label),
                    subtitle: step.detail == null ? null : Text(step.detail!),
                    textColor: switch (step.passed) {
                      true => Colors.green,
                      false => Colors.red,
                      null => null,
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _phaseButton(String label, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: _running ? null : onPressed,
      child: Text(label),
    );
  }
}
