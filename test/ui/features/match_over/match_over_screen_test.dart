import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/app/app_routes.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/classic_hareeg_match_report.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/match_progression_rules.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/core/audio/table_audio.dart';
import 'package:hareeg_table/ui/core/haptics/table_haptics.dart';
import 'package:hareeg_table/ui/core/motion/motion_speed.dart';
import 'package:hareeg_table/ui/core/scopes/app_scopes.dart';
import 'package:hareeg_table/ui/features/match_over/views/match_over_screen.dart';
import 'package:hareeg_table/ui/features/match_reports/match_report_exporter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('south win shows personalized headline and finish subline', (
    tester,
  ) async {
    await tester.pumpWidget(_app(arguments: _arguments()));

    expect(find.text('MATCH OVER'), findsOneWidget);
    expect(find.text('You win the match'), findsOneWidget);
    expect(find.text('Won by finish'), findsOneWidget);
    expect(find.text('FINAL STANDINGS'), findsOneWidget);
  });

  testWidgets('CPU win shows seat headline and Fifty subline', (tester) async {
    await tester.pumpWidget(
      _app(
        arguments: _arguments(
          result: _fiftyResult,
          progress: _progress(winner: PlayerSeat.east),
        ),
      ),
    );

    expect(find.text('CPU East wins the match'), findsOneWidget);
    expect(find.text('Won by Fifty'), findsOneWidget);
  });

  testWidgets('final standings sort by score and show eliminated rounds', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        arguments: _arguments(
          progress: const MatchProgressState(
            scores: {
              PlayerSeat.south: 12,
              PlayerSeat.east: -3,
              PlayerSeat.north: 31,
              PlayerSeat.west: 34,
            },
            activeSeats: [PlayerSeat.east],
            nextStarter: PlayerSeat.east,
            matchWinner: PlayerSeat.east,
          ),
          eliminatedRound: const {
            PlayerSeat.south: 5,
            PlayerSeat.north: 4,
            PlayerSeat.west: 3,
          },
        ),
      ),
    );

    final eastTop = tester.getTopLeft(
      find.byKey(const ValueKey('final-standing-east')),
    );
    final southTop = tester.getTopLeft(
      find.byKey(const ValueKey('final-standing-south')),
    );
    final northTop = tester.getTopLeft(
      find.byKey(const ValueKey('final-standing-north')),
    );

    expect(eastTop.dy, lessThan(southTop.dy));
    expect(southTop.dy, lessThan(northTop.dy));
    expect(find.text('Eliminated in round 5'), findsOneWidget);
    expect(find.text('Eliminated in round 4'), findsOneWidget);
    expect(find.text('Eliminated in round 3'), findsOneWidget);
  });

  testWidgets('round count handles singular and plural copy', (tester) async {
    await tester.pumpWidget(_app(arguments: _arguments(roundsPlayed: 1)));
    expect(find.text('1 round played'), findsOneWidget);

    await tester.pumpWidget(_app(arguments: _arguments(roundsPlayed: 7)));
    expect(find.text('7 rounds played'), findsOneWidget);
  });

  testWidgets('return-to-menu button clears stack to home', (tester) async {
    await tester.pumpWidget(_app(arguments: _arguments()));

    await tester.tap(find.byKey(const ValueKey('match-over-return-menu')));
    await tester.pumpAndSettle();

    expect(find.text('Home route'), findsOneWidget);
    expect(find.byType(MatchOverScreen), findsNothing);
  });

  testWidgets('rematch button opens table route with same setup', (
    tester,
  ) async {
    final setup = ClassicHareegSetup.defaults().copyWith(
      cpuDifficulty: CpuDifficulty.expert,
      tableStrictness: TableStrictness.table,
    );
    ClassicHareegSetup? routeSetup;

    await tester.pumpWidget(
      _app(
        arguments: _arguments(setup: setup),
        onTableRoute: (value) => routeSetup = value,
      ),
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('match-over-rematch')),
    );
    await tester.tap(find.byKey(const ValueKey('match-over-rematch')));
    await tester.pumpAndSettle();

    expect(find.text('Table route'), findsOneWidget);
    expect(routeSetup, same(setup));
  });

  testWidgets('export button offers clipboard fallback with completed report', (
    tester,
  ) async {
    final clipboard = _RecordingClipboardGateway();
    await tester.pumpWidget(
      _app(
        arguments: _arguments(),
        reportExporter: MatchReportExporter(
          shareGateway: const UnavailableMatchReportShareGateway(),
          clipboardGateway: clipboard,
        ),
      ),
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('match-over-export-report')),
    );
    await tester.tap(find.byKey(const ValueKey('match-over-export-report')));
    await tester.pump();

    expect(
      find.text(
        'File sharing is not available here. Copy the report JSON instead?',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Copy report'));
    await tester.pump();

    expect(find.text('Match report copied to clipboard.'), findsOneWidget);
    final decoded = ClassicHareegMatchReport.fromJson(
      _jsonMap(jsonDecode(clipboard.text!)),
    );
    expect(decoded.stage, MatchReportStage.completed);
    expect(decoded.matchProgress!.matchWinner, PlayerSeat.south);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('export success keeps copy action available', (tester) async {
    final clipboard = _RecordingClipboardGateway();
    await tester.pumpWidget(
      _app(
        arguments: _arguments(),
        reportExporter: MatchReportExporter(
          shareGateway: const _SuccessfulShareGateway(),
          clipboardGateway: clipboard,
        ),
      ),
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('match-over-export-report')),
    );
    await tester.tap(find.byKey(const ValueKey('match-over-export-report')));
    await tester.pump();

    expect(find.text('Match report ready to share.'), findsOneWidget);
    expect(find.text('Copy report'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('lounge-toast'))).width,
      lessThanOrEqualTo(360),
    );

    await tester.tap(find.text('Copy report'));
    await tester.pump();

    expect(find.text('Match report copied to clipboard.'), findsOneWidget);
    final decoded = ClassicHareegMatchReport.fromJson(
      _jsonMap(jsonDecode(clipboard.text!)),
    );
    expect(decoded.stage, MatchReportStage.completed);
    expect(decoded.matchProgress!.matchWinner, PlayerSeat.south);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('Arabic locale renders localized labels in RTL', (tester) async {
    await tester.pumpWidget(
      _app(arguments: _arguments(), strings: AppStrings.arabic),
    );

    final context = tester.element(find.byType(MatchOverScreen));
    expect(Directionality.of(context), TextDirection.rtl);
    expect(find.text('انتهت المباراة'), findsOneWidget);
    expect(find.text('الترتيب النهائي'), findsOneWidget);
  });

  testWidgets('reduced motion suppresses medallion pulse', (tester) async {
    await tester.pumpWidget(
      _app(
        arguments: _arguments(),
        motion: const MotionSettings(
          speed: MotionSpeed.reduced,
          osReducedMotion: false,
        ),
      ),
    );

    expect(find.byKey(const ValueKey('match-over-pulse')), findsNothing);
  });

  testWidgets('table strictness suppresses south-win haptic', (tester) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      _app(
        arguments: _arguments(),
        strictness: TableStrictness.table,
        haptics: TableHaptics(),
      ),
    );
    await tester.pump();

    expect(
      calls.where((call) => call.method == 'HapticFeedback.vibrate'),
      isEmpty,
    );
  });

  testWidgets('first frame fires match-end audio and south-win haptic once', (
    tester,
  ) async {
    final player = _RecordingSoundPlayer();
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      _app(
        arguments: _arguments(),
        audio: TableAudio(enabled: true, playerFactory: () => player),
        haptics: TableHaptics(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(player.paths, ['sounds/kenney_casino/cards-pack-open-2.ogg']);
    expect(
      calls.where((call) => call.method == 'HapticFeedback.vibrate'),
      hasLength(1),
    );
  });

  testWidgets('CPU match win skips celebratory haptic', (tester) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      _app(
        arguments: _arguments(progress: _progress(winner: PlayerSeat.east)),
        haptics: TableHaptics(),
      ),
    );
    await tester.pump();

    expect(
      calls.where((call) => call.method == 'HapticFeedback.vibrate'),
      isEmpty,
    );
  });
}

