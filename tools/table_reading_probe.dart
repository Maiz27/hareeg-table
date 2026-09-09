/// Runtime probe for per-tier consumption of the shared table-reading signals.
///
/// An alternate entrypoint, not part of the shipped app. It exists because the
/// property that matters here cannot be read off a firing count: the signals are
/// computed identically for every tier, so "the signal fired N times" says
/// nothing about whether a tier *used* it. What the ladder promises is a
/// difference in attention, and that only shows up as four separate numbers.
///
/// For every tier and every signal the probe reports:
///
/// - **available** — the signal had something to say at this position.
/// - **attended** — the tier consumes that signal class at all.
/// - **applied** — the tier attended AND the signal had something to say AND,
///   for Casual, the position fell inside its sampled attention.
/// - **choice-changed** — the tier's plan differs from the plan it makes on the
///   same position with that signal's evidence removed.
///
/// One reproducible corpus is collected from real seeded matches through the
/// live production adapter, and all four tiers are evaluated at each captured
/// position. Comparing unrelated match trajectories would not be evidence about
/// policy: two tiers playing different games differ for a hundred reasons.
///
/// ```
/// flutter run -d <emulator-id> --target=tools/table_reading_probe.dart --no-pub
/// ```
library;

import 'package:flutter/material.dart';
import 'package:hareeg_table/cpu/classic_hareeg/casual_cpu_move_planner.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_move_plan.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_observation.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_table_reading.dart';
import 'package:hareeg_table/cpu/classic_hareeg/expert_cpu_move_planner.dart';
import 'package:hareeg_table/cpu/classic_hareeg/priority_cpu_move_planner.dart';
import 'package:hareeg_table/cpu/classic_hareeg/skilled_cpu_move_planner.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_discard_history.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

/// Seeds the corpus is collected from. Fixed, so two runs of the probe walk
/// the same positions.
const List<int> probeSeeds = [
  11,
  29,
  47,
  83,
  101,
  137,
  211,
  307,
  419,
  523,
  641,
  757,
];

/// Upper bound on applied actions per seeded match, so a stuck table cannot
/// spin the probe forever.
const int maxActionsPerSeed = 600;

/// Upper bound on rounds per seeded match.
const int maxRoundsPerSeed = 12;

/// Corpus size. Collection stops here so the probe finishes in a couple of
/// minutes on a phone; the contract asks for at least two hundred positions.
const int maxPositions = 300;

/// Positions captured per seeded match, so the corpus spreads across every
/// seed instead of being consumed by the first one or two.
const int maxPositionsPerSeed = 26;

/// Capture every Nth decision. Walking a match to its later rounds is what
/// puts melds on the table and cards in the pile; sampling the whole walk
/// rather than its opening reaches those positions.
const int captureStride = 8;

void main() {
  runApp(const _ProbeApp());
}

/// One tier's consumption tally for one signal — the four contract counts.
class SignalTally {
  int available = 0;
  int attended = 0;
  int applied = 0;

  /// Positions where removing this signal's evidence changed the tier's plan
  /// **and** the removal was proven not to disturb anything else.
  int choiceChanged = 0;

  String row(String label, int positions) {
    return '$label  available ${_pad(available)}  attended ${_pad(attended)}'
        '  applied ${_pad(applied)}  choice-changed ${_pad(choiceChanged)}'
        '  of $positions';
  }

  static String _pad(int value) => value.toString().padLeft(4);
}

/// One counterfactual: what happens when a specific evidence class is removed.
///
/// A raw "the plan changed" count is worthless if the removal also moved inputs
/// something else reads. These four numbers keep that distinction visible
/// instead of folding a confounded position into the headline.
class Counterfactual {
  /// Positions where this evidence class was present, so the blinding applied.
  int blindable = 0;

  /// Blindable positions discarded because the blinding provably disturbed a
  /// legacy input as well, making any plan change unattributable.
  int confounded = 0;

  /// Blindable positions where the blinding was proven surgical.
  int countable = 0;

  /// Countable positions where the plan actually moved.
  int changed = 0;

  String row(String label) {
    return '$label  blindable ${SignalTally._pad(blindable)}'
        '  confounded ${SignalTally._pad(confounded)}'
        '  countable ${SignalTally._pad(countable)}'
        '  changed ${SignalTally._pad(changed)}';
  }
}

/// The probe result for one tier.
class TierReport {
  TierReport(this.difficulty);

  final CpuDifficulty difficulty;

  /// Card death and development liveness.
  final SignalTally material = SignalTally();

  /// Next-seat feed risk. `available` counts the signal, not one evidence
  /// class, so it must not be paired with a single counterfactual's numbers.
  final SignalTally feed = SignalTally();

  /// Removing the target's dead-draw evidence.
  final Counterfactual materialBlind = Counterfactual();

  /// Removing the target's visible-meld feed evidence (cover, joker).
  final Counterfactual feedMeldBlind = Counterfactual();

  /// Removing the target's recent-pickup feed evidence.
  final Counterfactual feedPickupBlind = Counterfactual();

  /// Positions where the value mirror disagreed with the live adapter before
  /// any blinding. Must be zero, or the choice-changed counts mean nothing.
  int mirrorMismatches = 0;

