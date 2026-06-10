import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/classic_hareeg_rules.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/match_progression_rules.dart';

import '../classic_hareeg_match_driver.dart';

/// Universal invariants for a driven Classic Hareeg match.
///
/// These hold for *any* legal full game regardless of seed or configuration, so
/// they assert structural correctness without locking in specific values (that
/// is Family B/C). A single checker instance is fed every step and every round
/// of one match; the first round fixes the reference card multiset that later
/// rounds must preserve.
///
/// Cost discipline: per-step checks read only cheap live counts (no snapshot —
/// a per-action snapshot dominated runtime). Identity (multiset) conservation
/// runs once per round against the round-over snapshot. Count conservation runs
/// every step and catches gross drift the moment it happens; a duplicate-plus-
/// vanish that keeps the count constant is caught at the next round boundary.
///
/// What each invariant guards:
/// - Card conservation → cards silently created/destroyed.
/// - Termination (asserted separately via [checkMatch]) → non-ending games.
/// - Turn / removed-seat integrity → a removed seat still acting.
/// - Score invariants → the Fifty/finish scoring family (bonuses/penalties
///   wrong, scores moving mid-round, non-active seats scored).
class MatchInvariantChecker {
  /// Creates a checker for one match.
  ///
  /// Set [requireNoBackstopDraw] for mistake-free (converging) configurations:
  /// a round forced to a draw by the engine's stock-exhaustion liveness backstop
  /// then becomes a failure. A mistake-free CPU always takes a reachable finish,
  /// so the backstop should never fire for it — when it does, the finish detector
  /// advertised a finish the CPU could not actually play out (the detector/
  /// executor disagreement this checker guards). Leave it false for fallible
  /// (casual) CPUs, which can legitimately decline a finish and dead-draw.
  MatchInvariantChecker({
    required this.setup,
    required this.seed,
    this.requireNoBackstopDraw = false,
  });

  /// Setup the match was driven with.
  final ClassicHareegSetup setup;

  /// Seed the match was dealt with (for failure messages).
  final int seed;

  /// Whether a backstop-forced draw is a failure (converging configs only).
  final bool requireNoBackstopDraw;

  List<String>? _referenceCardIds;
  int? _baselineRound;
  Map<PlayerSeat, int> _roundBaselineScores = const {};

  int get _expectedCardCount => setup.deckCount * 52 + setup.jokerCount;

  int get _eliminationScore => ClassicHareegRules.defaults().eliminationScore;

  /// Asserts the cheap per-step invariants against post-action counts.
  void checkStep(MatchStep step) {
    // 1. Card-count conservation. A taken discard stays on the pile, so the
    // pending card is already inside `discardCount`; nothing is double-counted.
    if (step.totalCards != _expectedCardCount) {
      _fail(
        'card count drifted to ${step.totalCards}, expected $_expectedCardCount',
        step: step,
        extra: 'hands=${step.handCounts} stock=${step.stockCount} '
            'discard=${step.discardCount} meldCards=${step.meldCardCount}',
      );
    }

    // 2. No seat is ever removed in autonomous all-CPU play. Every seat is
    // driven through `cpuActionIdsFor`, which must exclude mistake-class
    // actions, and removal only happens as a Table-tier mistake consequence.
    // A non-empty removed set therefore means a mistake-class move slipped past
    // the CPU action filter — the seat sabotaged itself.
    if (step.removedSeats.isNotEmpty) {
      _fail(
        'a CPU seat was removed (a mistake-class move slipped past '
        'cpuActionIdsFor): ${step.removedSeats.map((s) => s.name).toList()}',
        step: step,
      );
    }

    // 3. Scores never move mid-round. Every seat is driven through
    // `cpuActionIdsFor`, which excludes mistake-class actions, so the only
    // legal score movement is at a round boundary. The round-ending action is
    // exempt: its result legitimately lands on that same step.
    if (_baselineRound != step.roundNumber) {
      _baselineRound = step.roundNumber;
      _roundBaselineScores = Map<PlayerSeat, int>.of(step.scores);
    } else if (!step.roundEndedAfter &&
        !_mapEquals(step.scores, _roundBaselineScores)) {
      _fail(
        'scores moved mid-round: ${step.scores} != baseline '
        '$_roundBaselineScores',
        step: step,
      );
    }
  }

