import 'dart:io';

import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/match_progression_rules.dart';

import '../test/scenario/classic_hareeg_match_driver.dart';

void main(List<String> args) {
  final config = _AuditConfig.fromArgs(args);
  stdout.writeln(
    'CPU difficulty audit '
    'strictness=${config.strictness.name} '
    'jokers=${config.jokerCount} '
    'limit=${config.actionLimit} '
    'seeds=${config.seeds.join(",")}',
  );
  stdout.writeln('');

  for (final difficulty in config.difficulties) {
    final aggregate = _DifficultyAggregate(difficulty);
    for (final seed in config.seeds) {
      final setup = ClassicHareegSetup.defaults().copyWith(
        cpuDifficulty: difficulty,
        tableStrictness: config.strictness,
        jokerCount: config.jokerCount,
      );
      final metrics = _runCase(
        setup: setup,
        seed: seed,
        actionLimit: config.actionLimit,
      );
      aggregate.add(metrics);
      stdout.writeln(metrics.summaryLine());
    }
    stdout.writeln(aggregate.summaryBlock());
  }
}

_RunMetrics _runCase({
  required ClassicHareegSetup setup,
  required int seed,
  required int actionLimit,
}) {
  final metrics = _RunMetrics(
    difficulty: setup.cpuDifficulty,
    strictness: setup.tableStrictness,
    seed: seed,
  );
  final watch = Stopwatch()..start();
  final report = ClassicHareegMatchDriver(actionLimit: actionLimit).run(
    setup: setup,
    seed: seed,
    onStep: metrics.recordStep,
    onRoundEnd: metrics.recordRound,
  );
  watch.stop();
  return metrics
    ..elapsed = watch.elapsed
    ..stopReason = report.stopReason
    ..winner = report.winner
    ..totalActions = report.totalActions
    ..rounds = report.rounds.length;
}

final class _AuditConfig {
  const _AuditConfig({
    required this.difficulties,
    required this.strictness,
    required this.jokerCount,
    required this.actionLimit,
    required this.seeds,
  });

  final List<CpuDifficulty> difficulties;
  final TableStrictness strictness;
  final int jokerCount;
  final int actionLimit;
  final List<int> seeds;

  factory _AuditConfig.fromArgs(List<String> args) {
    var difficulties = CpuDifficulty.values;
    var strictness = TableStrictness.standard;
    var jokerCount = 2;
    var actionLimit = 200;
    var seeds = const [1, 2, 3];

    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      String readValue() {
        if (index + 1 >= args.length) {
          stderr.writeln('Missing value for $arg');
          exit(64);
        }
        index += 1;
        return args[index];
      }

      switch (arg) {
        case '--difficulty':
        case '-d':
          difficulties = readValue()
              .split(',')
              .map((name) => CpuDifficulty.fromName(name.trim()))
              .toList(growable: false);
        case '--strictness':
        case '-s':
          strictness = TableStrictness.fromName(readValue());
        case '--jokers':
        case '-j':
          jokerCount = int.parse(readValue());
        case '--limit':
        case '-l':
          actionLimit = int.parse(readValue());
        case '--seeds':
          seeds = readValue()
              .split(',')
              .where((value) => value.trim().isNotEmpty)
              .map((value) => int.parse(value.trim()))
              .toList(growable: false);
        case '--help':
        case '-h':
          _printUsage();
          exit(0);
        default:
          stderr.writeln('Unknown argument: $arg');
          _printUsage();
          exit(64);
      }
    }

    return _AuditConfig(
      difficulties: List.unmodifiable(difficulties),
      strictness: strictness,
      jokerCount: jokerCount,
      actionLimit: actionLimit,
      seeds: List.unmodifiable(seeds),
    );
  }

  static void _printUsage() {
    stdout.writeln(
      'Usage: dart run tools/cpu_difficulty_audit.dart '
      '[--difficulty beginner,casual,skilled,expert] '
      '[--strictness table|standard|strict|coaching] '
      '[--jokers 2] [--limit 200] [--seeds 1,2,3]',
    );
  }
}

final class _RunMetrics {
  _RunMetrics({
    required this.difficulty,
    required this.strictness,
    required this.seed,
  });

  final CpuDifficulty difficulty;
  final TableStrictness strictness;
  final int seed;
  final Map<ClassicHareegActionKind, int> actionCounts = {};
  final Map<PlayerSeat, int> winners = {};
  final List<int> meldCardCounts = [];
  final List<int> legalSurfaceSizes = [];
  final Set<PlayerSeat> fiftyClaimants = {};
  MatchStopReason? stopReason;
  PlayerSeat? winner;
  Duration elapsed = Duration.zero;
  int totalActions = 0;
  int rounds = 0;
  int drawRounds = 0;
  int fiftyRounds = 0;
  int normalRounds = 0;
  int maxHandCount = 0;