  /// Positions where the tier's attention gate was open, whether or not the
  /// signal had anything to say there.
  ///
  /// This is where Casual's sampling has statistical power. "Applied" is
  /// bounded by how often a hand actually holds a dead draw, which is rare;
  /// the gate itself is asked at every position.
  int attentionOpen = 0;
}

/// The full probe result.
class ProbeReport {
  ProbeReport({
    required this.positions,
    required this.tiers,
    required this.checks,
  });

  final int positions;
  final Map<CpuDifficulty, TierReport> tiers;
  final List<String> checks;

  bool get passed => checks.every((check) => !check.startsWith('FAIL'));

  /// The whole report as text, so a device run can be read out of `logcat`
  /// instead of squinted at in a screenshot.
  String get asText {
    final buffer = StringBuffer()
      ..writeln('positions: $positions from ${probeSeeds.length} seeds');
    for (final tier in tiers.values) {
      buffer
        ..writeln(
          '${tier.difficulty.name}  mirrorMismatches=${tier.mirrorMismatches}'
          '  attentionOpen=${tier.attentionOpen}',
        )
        ..writeln('  ${tier.material.row('material ', positions)}')
        ..writeln('  ${tier.feed.row('feed     ', positions)}')
        ..writeln('    ${tier.materialBlind.row('blind material')}')
        ..writeln('    ${tier.feedMeldBlind.row('blind feed:melds ')}')
        ..writeln('    ${tier.feedPickupBlind.row('blind feed:pickup')}');
    }
    for (final check in checks) {
      buffer.writeln(check);
    }
    return buffer.toString();
  }
}

/// How many units of work run between yields back to the event loop.
///
/// The probe is minutes of straight-line computation. Run in one blocking call
/// it starves the UI isolate, Android's input dispatcher gets no answer, and
/// the platform kills the app with an ANR before a single line is printed — so
/// the work is chunked and the isolate handed back regularly.
///
/// One unit, not a batch. Android gives an app five seconds to acknowledge an
/// input event, and a single position costs four full tier evaluations; on a
/// debug build on an emulator, even a handful of them between yields overruns
/// that budget and the platform files an ANR anyway.
const int _yieldEvery = 1;

/// Collects the corpus and evaluates every tier over it.
///
/// Asynchronous on purpose: see [_yieldEvery].
Future<ProbeReport> runProbe({void Function(String stage)? onProgress}) async {
  final positions = await _collectCorpus(onProgress);
  final tiers = {
    for (final difficulty in CpuDifficulty.values)
      difficulty: TierReport(difficulty),
  };

  for (var index = 0; index < positions.length; index += 1) {
    for (final difficulty in CpuDifficulty.values) {
      _evaluate(positions[index], difficulty, tiers[difficulty]!);
      await _yield();
    }
    if (index % _yieldEvery == 0) {
      onProgress?.call('evaluating ${index + 1}/${positions.length}');
      await _yield();
    }
  }

  return ProbeReport(
    positions: positions.length,
    tiers: tiers,
    checks: _checks(positions.length, tiers),
  );
}

/// Hands the isolate back so pending platform messages — input above all — get
/// serviced before the next chunk of work.
Future<void> _yield() => Future<void>.delayed(Duration.zero);

/// Whether this tier's plan was proven to move because of the new feed signal.
///
/// Deliberately NOT derived from [SignalTally.applied]. `applied` is policy
/// times availability — it says the tier is *allowed* to look and that there
/// was something to see. It would stay exactly as high if the production
/// comparator stopped reading the feed result altogether, so it cannot be
/// evidence of consumption. Only a surgical counterfactual that moved a real
/// planner decision can be.
bool provesFeedConsumption(TierReport tier) {
  return tier.feedMeldBlind.changed + tier.feedPickupBlind.changed > 0;
}

/// One captured decision position: the live table, frozen as the values the
/// CPU seat could see, plus the seat and legal actions it was offered.
class _Position {
  _Position({
    required this.seat,
    required this.legalActionIds,
    required this.snapshot,
    required this.livePlans,
  });

  final PlayerSeat seat;
  final List<String> legalActionIds;

  /// A value copy taken from the live adapter at capture time. The controller
  /// moves on; the position must not.
  final CpuObservationFacts snapshot;

  /// What each tier planned when asked through the **live** adapter, recorded
  /// at capture time while the controller still held this exact position.
  final Map<CpuDifficulty, String?> livePlans;
}