Widget _app({
  required MatchOverArguments arguments,
  AppStrings strings = AppStrings.english,
  TableStrictness strictness = TableStrictness.coaching,
  MotionSettings motion = const MotionSettings(
    speed: MotionSpeed.normal,
    osReducedMotion: false,
  ),
  TableAudio? audio,
  TableHaptics? haptics,
  ValueChanged<ClassicHareegSetup>? onTableRoute,
  MatchReportExporter? reportExporter,
}) {
  return MaterialApp(
    key: UniqueKey(),
    initialRoute: AppRoutes.matchOver,
    onGenerateRoute: (settings) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (context) {
          return switch (settings.name) {
            AppRoutes.matchOver => _scoped(
              strings: strings,
              strictness: strictness,
              motion: motion,
              audio: audio,
              haptics: haptics,
              child: MatchOverScreen(
                arguments: arguments,
                reportExporter: reportExporter ?? const MatchReportExporter(),
              ),
            ),
            AppRoutes.home => const Scaffold(
              body: Center(child: Text('Home route')),
            ),
            AppRoutes.table => _tableRoute(settings, onTableRoute),
            _ => const Scaffold(body: Center(child: Text('Unknown route'))),
          };
        },
      );
    },
  );
}

Widget _scoped({
  required AppStrings strings,
  required TableStrictness strictness,
  required MotionSettings motion,
  required Widget child,
  TableAudio? audio,
  TableHaptics? haptics,
}) {
  return MotionScope(
    settings: motion,
    child: StrictnessScope(
      strictness: strictness,
      child: HapticsScope(
        haptics: haptics ?? TableHaptics(enabled: false),
        child: AudioScope(
          audio: audio ?? TableAudio.noop(),
          child: AppStringsScope(
            strings: strings,
            child: Directionality(
              textDirection: strings.textDirection,
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _tableRoute(
  RouteSettings settings,
  ValueChanged<ClassicHareegSetup>? onTableRoute,
) {
  final setup = settings.arguments as ClassicHareegSetup;
  onTableRoute?.call(setup);
  return const Scaffold(body: Center(child: Text('Table route')));
}

MatchOverArguments _arguments({
  RoundProgressResult result = _normalResult,
  MatchProgressState? progress,
  int roundsPlayed = 5,
  ClassicHareegSetup? setup,
  Map<PlayerSeat, int> eliminatedRound = const {
    PlayerSeat.east: 5,
    PlayerSeat.north: 4,
    PlayerSeat.west: 3,
  },
}) {
  return MatchOverArguments(
    result: result,
    progress: progress ?? _progress(winner: PlayerSeat.south),
    previousScores: const {
      PlayerSeat.south: -2,
      PlayerSeat.east: 28,
      PlayerSeat.north: 27,
      PlayerSeat.west: 29,
    },
    roundsPlayed: roundsPlayed,
    setup: setup ?? ClassicHareegSetup.defaults(),
    finalSnapshot: _snapshot(
      setup: setup ?? ClassicHareegSetup.defaults(),
      roundNumber: roundsPlayed,
      scores: progress?.scores ?? _progress(winner: PlayerSeat.south).scores,
    ),
    eliminatedRound: eliminatedRound,
  );
}

MatchProgressState _progress({required PlayerSeat winner}) {
  return MatchProgressState(
    scores: {
      PlayerSeat.south: winner == PlayerSeat.south ? -3 : 34,
      PlayerSeat.east: winner == PlayerSeat.east ? -3 : 31,
      PlayerSeat.north: 32,
      PlayerSeat.west: 38,
    },
    activeSeats: [winner],
    nextStarter: winner,
    matchWinner: winner,
  );
}

const _normalResult = RoundProgressResult(
  type: RoundOutcomeType.normalFinish,
  winner: PlayerSeat.south,
  remainingCardCounts: {
    PlayerSeat.south: 0,
    PlayerSeat.east: 4,
    PlayerSeat.north: 8,
    PlayerSeat.west: 9,
  },
);

const _fiftyResult = RoundProgressResult(
  type: RoundOutcomeType.fiftyFinish,
  winner: PlayerSeat.east,
  fiftyDiscarder: PlayerSeat.south,
  remainingCardCounts: {
    PlayerSeat.south: 11,
    PlayerSeat.east: 0,
    PlayerSeat.north: 6,
    PlayerSeat.west: 8,
  },
);

class _RecordingSoundPlayer implements TableSoundPlayer {
  final paths = <String>[];

  @override
  Future<void> warmUp() async {}

  @override
  Future<void> playAsset(String path, {required double volume}) async {
    paths.add(path);
  }

  @override
  Future<void> dispose() async {}
}

ClassicHareegMatchSnapshot _snapshot({
  required ClassicHareegSetup setup,
  required int roundNumber,
  required Map<PlayerSeat, int> scores,
}) {
  final round = ClassicHareegRound.deal(setup: setup, seed: 13);
  return ClassicHareegMatchSnapshot(
    setup: setup,
    hands: round.hands,
    seed: round.seed,
    stock: round.stock,
    discardPile: round.discardPile,
    starter: round.starter,
    currentSeat: round.currentSeat,
    turnPhase: round.turnPhase,
    scores: scores,
    activeSeats: const [PlayerSeat.south],
    roundNumber: roundNumber,
    savedAt: DateTime.utc(2026, 6, 9),
  );
}

Map<String, Object?> _jsonMap(Object? value) {
  final map = value as Map<String, dynamic>;
  return {for (final entry in map.entries) entry.key: entry.value};
}

class _RecordingClipboardGateway implements MatchReportClipboardGateway {
  String? text;

  @override
  Future<void> copyText(String text) async {
    this.text = text;
  }
}

class _SuccessfulShareGateway implements MatchReportShareGateway {
  const _SuccessfulShareGateway();

  @override
  Future<void> shareText({
    required String fileName,
    required String text,
    required String mimeType,
  }) async {}
}