  /// Asserts per-round identity conservation and every score invariant.
  void checkRound(DrivenRoundReport report) {
    // Liveness root cause (checked first, before the value invariants): a
    // mistake-free CPU always realizes a reachable finish, so the
    // stock-exhaustion backstop should never have to force this round to a draw.
    // When it does, the finish detector kept the round alive on a finish the CPU
    // could not actually play out — the detector/executor disagreement. The
    // assertion is that a converging config never *needs* the backstop, so the
    // sweep fails a stock-exhaustion livelock the recovering driver would
    // otherwise tolerate as a silent draw.
    if (requireNoBackstopDraw && report.endedByLivelockBackstop) {
      _fail(
        'round ${report.roundNumber} was forced to a draw by the '
        'stock-exhaustion liveness backstop — the finish detector advertised a '
        'finish no mistake-free CPU completed (detector/executor disagreement)',
      );
    }

    _checkIdentityConservation(report);

    final result = report.result;
    final progress = report.progress;
    if (result == null || progress == null) {
      _fail('round ${report.roundNumber} ended without a result/progress');
    }

    final before = report.scoresBefore;
    final after = report.scoresAfter; // == progress.scores (the overlay view)
    final delta = <PlayerSeat, int>{
      for (final seat in PlayerSeat.values)
        seat: (after[seat] ?? 0) - (before[seat] ?? 0),
    };
    final activeThisRound = result.remainingCardCounts.keys.toSet()
      ..addAll([if (result.winner != null) result.winner!]);

    switch (result.type) {
      case RoundOutcomeType.draw:
        if (!_mapEquals(after, before)) {
          _fail('draw round changed scores: before=$before after=$after');
        }
      case RoundOutcomeType.normalFinish:
        final winner = result.winner!;
        for (final seat in PlayerSeat.values) {
          final expected = !activeThisRound.contains(seat)
              ? 0
              : seat == winner
                  ? -1
                  : (result.remainingCardCounts[seat] ?? 0);
          if (delta[seat] != expected) {
            _fail(
              'normal-finish delta wrong for ${seat.name}: got ${delta[seat]}, '
              'expected $expected (winner=${winner.name})',
            );
          }
        }
      case RoundOutcomeType.fiftyFinish:
        final winner = result.winner!;
        final discarder = result.fiftyDiscarder;
        if (discarder == null) {
          _fail('fifty finish without a discarder');
        }
        for (final seat in PlayerSeat.values) {
          final expected = !activeThisRound.contains(seat)
              ? 0
              : seat == winner
                  ? (result.firstRoundFiftyException ? -1 : -3)
                  : seat == discarder
                      ? (result.remainingCardCounts[seat] ?? 0) + 3
                      : (result.remainingCardCounts[seat] ?? 0);
          if (delta[seat] != expected) {
            _fail(
              'fifty-finish delta wrong for ${seat.name}: got ${delta[seat]}, '
              'expected $expected (winner=${winner.name} '
              'discarder=${discarder.name} '
              'firstRound=${result.firstRoundFiftyException})',
            );
          }
        }
    }

    // Elimination threshold: active iff score is below the elimination score.
    for (final seat in activeThisRound) {
      final score = after[seat] ?? 0;
      final isActive = progress.activeSeats.contains(seat);
      if (score >= _eliminationScore && isActive) {
        _fail('seat ${seat.name} at $score >= $_eliminationScore still active');
      }
      if (score < _eliminationScore && !isActive) {
        _fail('seat ${seat.name} at $score < $_eliminationScore was dropped');
      }
    }
  }