/// Walks the seeded matches with one fixed driver, capturing every CPU
/// decision position on the way.
///
/// The driver is deliberately tier-independent: if each tier played its own
/// game the corpus would differ per tier and no comparison between them would
/// mean anything.
Future<List<_Position>> _collectCorpus(
  void Function(String stage)? onProgress,
) async {
  final positions = <_Position>[];

  for (final seed in probeSeeds) {
    // A driven clock, advanced one second per applied action, so a Fifty
    // window nobody claims eventually expires instead of stalling the walk.
    var clock = DateTime.utc(2026, 1, 1);
    DateTime now() => clock;

    var controller = ClassicHareegGameController.fromRound(
      ClassicHareegRound.deal(
        setup: ClassicHareegSetup.defaults(),
        seed: seed,
      ),
      now: now,
    );

    if (positions.length >= maxPositions) {
      break;
    }

    var actions = 0;
    var captured = 0;
    var decisions = 0;
    for (var round = 0; round < maxRoundsPerSeed; round += 1) {
      // The walk continues after the per-seed capture cap is reached: driving
      // is cheap next to evaluating, and stopping early would confine the
      // corpus to opening play, where the pile is thin and nothing is dead.
      while (!controller.isRoundOver &&
          actions < maxActionsPerSeed &&
          positions.length < maxPositions) {
        final seat = controller.currentSeat;
        var legalActionIds = controller.cpuActionIdsFor(seat);
        if (legalActionIds.isEmpty) {
          break;
        }

        var live = LiveCpuObservation(
          controller: controller,
          seat: seat,
          legalActionIds: legalActionIds,
          difficulty: CpuDifficulty.skilled,
        );
        var actionId = const SkilledCpuMovePlanner().plan(live).actionId;
        if (actionId == null) {
          // The planner declined every legal action, which in practice means a
          // hopeless Fifty claim was the only option. Age the window out and
          // re-poll once, exactly as the scenario driver does.
          clock = clock.add(
            Duration(seconds: controller.setup.fiftyTimerSeconds + 30),
          );
          legalActionIds = controller.cpuActionIdsFor(seat);
          if (legalActionIds.isEmpty) {
            break;
          }
          live = LiveCpuObservation(
            controller: controller,
            seat: seat,
            legalActionIds: legalActionIds,
            difficulty: CpuDifficulty.skilled,
          );
          actionId = const SkilledCpuMovePlanner().plan(live).actionId;
          if (actionId == null) {
            break;
          }
        }

        // Every tier is asked through the live production adapter at this one
        // position, so the per-tier comparison is about policy rather than
        // about four tiers playing four different games.
        if (decisions % captureStride == 0 && captured < maxPositionsPerSeed) {
          positions.add(
            _Position(
              seat: seat,
              legalActionIds: legalActionIds,
              snapshot: _mirror(live, freezeHistory: true),
              livePlans: {
                for (final difficulty in CpuDifficulty.values)
                  difficulty: _plan(
                    LiveCpuObservation(
                      controller: controller,
                      seat: seat,
                      legalActionIds: legalActionIds,
                      difficulty: difficulty,
                    ),
                  ).actionId,
              },
            ),
          );
          captured += 1;
          if (positions.length % _yieldEvery == 0) {
            onProgress?.call(
              'collecting ${positions.length}/$maxPositions (seed $seed)',
            );
            await _yield();
          }
        }
        decisions += 1;

        final result = controller.applyAction(actionId);
        if (!result.isSuccess) {
          break;
        }
        actions += 1;
        clock = clock.add(const Duration(seconds: 1));
        // Every applied action, because the stride means many actions can pass
        // between two captures and each one is a full planner run.
        await _yield();
      }

      if (actions >= maxActionsPerSeed ||
          positions.length >= maxPositions ||
          !controller.isRoundOver) {
        break;
      }
      final next = controller.nextRoundSnapshot(savedAt: now());
      if (next == null) {
        break;
      }
      controller = ClassicHareegGameController.fromSnapshot(next, now: now);
    }
  }

  positions.add(_craftedFeedConsumptionPosition());
  return positions;
}

