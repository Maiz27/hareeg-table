import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_observation.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_table_reading.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_discard_history.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

HareegCard _c(CardRank rank, CardSuit suit, {int deckIndex = 0}) =>
    HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);

/// One decision position in the fixed corpus, described by exactly the scalars
/// the attention key is built from.
class _CorpusPosition {
  const _CorpusPosition({
    required this.seat,
    required this.roundNumber,
    required this.turnPhase,
    required this.stockCount,
    required this.discardCount,
    required this.tableMeldCount,
    required this.handSize,
  });

  final PlayerSeat seat;
  final int roundNumber;
  final TurnPhase turnPhase;
  final int stockCount;
  final int discardCount;
  final int tableMeldCount;
  final int handSize;
}

/// The fixed corpus: 240 distinct decision positions.
///
/// Deliberately built from a deterministic nested walk rather than sampled, so
/// the same positions appear in this process, in the spawned process, and in
/// the device probe.
List<_CorpusPosition> _corpus() {
  final positions = <_CorpusPosition>[];
  for (final seat in PlayerSeat.values) {
    for (var round = 1; round <= 5; round += 1) {
      for (var step = 0; step < 12; step += 1) {
        final stock = 40 - step * 3;
        positions.add(
          _CorpusPosition(
            seat: seat,
            roundNumber: round,
            turnPhase: step.isEven ? TurnPhase.draw : TurnPhase.action,
            stockCount: stock,
            discardCount: 44 - stock,
            tableMeldCount: (round + step) % 5,
            handSize: 4 + (step % 8),
          ),
        );
      }
    }
  }
  return positions;
}

/// A filler hand of [size] distinct cards; the gate reads its length only.
List<HareegCard> _hand(int size) {
  final cards = <HareegCard>[];
  for (var index = 0; index < size; index += 1) {
    cards.add(
      _c(
        CardRank.values[index % CardRank.values.length],
        CardSuit.values[(index ~/ CardRank.values.length) % 4],
        deckIndex: index ~/ (CardRank.values.length * 4),
      ),
    );
  }
  return cards;
}

CpuObservationFacts _observationFor(
  _CorpusPosition position, {
  CpuDifficulty difficulty = CpuDifficulty.casual,
}) {
  return CpuObservationFacts(
    seat: position.seat,
    difficulty: difficulty,
    turnPhase: position.turnPhase,
    ownHand: _hand(position.handSize),
    stockCount: position.stockCount,
    discardCount: position.discardCount,
    roundNumber: position.roundNumber,
    tableMelds: {
      position.seat.nextAntiClockwise: [
        for (var index = 0; index < position.tableMeldCount; index += 1)
          PlacedMeld(
            cards: [
              _c(CardRank.four, CardSuit.hearts, deckIndex: index),
              _c(CardRank.four, CardSuit.clubs, deckIndex: index),
              _c(CardRank.four, CardSuit.spades, deckIndex: index),
            ],
            valueSnapshot: 12,
          ),
      ],
    },
  );
}

/// `seat|round|phase|stock|discard|melds|hand -> applied` for every position.
String _applicationPattern(TableReadingPolicy policy) {
  final buffer = StringBuffer();
  for (final position in _corpus()) {
    final observation = _observationFor(position);
    buffer
      ..write(TableReadingPolicy.positionKey(observation))
      ..write(' ')
      ..write(policy.appliesMaterialSignalAt(observation) ? '1' : '0')
      ..write('\n');
  }
  return buffer.toString();
}

