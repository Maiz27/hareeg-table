import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_action_transcript.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_recorder.dart';

import '../../../scenario/classic_hareeg_match_driver.dart';

void main() {
  group('MatchActionTranscript', () {
    test('records player and CPU actions in one replayable format', () {
      final recorder = MatchRecorder();
      ClassicHareegMatchDriver(actionLimit: 80).run(
        setup: ClassicHareegSetup.defaults().copyWith(
          cpuDifficulty: CpuDifficulty.skilled,
        ),
        seed: 7,
        recorder: recorder,
      );

      final transcript = recorder.transcript;
      expect(transcript, isNotNull);
      expect(transcript!.entries, isNotEmpty);

      final seats = transcript.entries.map((e) => e.seat).toSet();
      expect(seats.contains(PlayerSeat.south), isTrue,
          reason: 'the human seat acts in a driven match');
      expect(
        seats.where((s) => s != PlayerSeat.south),
        isNotEmpty,
        reason: 'CPU seats use the identical transcript entry shape',
      );

      // Orders are contiguous from zero — the single applyAction seam captures
      // every accepted action across seats.
      final orders = transcript.entries.map((e) => e.order).toList();
      expect(orders, List.generate(orders.length, (i) => i));
    });

    test('round-trips through JSON', () {
      final recorder = MatchRecorder();
      ClassicHareegMatchDriver(actionLimit: 60).run(
        setup: ClassicHareegSetup.defaults(),
        seed: 11,
        recorder: recorder,
      );
      final transcript = recorder.transcript!;

      final decoded = MatchActionTranscript.fromJson(transcript.toJson());

      expect(decoded.entries, hasLength(transcript.entries.length));
      expect(
        decoded.entries.map((e) => e.actionId),
        transcript.entries.map((e) => e.actionId),
      );
      expect(
        decoded.initialSnapshot.seed,
        transcript.initialSnapshot.seed,
      );
      expect(decoded.toJson()['version'], matchActionTranscriptVersion);
    });

    test('rejects unsupported transcript versions', () {
      final recorder = MatchRecorder();
      ClassicHareegMatchDriver(actionLimit: 30).run(
        setup: ClassicHareegSetup.defaults(),
        seed: 3,
        recorder: recorder,
      );
      final json = recorder.transcript!.toJson()..['version'] = 99;

      expect(
        () => MatchActionTranscript.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Unsupported match transcript version 99'),
          ),
        ),
      );
    });

    test('is null before any action is recorded', () {
      expect(MatchRecorder().transcript, isNull);
    });
  });
}