/// A deterministic position, hand-built and appended to the same corpus.
///
/// The natural walk cannot be relied on to contain a position where the new
/// feed signal is the thing that decides Expert's discard, and waiting for one
/// to turn up in three hundred deals is not evidence — it is luck. Two facts
/// about the game make it rare:
///
/// - The **cover** evidence class can never reach a discard decision at all.
///   The rules engine refuses to surface a discard for a card that would cover
///   a visible meld, so such a card is not a candidate in the first place. That
///   is why the meld counterfactual reports zero blindable positions.
/// - The **pickup** class is normally read by Expert's older
///   `OpponentThreatProfile` too, so removing it moves the legacy comparator as
///   well and the position is correctly excluded as confounded.
///
/// This position threads that needle. East has opened and is down to three
/// cards, so the legacy profile has stopped reading its pile pickups entirely,
/// while the new signal — which has no such filter — still sees the four East
/// took. Every legacy danger and avoid-feeding value is zero on both sides of
/// the blinding, Skilled plans identically across it, and the only thing that
/// moves is the new feed result.
///
/// It runs through the live production adapter exactly like every natural
/// position, and it is subject to the same guards: if the construction ever
/// stops isolating the signal, the probe will count it as confounded rather
/// than credit it.
_Position _craftedFeedConsumptionPosition() {
  HareegCard card(CardRank rank, CardSuit suit, {int deck = 0}) =>
      HareegCard.standard(rank: rank, suit: suit, deckIndex: deck);

  final controller = ClassicHareegGameController.fromSnapshot(
    ClassicHareegMatchSnapshot(
      setup: ClassicHareegSetup.defaults(),
      hands: {
        // Keep scores: 4♦ is 4, the lone cheapest card. J♥ and 9♥ form a
        // two-run worth 19, so the next-cheapest are the two loose tens.
        PlayerSeat.south: [
          card(CardRank.four, CardSuit.diamonds),
          card(CardRank.nine, CardSuit.hearts),
          card(CardRank.king, CardSuit.spades),
          card(CardRank.queen, CardSuit.clubs),
          card(CardRank.jack, CardSuit.hearts),
        ],
        // Three cards and opened: below the legacy profile's collecting floor,
        // so its pickup tells are dropped while the new signal keeps reading.
        PlayerSeat.east: [
          card(CardRank.two, CardSuit.clubs),
          card(CardRank.five, CardSuit.spades),
          card(CardRank.ten, CardSuit.clubs),
        ],
        PlayerSeat.north: [
          card(CardRank.six, CardSuit.hearts),
          card(CardRank.eight, CardSuit.spades),
          card(CardRank.two, CardSuit.diamonds, deck: 1),
        ],
        PlayerSeat.west: [
          card(CardRank.nine, CardSuit.clubs),
          card(CardRank.jack, CardSuit.spades),
          card(CardRank.three, CardSuit.clubs),
        ],
      },
      stock: [
        card(CardRank.ten, CardSuit.hearts),
        card(CardRank.six, CardSuit.spades),
      ],
      discardPile: [card(CardRank.two, CardSuit.hearts)],
      // A SET, not a run: a set yields no run-end threats, so East's meld
      // contributes nothing to the legacy danger score. Sevens rather than
      // fours, so the four of diamonds is not a cover and therefore stays a
      // legal discard.
      tableMelds: {
        PlayerSeat.east: [
          PlacedMeld.fromCards([
            card(CardRank.seven, CardSuit.hearts),
            card(CardRank.seven, CardSuit.clubs),
            card(CardRank.seven, CardSuit.spades),
          ]),
        ],
      },
      starter: PlayerSeat.south,
      currentSeat: PlayerSeat.south,
      turnPhase: TurnPhase.action,
      openingState: const OpeningState(
        baseRequirement: 51,
        currentRequirement: 51,
        openedSeats: {PlayerSeat.east},
      ),
      discardHistoryEvents: [
        DiscardEvent(
          seat: PlayerSeat.east,
          card: card(CardRank.four, CardSuit.hearts),
          kind: DiscardEventKind.pickup,
          sequence: 0,
        ),
      ],
      savedAt: DateTime.utc(2026, 1, 1),
    ),
  );

  final legalActionIds = controller.cpuActionIdsFor(PlayerSeat.south);
  final live = LiveCpuObservation(
    controller: controller,
    seat: PlayerSeat.south,
    legalActionIds: legalActionIds,
    difficulty: CpuDifficulty.skilled,
  );

  return _Position(
    seat: PlayerSeat.south,
    legalActionIds: legalActionIds,
    snapshot: _mirror(live, freezeHistory: true),
    livePlans: {
      for (final difficulty in CpuDifficulty.values)
        difficulty: _plan(
          LiveCpuObservation(
            controller: controller,
            seat: PlayerSeat.south,
            legalActionIds: legalActionIds,
            difficulty: difficulty,
          ),
        ).actionId,
    },
  );
}