  void recordStep(MatchStep step) {
    final descriptor = ClassicHareegActionIds.describe(step.actionId);
    actionCounts.update(
      descriptor.kind,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    legalSurfaceSizes.add(step.legalActionIds.length);
    maxHandCount = [
      maxHandCount,
      ...step.handCounts.values,
    ].reduce((left, right) => left > right ? left : right);
    if (descriptor.isMeldPlay ||
        descriptor.kind == ClassicHareegActionKind.placeCover) {
      meldCardCounts.add(descriptor.cardIds.length);
    }
  }

  void recordRound(DrivenRoundReport report) {
    final result = report.result;
    if (result == null) {
      return;
    }
    final winner = result.winner;
    if (winner != null) {
      winners.update(winner, (value) => value + 1, ifAbsent: () => 1);
    }
    switch (result.type) {
      case RoundOutcomeType.draw:
        drawRounds += 1;
      case RoundOutcomeType.fiftyFinish:
        fiftyRounds += 1;
        if (winner != null) {
          fiftyClaimants.add(winner);
        }
      case RoundOutcomeType.normalFinish:
        normalRounds += 1;
    }
  }

  String summaryLine() {
    final kinds = [
      _countLabel('draw', ClassicHareegActionKind.drawStock),
      _countLabel('take', ClassicHareegActionKind.takeDiscard),
      _countLabel('meld', ClassicHareegActionKind.playMeld),
      _countLabel('jokerMeld', ClassicHareegActionKind.playMeldWithJoker),
      _countLabel('cover', ClassicHareegActionKind.placeCover),
      _countLabel('replace', ClassicHareegActionKind.replaceJoker),
      _countLabel('discard', ClassicHareegActionKind.discard),
      _countLabel('fifty', ClassicHareegActionKind.claimFifty),
    ].join(' ');
    return '${difficulty.name.padRight(8)} seed=${seed.toString().padLeft(2)} '
        'stop=${stopReason?.name ?? "-"} '
        'actions=${totalActions.toString().padLeft(3)} '
        'rounds=${rounds.toString().padLeft(2)} '
        'elapsed=${elapsed.inMilliseconds}ms '
        '$kinds '
        'avgLegal=${_average(legalSurfaceSizes).toStringAsFixed(1)} '
        'avgPlayCards=${_average(meldCardCounts).toStringAsFixed(1)}';
  }

  String _countLabel(String label, ClassicHareegActionKind kind) {
    return '$label=${actionCounts[kind] ?? 0}';
  }
}

final class _DifficultyAggregate {
  _DifficultyAggregate(this.difficulty);

  final CpuDifficulty difficulty;
  final List<_RunMetrics> runs = [];

  void add(_RunMetrics metrics) => runs.add(metrics);

  String summaryBlock() {
    final actions = runs.map((run) => run.totalActions).toList();
    final elapsed = runs.map((run) => run.elapsed.inMilliseconds).toList();
    final draws = runs.fold<int>(0, (total, run) => total + run.drawRounds);
    final normal = runs.fold<int>(0, (total, run) => total + run.normalRounds);
    final fifty = runs.fold<int>(0, (total, run) => total + run.fiftyRounds);
    final take = _kindTotal(ClassicHareegActionKind.takeDiscard);
    final draw = _kindTotal(ClassicHareegActionKind.drawStock);
    final meld =
        _kindTotal(ClassicHareegActionKind.playMeld) +
        _kindTotal(ClassicHareegActionKind.playMeldWithJoker);
    final cover = _kindTotal(ClassicHareegActionKind.placeCover);
    final replace = _kindTotal(ClassicHareegActionKind.replaceJoker);
    final fiftyClaims = _kindTotal(ClassicHareegActionKind.claimFifty);
    return 'TOTAL ${difficulty.name}: '
        'runs=${runs.length} '
        'avgActions=${_average(actions).toStringAsFixed(1)} '
        'avgElapsed=${_average(elapsed).toStringAsFixed(1)}ms '
        'rounds(normal/draw/fifty)=$normal/$draws/$fifty '
        'drawTake=$draw/$take '
        'meld=$meld cover=$cover replace=$replace fiftyClaims=$fiftyClaims\n';
  }

  int _kindTotal(ClassicHareegActionKind kind) {
    return runs.fold<int>(
      0,
      (total, run) => total + (run.actionCounts[kind] ?? 0),
    );
  }
}

double _average(List<int> values) {
  if (values.isEmpty) {
    return 0;
  }
  return values.fold<int>(0, (total, value) => total + value) / values.length;
}