  /// Asserts the terminal-state (liveness) invariants. Call only for
  /// configurations expected to converge — weak CPUs can draw indefinitely.
  void checkMatch(MatchRunReport report) {
    if (report.stopReason != MatchStopReason.matchWinner) {
      _fail(
        'match did not end naturally: ${report.stopReason.name} after '
        '${report.totalActions} actions / ${report.rounds.length} rounds',
      );
    }
    final winner = report.winner;
    if (winner == null) {
      _fail('match ended without a winner');
    }
    final lastProgress = report.rounds.last.progress;
    if (lastProgress == null || lastProgress.activeSeats.length != 1) {
      _fail('match end must leave exactly one active seat, got '
          '${lastProgress?.activeSeats}');
    }
    if (lastProgress.activeSeats.single != winner) {
      _fail('winner ${winner.name} != last active ${lastProgress.activeSeats}');
    }
    final winnerScore = lastProgress.scores[winner] ?? 0;
    if (winnerScore >= _eliminationScore) {
      _fail('winner ${winner.name} score $winnerScore >= $_eliminationScore');
    }
  }

  void _checkIdentityConservation(DrivenRoundReport report) {
    final ids = [for (final card in _allCards(report.snapshotAtRoundOver)) card.id];
    if (ids.length != _expectedCardCount) {
      _fail('round ${report.roundNumber}: card count ${ids.length} != '
          '$_expectedCardCount at round-over');
    }
    final unique = ids.toSet();
    if (unique.length != ids.length) {
      _fail('round ${report.roundNumber}: duplicate physical cards: '
          '${_duplicates(ids)}');
    }
    final sorted = [...ids]..sort();
    final reference = _referenceCardIds;
    if (reference == null) {
      _referenceCardIds = sorted;
    } else if (!_listEquals(sorted, reference)) {
      _fail('round ${report.roundNumber}: physical card multiset changed — '
          'added=${_difference(sorted, reference)} '
          'removed=${_difference(reference, sorted)}');
    }
  }

  List<HareegCard> _allCards(ClassicHareegMatchSnapshot s) {
    // `pendingDiscard` is excluded: the taken card stays on the discard pile
    // and is merely referenced as pending, so it is already counted there.
    return [
      for (final hand in s.hands.values) ...hand,
      ...s.stock,
      ...s.discardPile,
      for (final melds in s.tableMelds.values)
        for (final meld in melds) ...meld.cards,
    ];
  }

  Never _fail(String what, {MatchStep? step, String? extra}) {
    final where = step == null
        ? ''
        : ' at round ${step.roundNumber} action #${step.actionIndex} '
            '(seat=${step.seat.name} phase=${step.phase.name} '
            'action=${step.actionId})';
    throw StateError(
      'Match invariant violated [seed=$seed '
      'strictness=${setup.tableStrictness.name} '
      'difficulty=${setup.cpuDifficulty.name} '
      'decks=${setup.deckCount} jokers=${setup.jokerCount}]$where: $what'
      '${extra == null ? '' : '\n  $extra'}',
    );
  }

  static List<String> _duplicates(List<String> ids) {
    final seen = <String>{};
    final dupes = <String>{};
    for (final id in ids) {
      if (!seen.add(id)) {
        dupes.add(id);
      }
    }
    return dupes.toList();
  }

  static List<String> _difference(List<String> a, List<String> b) {
    final counts = <String, int>{};
    for (final id in b) {
      counts[id] = (counts[id] ?? 0) + 1;
    }
    final extra = <String>[];
    for (final id in a) {
      final remaining = counts[id] ?? 0;
      if (remaining > 0) {
        counts[id] = remaining - 1;
      } else {
        extra.add(id);
      }
    }
    return extra;
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i += 1) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  static bool _mapEquals(Map<PlayerSeat, int> a, Map<PlayerSeat, int> b) {
    final keys = {...a.keys, ...b.keys};
    for (final key in keys) {
      if ((a[key] ?? 0) != (b[key] ?? 0)) {
        return false;
      }
    }
    return true;
  }
}