void _evaluate(
  _Position position,
  CpuDifficulty difficulty,
  TierReport report,
) {
  final observation = _mirror(position.snapshot, difficulty: difficulty);
  final reading = CpuTableReading.forObservation(observation);
  final candidates = _discardCandidates(observation);
  final live = _plan(observation);

  // Fidelity: the value mirror must reproduce what the tier decided through
  // the live adapter at capture time. Without this, a "choice changed" number
  // would be measuring the mirror rather than the signal.
  if (position.livePlans[difficulty] != live.actionId) {
    report.mirrorMismatches += 1;
  }

  // --- material -----------------------------------------------------------
  final starved = reading.availableStarvedCardIds;
  final materialAvailable = candidates.any(
    (card) => starved.contains(card.id),
  );
  if (materialAvailable) {
    report.material.available += 1;
  }
  if (reading.policy.attendsMaterialSignal) {
    report.material.attended += 1;
  }
  if (reading.materialApplied) {
    report.attentionOpen += 1;
  }
  if (reading.policy.attendsMaterialSignal &&
      reading.materialApplied &&
      materialAvailable) {
    report.material.applied += 1;
  }

  if (materialAvailable) {
    final blind = _mirror(
      position.snapshot,
      difficulty: difficulty,
      blindMaterial: true,
    );
    // Load-bearing: emptying the pile is not the same as removing the signal.
    // Card death counts the hand and the visible melds too, so a starved group
    // can survive an empty pile. The blind only counts once it is shown to
    // have actually silenced the signal for every candidate.
    scoreCounterfactual(
      report.materialBlind,
      removed: !materialSignalPresent(blind, candidates),
      surgical: legacyProfileUnchanged(live: observation, blind: blind,
          candidates: candidates),
      changed: _plan(blind).actionId != live.actionId,
      into: report.material,
    );
  }

  // --- feed risk ----------------------------------------------------------
  // Availability is per SIGNAL for the contract counts, and per EVIDENCE CLASS
  // for the counterfactuals. Feeding the combined number into a single class's
  // row was how the meld row came to claim 22 available against 0 blindable.
  final feedAvailable = candidates.any(
    (card) => reading.availableFeedRiskFor(card).isRisky,
  );
  final meldFeedAvailable = candidates.any((card) {
    final evidence = reading.availableFeedRiskFor(card).evidence;
    return evidence.contains(FeedEvidenceKind.coverExtension) ||
        evidence.contains(FeedEvidenceKind.jokerReplacement);
  });
  final pickupFeedAvailable = candidates.any(
    (card) => reading
        .availableFeedRiskFor(card)
        .evidence
        .contains(FeedEvidenceKind.recentPickup),
  );

  if (feedAvailable) {
    report.feed.available += 1;
  }
  if (reading.policy.attendsFeedRisk) {
    report.feed.attended += 1;
  }
  if (reading.policy.attendsFeedRisk && feedAvailable) {
    report.feed.applied += 1;
  }

  // Neither blinding is surgical by construction: the legacy Expert profile
  // reads the target's melds AND the target's pickups, which are exactly the
  // two things there are to remove. So every blinded pair is checked, and a
  // position only contributes evidence once the legacy read is proven
  // unmoved. Anything else is counted as confounded and kept out of the
  // headline rather than quietly folded into it.
  if (meldFeedAvailable) {
    final blind = _mirror(
      position.snapshot,
      difficulty: difficulty,
      blindFeed: true,
    );
    scoreCounterfactual(
      report.feedMeldBlind,
      removed: !feedEvidencePresent(blind, candidates),
      surgical: legacyProfileUnchanged(live: observation, blind: blind,
              candidates: candidates) &&
          _sharedReadUnchanged(position, blindFeed: true),
      changed: _plan(blind).actionId != live.actionId,
      into: report.feed,
    );
  }

  if (pickupFeedAvailable) {
    final blind = _mirror(
      position.snapshot,
      difficulty: difficulty,
      blindTargetPickups: true,
    );
    scoreCounterfactual(
      report.feedPickupBlind,
      removed: !feedEvidencePresent(blind, candidates),
      surgical: legacyProfileUnchanged(live: observation, blind: blind,
              candidates: candidates) &&
          _sharedReadUnchanged(position, blindTargetPickups: true),
      changed: _plan(blind).actionId != live.actionId,
      into: report.feed,
    );
  }
}

/// Folds one counterfactual outcome into its tallies.
///
/// A plan change only reaches the headline [into] count when the blinding both
/// removed the signal and left everything else alone.
void scoreCounterfactual(
  Counterfactual counterfactual, {
  required bool removed,
  required bool surgical,
  required bool changed,
  required SignalTally into,
}) {
  counterfactual.blindable += 1;
  if (!removed || !surgical) {
    counterfactual.confounded += 1;
    return;
  }
  counterfactual.countable += 1;
  if (changed) {
    counterfactual.changed += 1;
    into.choiceChanged += 1;
  }
}

/// Whether any candidate still sits in a starved group under [blind].
///
/// Emptying the discard pile is NOT the same as removing the material signal:
/// card death counts the perspective hand and the visible melds too, so a group
/// can stay starved with an empty pile. Without this check a "nothing changed"
/// result could mean the signal was never removed in the first place.
bool materialSignalPresent(
  CpuObservation blind,
  List<HareegCard> candidates,
) {
  final reading = CpuTableReading.forObservation(blind);
  return candidates.any(
    (card) => reading.availableStarvedCardIds.contains(card.id),
  );
}

/// Whether any candidate still carries feed evidence under [blind].
bool feedEvidencePresent(CpuObservation blind, List<HareegCard> candidates) {
  final reading = CpuTableReading.forObservation(blind);
  return candidates.any((card) => reading.availableFeedRiskFor(card).isRisky);
}

/// Whether Expert's legacy posture reads [live] and [blind] identically.
///
/// `OpponentThreatProfile` scans every opponent's visible melds and pile
/// pickups — the same inputs the blindings touch — so without this check a
/// plan change could be the old comparator moving, not the new signal.
bool legacyProfileUnchanged({
  required CpuObservation live,
  required CpuObservation blind,
  required List<HareegCard> candidates,
}) {
  final before = OpponentThreatProfile.fromObservation(live);
  final after = OpponentThreatProfile.fromObservation(blind);
  for (final card in candidates) {
    if (before.dangerScore(card) != after.dangerScore(card)) {
      return false;
    }
    if (before.avoidFeedingScore(card) != after.avoidFeedingScore(card)) {
      return false;
    }
  }
  return true;
}

/// Whether the blinding left the reads a non-consuming tier depends on alone.
///
/// Skilled provably does not consume the new feed signal, but it does read the
/// pile history its own hot-rank tiebreak is built on. If Skilled's plan moves
/// under a blinding, that blinding disturbed shared state and cannot be used to
/// attribute anything to the new signal.
bool _sharedReadUnchanged(
  _Position position, {
  bool blindFeed = false,
  bool blindTargetPickups = false,
}) {
  final before = _plan(
    _mirror(position.snapshot, difficulty: CpuDifficulty.skilled),
  ).actionId;
  final after = _plan(
    _mirror(
      position.snapshot,
      difficulty: CpuDifficulty.skilled,
      blindFeed: blindFeed,
      blindTargetPickups: blindTargetPickups,
    ),
  ).actionId;
  return before == after;
}