void main() {
  group('the tier policy is one pure value per tier', () {
    test('each difficulty maps to its own constant', () {
      expect(
        TableReadingPolicy.forDifficulty(CpuDifficulty.beginner),
        same(TableReadingPolicy.beginner),
      );
      expect(
        TableReadingPolicy.forDifficulty(CpuDifficulty.casual),
        same(TableReadingPolicy.casual),
      );
      expect(
        TableReadingPolicy.forDifficulty(CpuDifficulty.skilled),
        same(TableReadingPolicy.skilled),
      );
      expect(
        TableReadingPolicy.forDifficulty(CpuDifficulty.expert),
        same(TableReadingPolicy.expert),
      );
    });

    test('the ladder reads exactly as the design says it does', () {
      const beginner = TableReadingPolicy.beginner;
      expect(beginner.attendsMaterialSignal, isFalse);
      expect(beginner.attendsFeedRisk, isFalse);
      expect(beginner.pickupMemoryDepth, 0);

      const casual = TableReadingPolicy.casual;
      expect(casual.attendsMaterialSignal, isTrue);
      expect(casual.attendsFeedRisk, isFalse);
      expect(casual.pickupMemoryDepth, 1);
      expect(casual.materialAttentionPercent, 40);
      expect(casual.samplesMaterialAttention, isTrue);

      const skilled = TableReadingPolicy.skilled;
      expect(skilled.attendsMaterialSignal, isTrue);
      expect(skilled.attendsFeedRisk, isFalse);
      expect(skilled.pickupMemoryDepth, 3);
      expect(skilled.samplesMaterialAttention, isFalse);

      const expert = TableReadingPolicy.expert;
      expect(expert.attendsMaterialSignal, isTrue);
      expect(expert.attendsFeedRisk, isTrue);
      expect(expert.pickupMemoryDepth, 6);
      expect(expert.samplesMaterialAttention, isFalse);
    });

    test('a reading takes its policy from the observation, not a caller', () {
      for (final difficulty in CpuDifficulty.values) {
        final reading = CpuTableReading.forObservation(
          CpuObservationFacts(difficulty: difficulty),
        );
        expect(reading.policy, same(TableReadingPolicy.forDifficulty(difficulty)));
      }
    });

    test('Beginner never applies either signal, at any position', () {
      for (final position in _corpus()) {
        final observation = _observationFor(
          position,
          difficulty: CpuDifficulty.beginner,
        );
        expect(
          TableReadingPolicy.beginner.appliesMaterialSignalAt(observation),
          isFalse,
        );
        expect(
          TableReadingPolicy.beginner.appliesFeedRiskAt(observation),
          isFalse,
        );
      }
    });

    test('Skilled and Expert always apply the material signal', () {
      for (final position in _corpus()) {
        for (final policy in [
          TableReadingPolicy.skilled,
          TableReadingPolicy.expert,
        ]) {
          expect(
            policy.appliesMaterialSignalAt(
              _observationFor(position, difficulty: policy.difficulty),
            ),
            isTrue,
          );
        }
      }
    });

    test('only Expert applies feed risk', () {
      final observation = _observationFor(_corpus().first);
      expect(TableReadingPolicy.beginner.appliesFeedRiskAt(observation), isFalse);
      expect(TableReadingPolicy.casual.appliesFeedRiskAt(observation), isFalse);
      expect(TableReadingPolicy.skilled.appliesFeedRiskAt(observation), isFalse);
      expect(TableReadingPolicy.expert.appliesFeedRiskAt(observation), isTrue);
    });
  });

  group('the attention key describes a position, never a candidate', () {
    test('the key is built from the seven observable scalars', () {
      final observation = _observationFor(
        const _CorpusPosition(
          seat: PlayerSeat.north,
          roundNumber: 3,
          turnPhase: TurnPhase.action,
          stockCount: 17,
          discardCount: 21,
          tableMeldCount: 2,
          handSize: 6,
        ),
      );
      expect(
        TableReadingPolicy.positionKey(observation),
        'north|r3|action|s17|d21|m2|h6',
      );
    });

    test('no candidate card id can reach the key', () {
      final observation = _observationFor(_corpus()[7]);
      final key = TableReadingPolicy.positionKey(observation);
      for (final card in observation.ownHand) {
        expect(key, isNot(contains(card.id)));
      }
    });

    test('every candidate in one decision shares the gate answer', () {
      // The decisive property: sampling positions, not cards. A gate that
      // hashed the candidate would split one comparison into attended and
      // ignored halves, which is not a mistake a human makes.
      final starved = _starvedCasualPosition();
      final reading = CpuTableReading.forObservation(starved.observation);

      expect(reading.availableStarvedCardIds, isNotEmpty);
      if (reading.materialApplied) {
        for (final id in reading.availableStarvedCardIds) {
          expect(reading.starvedCardIds, contains(id));
        }
      } else {
        expect(reading.starvedCardIds, isEmpty);
        for (final card in starved.observation.ownHand) {
          expect(reading.isStarved(card), isFalse);
        }
      }
    });

    test('the gate is invariant under permuted unordered inputs', () {
      // Scoped to the GATE. The grouping is order-sensitive on purpose (see
      // the partial-groups tests); this says nothing about it.
      for (final position in _corpus().take(40)) {
        final straight = _observationFor(position);
        final hand = straight.ownHand.reversed.toList();
        final melds = {
          for (final entry in straight.tableMelds.entries)
            entry.key: entry.value.reversed.toList(),
        };
        final permuted = CpuObservationFacts(
          seat: straight.seat,
          difficulty: straight.difficulty,
          turnPhase: straight.turnPhase,
          ownHand: hand,
          stockCount: straight.stockCount,
          discardCount: straight.discardCount,
          roundNumber: straight.roundNumber,
          tableMelds: melds,
        );

        expect(
          TableReadingPolicy.positionKey(permuted),
          TableReadingPolicy.positionKey(straight),
        );
        expect(
          TableReadingPolicy.casual.appliesMaterialSignalAt(permuted),
          TableReadingPolicy.casual.appliesMaterialSignalAt(straight),
        );
      }
    });
  });

  group('the sampling hash', () {
    test('is FNV-1a and not a platform hash', () {
      // Fixed by the algorithm: offset basis 2166136261, prime 16777619,
      // 32-bit wrap. These constants are what make the answer the same in
      // another process and under another SDK.
      expect(TableReadingPolicy.fnv1a32(''), 0x811c9dc5);
      expect(TableReadingPolicy.fnv1a32('a'), 0xe40c292c);
      expect(TableReadingPolicy.fnv1a32('foobar'), 0xbf9cf968);
      // And explicitly not the platform's own hash for the same input.
      expect(TableReadingPolicy.fnv1a32('foobar'), isNot('foobar'.hashCode));
    });

    test('no banned hash source appears in the policy file', () {
      final source = File(
        '${Directory.current.path}/lib/cpu/classic_hareeg/cpu_table_reading.dart',
      ).readAsStringSync();
      // `hashCode`, `Object.hash`, and `Object.hashAll` are not contracted to
      // be stable across processes or SDK versions, so a sampling rule built
      // on one would drift between runs.
      final code = source
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('///'))
          .join('\n');
      expect(code, isNot(contains('hashCode')));
      expect(code, isNot(contains('Object.hash')));
      expect(code, isNot(contains('Object.hashAll')));
    });

    test('no Random, DateTime.now, or mutable static enters the tier layer', () {
      // Every CPU-layer and analysis-layer file this sprint touched. A signal
      // that reads a clock or a global would make replays and tests drift for
      // reasons that have nothing to do with the game.
      for (final name in [
        'lib/cpu/classic_hareeg/cpu_table_reading.dart',
        'lib/cpu/classic_hareeg/cpu_move_plan_pipeline.dart',
        'lib/cpu/classic_hareeg/cpu_observation.dart',
        'lib/cpu/classic_hareeg/casual_cpu_move_planner.dart',
        'lib/cpu/classic_hareeg/skilled_cpu_move_planner.dart',
        'lib/cpu/classic_hareeg/expert_cpu_move_planner.dart',
        'lib/domain/classic_hareeg/analysis/table_reading_analysis.dart',
        'lib/domain/classic_hareeg/analysis/partial_hand_groups.dart',
      ]) {
        final source = File(
          '${Directory.current.path}/$name',
        ).readAsStringSync();
        expect(source, isNot(contains('Random(')), reason: name);
        expect(source, isNot(contains('DateTime.now')), reason: name);
        expect(
          _mutableStatics(source),
          isEmpty,
          reason: '$name must not declare a mutable static',
        );
      }
    });

    test('the mutable-static scan actually catches one', () {
      // The scan above passes trivially if it cannot detect anything. An
      // allow-list of type names would have let `static int counter = 0;`
      // through, so the detector is checked against real offenders here.
      expect(_mutableStatics('  static int counter = 0;'), [
        'static int counter = 0;',
      ]);
      expect(_mutableStatics('  static var seen = <String>{};'), [
        'static var seen = <String>{};',
      ]);
      expect(_mutableStatics('  static late Foo instance;'), [
        'static late Foo instance;',
      ]);
      // ...and against the shapes that are legitimately fine.
      expect(_mutableStatics('  static const int cap = 256;'), isEmpty);
      expect(_mutableStatics('  static final Foo x = Foo();'), isEmpty);
      expect(_mutableStatics('  static int fnv1a32(String value) {'), isEmpty);
      expect(_mutableStatics('  static int get count => 3;'), isEmpty);
    });
  });

  group('the sampled 40% is a real 40%', () {
    test('the applied fraction lands inside the stated band', () {
      // The band is written in the contract, not derived from whatever this
      // implementation happens to produce: inclusive [0.34, 0.46] over at
      // least 200 distinct positions.
      final positions = _corpus();
      expect(positions.length, greaterThanOrEqualTo(200));
      expect(
        positions
            .map(
              (position) =>
                  TableReadingPolicy.positionKey(_observationFor(position)),
            )
            .toSet()
            .length,
        positions.length,
        reason: 'the corpus positions must be distinct',
      );

      var applied = 0;
      for (final position in positions) {
        if (TableReadingPolicy.casual.appliesMaterialSignalAt(
          _observationFor(position),
        )) {
          applied += 1;
        }
      }
      final fraction = applied / positions.length;
      expect(fraction, greaterThanOrEqualTo(0.34));
      expect(fraction, lessThanOrEqualTo(0.46));
    });

    test('the pattern is byte-identical in a second Dart process', () {
      // A repeated in-process call proves nothing: the same `String.hashCode`
      // would also agree with itself. The claim is that a DIFFERENT process
      // reaches the same answer, so the corpus is re-evaluated in a freshly
      // spawned Dart VM and the two outputs compared byte for byte.
      final root = Directory.current.path;
      final scratch = Directory('$root/.dart_tool/table_reading_gate_probe')
        ..createSync(recursive: true);
      final script = File('${scratch.path}/gate_corpus.dart');
      script.writeAsStringSync(_gateCorpusScript);

      try {
        final dart = _dartExecutable();
        // The pattern is written to a file rather than stdout: `dart run`
        // prints its own build-hook chatter to stdout, and a byte-for-byte
        // claim must be about the pattern, not about tool noise.
        String runOnce(String name) {
          final output = File('${scratch.path}/$name.txt');
          final result = Process.runSync(dart, [
            'run',
            script.path,
            output.path,
          ], workingDirectory: root);
          expect(
            result.exitCode,
            0,
            reason: 'spawned process failed:\n${result.stdout}${result.stderr}',
          );
          return output.readAsStringSync();
        }

        final first = runOnce('first');
        final second = runOnce('second');

        expect(first, isNotEmpty);
        expect(first, second);
        // And the separate processes agree with this one, which is what makes
        // the two-process run evidence about THIS corpus rather than about
        // some other corpus the script happened to build.
        expect(first, _applicationPattern(TableReadingPolicy.casual));
      } finally {
        scratch.deleteSync(recursive: true);
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  group('pickup memory ages the target seat only', () {
    test('the remembered pickups are truncated to the tier depth', () {
      final history = DiscardHistory();
      for (final rank in [
        CardRank.two,
        CardRank.three,
        CardRank.four,
        CardRank.five,
        CardRank.six,
        CardRank.seven,
        CardRank.eight,
      ]) {
        history.recordPickup(PlayerSeat.east, _c(rank, CardSuit.clubs));
      }

      // Probed with hearts against clubs pickups, so only the same-rank
      // relationship can fire and the visible set is exactly the memory
      // window rather than the window plus its run neighbours.
      const oldestFirst = [
        CardRank.two,
        CardRank.three,
        CardRank.four,
        CardRank.five,
        CardRank.six,
        CardRank.seven,
        CardRank.eight,
      ];

      for (final difficulty in CpuDifficulty.values) {
        final observation = CpuObservationFacts(
          seat: PlayerSeat.south,
          difficulty: difficulty,
          discardHistory: history,
        );
        final reading = CpuTableReading.forObservation(observation);
        expect(reading.feedTarget, PlayerSeat.east);

        final depth = reading.policy.pickupMemoryDepth;
        final visible = <CardRank>{};
        for (final rank in oldestFirst) {
          final probe = _c(rank, CardSuit.hearts);
          if (reading.availableFeedRiskFor(probe).evidence.contains(
            FeedEvidenceKind.recentPickup,
          )) {
            visible.add(rank);
          }
        }

        expect(
          visible,
          oldestFirst.reversed.take(depth).toSet(),
          reason:
              '${difficulty.name} remembers $depth pickups, newest first',
        );
      }
    });

    test('there is no target and no signal when nobody else is active', () {
      final reading = CpuTableReading.forObservation(
        CpuObservationFacts(
          seat: PlayerSeat.south,
          difficulty: CpuDifficulty.expert,
          activeSeats: const [PlayerSeat.south],
        ),
      );
      expect(reading.feedTarget, isNull);
      expect(reading.isFeedRisk(_c(CardRank.nine, CardSuit.hearts)), isFalse);
      expect(
        reading.appliedFeedRiskFor(_c(CardRank.nine, CardSuit.hearts))?.target,
        isNull,
      );
    });

    test('a non-attending tier reports no applied feed risk at all', () {
      final history = DiscardHistory()
        ..recordPickup(PlayerSeat.east, _c(CardRank.nine, CardSuit.clubs));
      for (final difficulty in [
        CpuDifficulty.beginner,
        CpuDifficulty.casual,
        CpuDifficulty.skilled,
      ]) {
        final reading = CpuTableReading.forObservation(
          CpuObservationFacts(
            seat: PlayerSeat.south,
            difficulty: difficulty,
            discardHistory: history,
          ),
        );
        expect(
          reading.appliedFeedRiskFor(_c(CardRank.nine, CardSuit.hearts)),
          isNull,
          reason: difficulty.name,
        );
        expect(reading.isFeedRisk(_c(CardRank.nine, CardSuit.hearts)), isFalse);
      }
    });
  });
}

/// Static declarations in [source] that are neither `const` nor `final`.
///
/// Deliberately a denial rather than an allow-list: listing the type names
/// that are "fine" is what let a plain `static int counter = 0;` slip past.
/// Anything static is an offender unless it is immutable, a method, or a
/// getter — those three carry no per-process state.
List<String> _mutableStatics(String source) {
  final offenders = <String>[];
  for (final rawLine in source.split('\n')) {
    final line = rawLine.trim();
    if (!line.startsWith('static ')) {
      continue;
    }
    final rest = line.substring('static '.length).trim();
    if (rest.startsWith('const ') || rest.startsWith('final ')) {
      continue;
    }
    // A method or constructor: the declaration takes a parameter list before
    // its body or arrow.
    final bodyStart = rest.indexOf(RegExp(r'[;={]'));
    final head = bodyStart == -1 ? rest : rest.substring(0, bodyStart);
    if (head.contains('(')) {
      continue;
    }
    if (head.contains(' get ')) {
      continue;
    }
    offenders.add(line);
  }
  return offenders;
}

/// The `dart` binary to spawn the second process with.
///
/// The test host is `flutter_tester`, not `dart`, and the Flutter SDK is not
/// necessarily on PATH here, so the SDK's own Dart is located rather than
/// assumed.
String _dartExecutable() {
  final suffix = Platform.isWindows ? '.exe' : '';
  final candidates = <String>[];

  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null && flutterRoot.isNotEmpty) {
    candidates.add('$flutterRoot/bin/cache/dart-sdk/bin/dart$suffix');
  }

  // Walk up from the running engine binary looking for the bundled SDK.
  var directory = File(Platform.resolvedExecutable).parent;
  for (var depth = 0; depth < 8; depth += 1) {
    candidates.add('${directory.path}/dart$suffix');
    candidates.add('${directory.path}/bin/cache/dart-sdk/bin/dart$suffix');
    final parent = directory.parent;
    if (parent.path == directory.path) {
      break;
    }
    directory = parent;
  }

  for (final candidate in candidates) {
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }
  return 'dart$suffix';
}

/// A Casual position whose hand really does hold a starved group, so the gate
/// assertion is about attention rather than about an empty signal.
({CpuObservation observation, List<HareegCard> starved}) _starvedCasualPosition() {
  final pairA = _c(CardRank.seven, CardSuit.hearts);
  final pairB = _c(CardRank.seven, CardSuit.spades);
  final observation = CpuObservationFacts(
    seat: PlayerSeat.south,
    difficulty: CpuDifficulty.casual,
    ownHand: [pairA, pairB],
    discardPile: [
      _c(CardRank.seven, CardSuit.clubs),
      _c(CardRank.seven, CardSuit.clubs, deckIndex: 1),
      _c(CardRank.seven, CardSuit.diamonds),
      _c(CardRank.seven, CardSuit.diamonds, deckIndex: 1),
    ],
    discardCount: 4,
  );
  return (observation: observation, starved: [pairA, pairB]);
}

/// The corpus re-built inside a freshly spawned Dart VM.
///
/// It walks the same nested loop as [_corpus] and prints the same lines as
/// [_applicationPattern]. The test compares the spawned output against its own
/// in-process result, so a drift between the two builders fails the test rather
/// than quietly comparing two unrelated corpora.
const String _gateCorpusScript = r'''
import 'dart:io';

import 'package:hareeg_table/cpu/classic_hareeg/cpu_observation.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_table_reading.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

HareegCard _c(CardRank rank, CardSuit suit, {int deckIndex = 0}) =>
    HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);

List<HareegCard> _hand(int size) {
  final cards = <HareegCard>[];
  for (var index = 0; index < size; index += 1) {
    cards.add(
      _c(
        CardRank.values[index % CardRank.values.length],
        CardSuit.values[(index ~/ CardRank.values.length) % 4],
        deckIndex: index ~/ (CardRank.values.length * 4),
      ),
    );
  }
  return cards;
}

void main(List<String> args) {
  final buffer = StringBuffer();
  for (final seat in PlayerSeat.values) {
    for (var round = 1; round <= 5; round += 1) {
      for (var step = 0; step < 12; step += 1) {
        final stock = 40 - step * 3;
        final observation = CpuObservationFacts(
          seat: seat,
          difficulty: CpuDifficulty.casual,
          turnPhase: step.isEven ? TurnPhase.draw : TurnPhase.action,
          ownHand: _hand(4 + (step % 8)),
          stockCount: stock,
          discardCount: 44 - stock,
          roundNumber: round,
          tableMelds: {
            seat.nextAntiClockwise: [
              for (var index = 0; index < (round + step) % 5; index += 1)
                PlacedMeld(
                  cards: [
                    _c(CardRank.four, CardSuit.hearts, deckIndex: index),
                    _c(CardRank.four, CardSuit.clubs, deckIndex: index),
                    _c(CardRank.four, CardSuit.spades, deckIndex: index),
                  ],
                  valueSnapshot: 12,
                ),
            ],
          },
        );
        buffer
          ..write(TableReadingPolicy.positionKey(observation))
          ..write(' ')
          ..write(
            TableReadingPolicy.casual.appliesMaterialSignalAt(observation)
                ? '1'
                : '0',
          )
          ..write('\n');
      }
    }
  }
  File(args.single).writeAsStringSync(buffer.toString());
}
''';