/// The hand cards this position could legally discard.
List<HareegCard> _discardCandidates(CpuObservation observation) {
  final candidates = <HareegCard>[];
  for (final id in observation.legalActionIds) {
    final descriptor = ClassicHareegActionIds.describe(id);
    if (!descriptor.isSafeDiscard) {
      continue;
    }
    final cardId = descriptor.cardId;
    for (final card in observation.ownHand) {
      if (card.id == cardId) {
        candidates.add(card);
      }
    }
  }
  return candidates;
}

ClassicHareegCpuMovePlan _plan(CpuObservation observation) {
  return switch (observation.difficulty) {
    CpuDifficulty.beginner => const PriorityCpuMovePlanner().plan(observation),
    CpuDifficulty.casual => const CasualCpuMovePlanner().plan(observation),
    CpuDifficulty.skilled => const SkilledCpuMovePlanner().plan(observation),
    CpuDifficulty.expert => const ExpertCpuMovePlanner().plan(observation),
  };
}

/// A value copy of [source], optionally with one signal's evidence removed.
///
/// Blinding is surgical. The attention key is built from `discardCount`,
/// `tableMeldCount`, and the hand size, so a blinded mirror keeps all three
/// exactly as they were — otherwise Casual's gate would move and the
/// comparison would be measuring the gate rather than the signal.
CpuObservationFacts _mirror(
  CpuObservation source, {
  CpuDifficulty? difficulty,
  bool blindMaterial = false,
  bool blindFeed = false,
  bool blindTargetPickups = false,
  bool freezeHistory = false,
}) {
  final history = freezeHistory
      ? _frozenHistory(source.discardHistory)
      : source.discardHistory;
  final target = CpuTableReading.forObservation(source).feedTarget;

  final melds = <PlayerSeat, List<PlacedMeld>>{
    for (final entry in source.tableMelds.entries)
      entry.key: blindFeed && entry.key == target
          // Replaced one-for-one with maximal four-card sets: a natural set of
          // four cannot take another card and holds no joker, so it offers the
          // target no legal public benefit while keeping the meld count — and
          // therefore the attention key — unchanged.
          ? [
              for (var index = 0; index < entry.value.length; index += 1)
                _inertMeld(index),
            ]
          : entry.value,
  };

  return CpuObservationFacts(
    seat: source.seat,
    difficulty: difficulty ?? source.difficulty,
    legalActionIds: source.legalActionIds,
    turnPhase: source.turnPhase,
    pendingDiscard: source.pendingDiscard,
    ownHand: source.ownHand,
    handCounts: {
      for (final seat in PlayerSeat.values)
        if (seat != source.seat) seat: source.handCountFor(seat),
    },
    tableMelds: melds,
    stockCount: source.stockCount,
    topDiscard: source.topDiscard,
    discardCount: source.discardCount,
    discardPile: blindMaterial ? const [] : source.discardPile,
    roundNumber: source.roundNumber,
    deckCopyCount: source.deckCopyCount,
    openingState: source.openingState,
    scores: source.scoreView.currentScores,
    previousScores: source.scoreView.previousScores,
    eliminationThreshold: source.eliminationThreshold,
    activeSeats: source.activeSeats,
    currentSeat: source.currentSeat,
    opponents: source.opponents,
    fiftyClaimant: source.fiftyClaimant,
    fiftySecondsRemaining: source.fiftySecondsRemaining,
    ownIsFiftyProofTurn: source.ownIsFiftyProofTurn,
    discardHistory: blindTargetPickups
        ? _PickupBlindHistory(inner: history, hidden: target)
        : history,
    // A value view over the captured hand, NOT the live one. `LiveCpuObservation`
    // enumerates whatever the controller holds right now, so carrying its
    // partition view into a stored position would silently start answering
    // about a later turn.
    partitions: _ValuePartitionView(
      hand: source.ownHand,
      pendingDiscard: source.pendingDiscard,
    ),
    shortestSingleMeld: source.shortestSingleMeld(),
    finishingPartition: source.finishingPartition(),
  );
}

/// Partition enumeration over a fixed hand, mirroring [LiveMeldPartitionView]
/// with the controller replaced by the captured cards.
class _ValuePartitionView implements MeldPartitionView {
  const _ValuePartitionView({required this.hand, required this.pendingDiscard});

  final List<HareegCard> hand;
  final HareegCard? pendingDiscard;

  @override
  Iterable<MeldPartition> enumerate({
    bool includePendingDiscard = true,
    int maxPartitions = 32,
    int minMelds = 1,
    int maxMelds = 5,
    String? mustUseCardId,
    int? minTotalValue,
  }) {
    if (maxPartitions <= 0) {
      return const [];
    }
    final pending = pendingDiscard;
    final cards = !includePendingDiscard && pending != null
        ? [
            for (final card in hand)
              if (card.id != pending.id) card,
          ]
        : hand;

    return MeldPartitionEnumerator.partitionsOf(
      cards,
      minMelds: minMelds,
      maxMelds: maxMelds,
      mustUseCardId: mustUseCardId,
      minTotalValue: minTotalValue,
      safetyCap: maxPartitions,
    );
  }
}

/// A detached copy of [source]'s pile memory.
///
/// The controller's own `DiscardHistory` is mutable and keeps recording as the
/// walk continues, so carrying a reference into a stored position would make
/// that position answer with a later turn's memory — which is exactly what the
/// mirror-fidelity check caught.
DiscardHistoryView _frozenHistory(DiscardHistoryView source) {
  final frozen = DiscardHistory();
  if (source is DiscardHistory) {
    for (final event in source.events) {
      switch (event.kind) {
        case DiscardEventKind.discard:
          frozen.recordDiscard(event.seat, event.card);
        case DiscardEventKind.pickup:
          frozen.recordPickup(event.seat, event.card);
      }
    }
  }
  return frozen;
}

/// A history that hides one seat's pile pickups and delegates everything else.
class _PickupBlindHistory implements DiscardHistoryView {
  const _PickupBlindHistory({required this.inner, required this.hidden});

  final DiscardHistoryView inner;
  final PlayerSeat? hidden;

  @override
  Iterable<HareegCard> lastPickupsBy(PlayerSeat seat, int n) {
    return seat == hidden ? const [] : inner.lastPickupsBy(seat, n);
  }

  @override
  Iterable<HareegCard> lastDiscardsBy(PlayerSeat seat, int n) =>
      inner.lastDiscardsBy(seat, n);

  @override
  bool cardSeenAt(CardRank rank, CardSuit suit) =>
      inner.cardSeenAt(rank, suit);

  @override
  DiscardEvent? lastSeenAt(CardRank rank, CardSuit suit) =>
      inner.lastSeenAt(rank, suit);

  @override
  int discardsCount(CardRank rank) => inner.discardsCount(rank);

  @override
  int get jokersDiscarded => inner.jokersDiscarded;
}

PlacedMeld _inertMeld(int index) {
  final rank = CardRank.values[index % CardRank.values.length];
  return PlacedMeld(
    cards: [
      for (final suit in CardSuit.values)
        HareegCard.standard(rank: rank, suit: suit, deckIndex: index % 2),
    ],
    valueSnapshot: rank.value * 4,
  );
}

List<String> _checks(int positions, Map<CpuDifficulty, TierReport> tiers) {
  final checks = <String>[];

  void check(String label, bool ok, [String? detail]) {
    checks.add('${ok ? 'PASS' : 'FAIL'}  $label${detail == null ? '' : '  ($detail)'}');
  }

  check('corpus is non-trivial', positions >= 200, '$positions positions');

  for (final report in tiers.values) {
    check(
      '${report.difficulty.name}: the value mirror reproduces the live plan',
      report.mirrorMismatches == 0,
      '${report.mirrorMismatches} mismatches',
    );
  }

  // One corpus, so availability must be identical wherever memory depth does
  // not enter — the material signal reads no pickup history at all.
  final materialAvailable = {
    for (final report in tiers.values) report.material.available,
  };
  check(
    'the material signal is equally available to every tier',
    materialAvailable.length == 1,
    materialAvailable.join('/'),
  );

  final beginner = tiers[CpuDifficulty.beginner]!;
  final casual = tiers[CpuDifficulty.casual]!;
  final skilled = tiers[CpuDifficulty.skilled]!;
  final expert = tiers[CpuDifficulty.expert]!;

  check(
    'Beginner attends neither signal',
    beginner.material.attended == 0 && beginner.feed.attended == 0,
  );
  check(
    'Beginner never changes its choice',
    beginner.material.choiceChanged == 0 && beginner.feed.choiceChanged == 0,
  );

  // Casual's sampling is measured on the gate, not on "applied". How often a
  // hand happens to hold a dead draw is a property of the deal; how often
  // Casual is paying attention is the property this ladder promises, and it is
  // asked at every position.
  final casualRate = positions == 0 ? 0.0 : casual.attentionOpen / positions;
  check(
    'Casual attends a stable fraction of positions inside [0.34, 0.46]',
    casualRate >= 0.34 && casualRate <= 0.46,
    '${casual.attentionOpen}/$positions = ${casualRate.toStringAsFixed(3)}',
  );
  check(
    'Casual applies the material signal no more often than Skilled does',
    casual.material.applied <= skilled.material.applied,
    '${casual.material.applied} vs ${skilled.material.applied} '
    'of ${casual.material.available} available',
  );
  check(
    'Beginner and Skilled/Expert gates are constant, not sampled',
    beginner.attentionOpen == 0 &&
        skilled.attentionOpen == positions &&
        expert.attentionOpen == positions,
    'beginner ${beginner.attentionOpen}, skilled ${skilled.attentionOpen}, '
    'expert ${expert.attentionOpen}',
  );
  check(
    'Casual never applies feed risk',
    casual.feed.applied == 0 && casual.feed.choiceChanged == 0,
  );

  check(
    'Skilled applies the material signal everywhere it is available',
    skilled.material.applied == skilled.material.available,
    '${skilled.material.applied} of ${skilled.material.available}',
  );
  check(
    'Skilled never applies feed risk',
    skilled.feed.applied == 0 && skilled.feed.choiceChanged == 0,
  );

  check(
    'Expert applies the material signal everywhere it is available',
    expert.material.applied == expert.material.available,
    '${expert.material.applied} of ${expert.material.available}',
  );
  check(
    'Expert applies feed risk everywhere it is available',
    expert.feed.applied == expert.feed.available,
    '${expert.feed.applied} of ${expert.feed.available}',
  );
  check(
    'no tier below Expert moves on an attributable feed removal',
    beginner.feed.choiceChanged == 0 &&
        casual.feed.choiceChanged == 0 &&
        skilled.feed.choiceChanged == 0,
    'beginner ${beginner.feed.choiceChanged}, casual '
    '${casual.feed.choiceChanged}, skilled ${skilled.feed.choiceChanged}',
  );
  check(
    'Expert CONSUMES the feed signal: a surgical removal moves its real plan',
    provesFeedConsumption(expert),
    'melds ${expert.feedMeldBlind.changed}, pickups '
    '${expert.feedPickupBlind.changed}',
  );
  check(
    'no tier below Expert consumes it',
    !provesFeedConsumption(beginner) &&
        !provesFeedConsumption(casual) &&
        !provesFeedConsumption(skilled),
  );
  checks.add(
    'INFO  Expert feed counterfactual: melds '
    '${expert.feedMeldBlind.changed}/${expert.feedMeldBlind.countable} '
    'countable of ${expert.feedMeldBlind.blindable} blindable '
    '(${expert.feedMeldBlind.confounded} confounded); pickups '
    '${expert.feedPickupBlind.changed}/${expert.feedPickupBlind.countable} '
    'countable of ${expert.feedPickupBlind.blindable} blindable '
    '(${expert.feedPickupBlind.confounded} confounded)',
  );
  check(
    'every counted feed change was proven surgical',
    tiers.values.every(
      (tier) =>
          tier.feed.choiceChanged ==
          tier.feedMeldBlind.changed + tier.feedPickupBlind.changed,
    ),
  );
  check(
    'no confounded position ever reached a headline count',
    tiers.values.every(
      (tier) =>
          tier.feedMeldBlind.blindable ==
              tier.feedMeldBlind.countable + tier.feedMeldBlind.confounded &&
          tier.feedPickupBlind.blindable ==
              tier.feedPickupBlind.countable +
                  tier.feedPickupBlind.confounded &&
          tier.materialBlind.blindable ==
              tier.materialBlind.countable + tier.materialBlind.confounded,
    ),
  );

  return checks;
}

class _ProbeApp extends StatelessWidget {
  const _ProbeApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Table reading probe',
      theme: ThemeData.dark(useMaterial3: true),
      home: const _ProbeScreen(),
    );
  }
}

class _ProbeScreen extends StatefulWidget {
  const _ProbeScreen();

  @override
  State<_ProbeScreen> createState() => _ProbeScreenState();
}

class _ProbeScreenState extends State<_ProbeScreen> {
  ProbeReport? _report;
  bool _running = false;
  String? _stage;

  Future<void> _run() async {
    setState(() {
      _running = true;
      _stage = 'starting';
    });
    debugPrint('TABLE_READING_PROBE ---- run start ----');
    final report = await runProbe(
      onProgress: (stage) {
        if (mounted) {
          setState(() => _stage = stage);
        }
      },
    );
    for (final line in report.asText.trimRight().split('\n')) {
      debugPrint('TABLE_READING_PROBE $line');
    }
    debugPrint('TABLE_READING_PROBE ---- run end ----');
    if (!mounted) {
      return;
    }
    setState(() {
      _report = report;
      _running = false;
      _stage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('Table reading — per-tier consumption')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FilledButton(
                  onPressed: _running ? null : _run,
                  child: Text(_running ? 'Running…' : 'Run probe'),
                ),
                const SizedBox(width: 12),
                // A live stage line doubles as the proof that the isolate is
                // still answering while the walk runs.
                if (_stage != null) Expanded(child: _Mono(_stage!)),
              ],
            ),
            const SizedBox(height: 12),
            if (report != null)
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        report.passed ? 'ALL CHECKS PASS' : 'CHECKS FAILED',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: report.passed
                              ? Colors.greenAccent
                              : Colors.redAccent,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${report.positions} decision positions from '
                        '${probeSeeds.length} seeded matches',
                      ),
                      const SizedBox(height: 12),
                      for (final tier in report.tiers.values) ...[
                        Text(
                          tier.difficulty.name.toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        _Mono(tier.material.row('material ', report.positions)),
                        _Mono(tier.feed.row('feed     ', report.positions)),
                        _Mono(tier.materialBlind.row('blind material')),
                        _Mono(tier.feedMeldBlind.row('blind feed:melds ')),
                        _Mono(tier.feedPickupBlind.row('blind feed:pickup')),
                        const SizedBox(height: 8),
                      ],
                      const Divider(),
                      for (final check in report.checks) _Mono(check),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Mono extends StatelessWidget {
  const _Mono(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
    );
  }
}
