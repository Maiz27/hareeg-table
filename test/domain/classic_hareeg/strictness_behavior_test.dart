import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/mistake_preset_rules.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/strictness_rule_profile.dart';

/// Behavior tests that drive [ClassicHareegGameController] through real-game
/// scenarios and assert each [TableStrictness] tier produces the behavior
/// promised by [StrictnessRuleProfile]. These assert on observable controller
/// state (scores, hands, removed seats, legal actions, apply-action messages),
/// not on the rule-profile getters themselves.
void main() {
  group('TableStrictness behavior matrix', () {
    group('Illegal cover discard', () {
      // South is already opened and owns a 5-6-7 sequence; the 8C in their
      // hand becomes an illegal cover discard outside the final-discard window
      // because the run can be covered with it. Each tier responds differently.
      for (final tier in TableStrictness.values) {
        test('${tier.name} tier handles a cover discard per profile', () {
          final fixture = _coverDiscardFixture(tier);
          final controller = ClassicHareegGameController.fromSnapshot(
            fixture.snapshot,
          );
          // Play the meld first so the cover candidate is recognised.
          final played = controller.applyAction(
            ClassicHareegActionIds.playMeldActionId(
              fixture.meldCards.map((card) => card.id),
            ),
          );
          expect(played.isSuccess, isTrue, reason: 'preconditions: meld plays');

          final scoreBefore = controller.scores[PlayerSeat.south] ?? 0;
          final handBefore = controller.cardCountFor(PlayerSeat.south);
          final discardActionId =
              '${ClassicHareegActionIds.discardBlockedCoverPrefix}'
              '${fixture.cover.id}';
          final legal = controller.legalActionIdsFor(PlayerSeat.south);

          if (tier.blocksIllegalMoves) {
            // Coaching / Standard: the discard is hard-blocked. The blocked
            // action id is not advertised and applying it returns failure with
            // no score change.
            expect(
              legal,
              isNot(contains(discardActionId)),
              reason: '${tier.name} should not advertise cover discard',
            );
            final result = controller.applyAction(discardActionId);
            expect(result.isSuccess, isFalse, reason: tier.name);
            expect(
              controller.scores[PlayerSeat.south] ?? 0,
              scoreBefore,
              reason: '${tier.name}: score must not change',
            );
            expect(
              controller.cardCountFor(PlayerSeat.south),
              handBefore,
              reason: '${tier.name}: hand must not change',
            );
            return;
          }

          // Strict / Table: discard goes through as a penalised mistake.
          expect(
            legal,
            contains(discardActionId),
            reason: '${tier.name} should advertise cover discard',
          );
          final result = controller.applyAction(discardActionId);
          expect(result.isSuccess, isTrue, reason: tier.name);
          expect(
            controller.scores[PlayerSeat.south],
            scoreBefore + tier.mistakePenaltyPoints,
            reason: '${tier.name} must add +${tier.mistakePenaltyPoints}',
          );

          if (tier.removesPlayerOnMistake) {
            // Table tier: South is removed from the round AND the cover card
            // still lands on the discard pile (the player is out but the card
            // has left their hand).
            final snapshot = controller.toSnapshot();
            expect(
              snapshot.removedSeats,
              contains(PlayerSeat.south),
              reason: '${tier.name} must remove offender from round',
            );
            expect(
              controller.topDiscard?.id,
              fixture.cover.id,
              reason:
                  '${tier.name}: cover card must land on discard pile, not stay orphaned in the removed seat\'s hand',
            );
            expect(
              controller.cardCountFor(PlayerSeat.south),
              handBefore - 1,
              reason:
                  '${tier.name}: removed seat\'s hand must shrink by one (the discarded card left)',
            );
          } else {
            // Strict: penalty applied to the score but the action is
            // reverted — the cover card stays in the seat's hand, the top
            // discard is unchanged, and the turn is still south's so they
            // can pick a legal discard.
            expect(
              result.wasReverted,
              isTrue,
              reason: '${tier.name} must mark the result as reverted',
            );
            expect(
              result.revertedCardId,
              fixture.cover.id,
              reason: '${tier.name} must surface the wrong card for the flash',
            );
            expect(
              controller.cardCountFor(PlayerSeat.south),
              handBefore,
              reason: '${tier.name}: card must stay in hand after revert',
            );
            expect(
              controller.topDiscard?.id,
              isNot(fixture.cover.id),
              reason: '${tier.name}: cover must NOT land on the discard pile',
            );
            expect(
              controller.currentSeat,
              PlayerSeat.south,
              reason: '${tier.name}: turn does not advance after revert',
            );
          }
        });
      }
    });

    group('Wrong Fifty claim', () {
      for (final tier in TableStrictness.values) {
        test('${tier.name} tier handles a wrong Fifty claim per profile', () {
          final now = DateTime.utc(2026, 5, 23, 12);
          final fixture = _wrongFiftyFixture(tier, now: now);
          final controller = ClassicHareegGameController.fromSnapshot(
            fixture.snapshot,
            now: () => now,
          );

          // Sanity: South is the claimant and we're in draw phase.
          expect(controller.fiftyClaimant, PlayerSeat.south);
          expect(controller.turnPhase, TurnPhase.draw);

          final scoreBefore = controller.scores[PlayerSeat.south] ?? 0;
          final legal = controller.legalActionIdsFor(PlayerSeat.south);
          final attempt = controller.applyAction(
            ClassicHareegActionIds.claimFifty,
          );

          if (tier.blocksIllegalMoves) {
            // Coaching / Standard: the claim action is not even advertised,
            // because there is no provable finish. Applying it fails.
            expect(
              legal,
              isNot(contains(ClassicHareegActionIds.claimFifty)),
              reason: '${tier.name} must not advertise wrong claim',
            );
            expect(attempt.isSuccess, isFalse, reason: tier.name);
            expect(
              controller.scores[PlayerSeat.south] ?? 0,
              scoreBefore,
              reason: '${tier.name}: score must not change',
            );
            return;
          }

          // Strict / Table: the claim goes through as a penalty.
          expect(
            legal,
            contains(ClassicHareegActionIds.claimFifty),
            reason: '${tier.name} must advertise wrong-claim affordance',
          );
          expect(attempt.isSuccess, isTrue, reason: tier.name);
          expect(
            controller.scores[PlayerSeat.south],
            scoreBefore + tier.mistakePenaltyPoints,
            reason: '${tier.name} must add +${tier.mistakePenaltyPoints}',
          );

          if (tier.removesPlayerOnMistake) {
            final snapshot = controller.toSnapshot();
            expect(
              snapshot.removedSeats,
              contains(PlayerSeat.south),
              reason: '${tier.name} must remove the wrong-claimant',
            );
          } else {
            // Strict: South still around — the round continues with them
            // still on the active list.
            final snapshot = controller.toSnapshot();
            expect(
              snapshot.removedSeats,
              isNot(contains(PlayerSeat.south)),
              reason: '${tier.name} keeps the wrong-claimant in the round',
            );
          }
        });
      }
    });

    group('Table-play retraction', () {
      for (final tier in TableStrictness.values) {
        test('${tier.name} tier honours allowsTablePlayRetraction', () {
          final meldCards = [
            _card(CardRank.seven, CardSuit.clubs, 70),
            _card(CardRank.eight, CardSuit.clubs, 70),
            _card(CardRank.nine, CardSuit.clubs, 70),
          ];
          final controller = ClassicHareegGameController.fromSnapshot(
            _snapshotWithSouthHand(
              southHand: [
                ...meldCards,
                _card(CardRank.two, CardSuit.spades, 70),
                _card(CardRank.three, CardSuit.diamonds, 70),
              ],
              currentSeat: PlayerSeat.south,
              turnPhase: TurnPhase.action,
              openingState: _opened(PlayerSeat.south),
              setup: ClassicHareegSetup.defaults().copyWith(
                tableStrictness: tier,
              ),
            ),
          );

          final played = controller.applyAction(
            ClassicHareegActionIds.playMeldActionId(
              meldCards.map((card) => card.id),
            ),
          );
          expect(played.isSuccess, isTrue);
          expect(controller.tableMeldsFor(PlayerSeat.south), hasLength(1));

          final retraction = controller.applyAction(
            ClassicHareegActionIds.returnTablePlayActionId(
              owner: PlayerSeat.south,
              meldIndex: 0,
            ),
          );

          if (tier.allowsTablePlayRetraction) {
            expect(
              retraction.isSuccess,
              isTrue,
              reason: '${tier.name} must allow retraction',
            );
            expect(controller.tableMeldsFor(PlayerSeat.south), isEmpty);
            expect(
              controller.handFor(PlayerSeat.south).map((card) => card.id),
              containsAll(meldCards.map((card) => card.id)),
            );
          } else {
            expect(
              retraction.isSuccess,
              isFalse,
              reason: '${tier.name} must lock plays',
            );
            expect(
              controller.tableMeldsFor(PlayerSeat.south),
              hasLength(1),
              reason: '${tier.name}: meld stays committed to table',
            );
          }
        });
      }
    });

    group('Fifty advertise without finish proof', () {
      // South sits as the Fifty claimant in draw phase, but the discarded
      // card + hand cannot prove a valid finish. The hand has a 9C up top to
      // distract: there's no partition that uses 9C from the top of the
      // discard pile to satisfy a perfect-hand finish.
      for (final tier in TableStrictness.values) {
        test('${tier.name} tier advertises Fifty per profile', () {
          final now = DateTime.utc(2026, 5, 23, 12);
          final fixture = _wrongFiftyFixture(tier, now: now);
          final controller = ClassicHareegGameController.fromSnapshot(
            fixture.snapshot,
            now: () => now,
          );

          final legal = controller.legalActionIdsFor(PlayerSeat.south);
          final control = controller.controlActionIdsFor(PlayerSeat.south);
          final shouldAdvertise = !tier.fiftyClaimNeedsFinishProofForAdvertise;

          expect(
            legal.contains(ClassicHareegActionIds.claimFifty),
            shouldAdvertise,
            reason:
                '${tier.name}: claim-fifty advertise=$shouldAdvertise '
                '(needsProof=${tier.fiftyClaimNeedsFinishProofForAdvertise})',
          );
          expect(
            control.contains(ClassicHareegActionIds.claimFifty),
            shouldAdvertise,
            reason: '${tier.name}: control surface mirrors legal surface',
          );
        });
      }
    });

    group('CPU mistakes allowed', () {
      for (final tier in TableStrictness.values) {
        test('${tier.name} matches profile cpuMistakesAllowed flag', () {
          expect(
            ClassicHareegMistakePresetRules.cpuMistakesAllowed(tier),
            tier.cpuMistakesAllowed,
            reason:
                'mistake-preset must agree with strictness profile for $tier',
          );
        });
      }
    });

    group('Penalty message propagation (regression for empty success)', () {
      // BUG that prompted this suite: a successful cover-discard mistake in
      // strict tier was returning ApplyActionResult.success('') instead of
      // propagating the "+3" copy from the mistake resolution. The feedback
      // chip then surfaced nothing and the user couldn't tell the penalty
      // had been applied. Lock the propagated message in.
      test('strict cover discard surfaces the +3 message on success', () {
        final fixture = _coverDiscardFixture(TableStrictness.strict);
        final controller = ClassicHareegGameController.fromSnapshot(
          fixture.snapshot,
        );
        final played = controller.applyAction(
          ClassicHareegActionIds.playMeldActionId(
            fixture.meldCards.map((card) => card.id),
          ),
        );
        expect(played.isSuccess, isTrue);

        final discard = controller.applyAction(
          '${ClassicHareegActionIds.discardBlockedCoverPrefix}'
          '${fixture.cover.id}',
        );

        expect(discard.isSuccess, isTrue);
        expect(
          discard.message,
          contains('+3'),
          reason:
              'BUG: strict cover discard must surface the "+3" penalty copy. '
              '_applyDiscard previously returned success("") on the mistake '
              'branch, losing the "+3" feedback message.',
        );
      });

      test('table cover discard surfaces the +17 message on success', () {
        // Parallel guard for table tier so the same regression cannot creep
        // in for the harder strictness path.
        final fixture = _coverDiscardFixture(TableStrictness.table);
        final controller = ClassicHareegGameController.fromSnapshot(
          fixture.snapshot,
        );
        final played = controller.applyAction(
          ClassicHareegActionIds.playMeldActionId(
            fixture.meldCards.map((card) => card.id),
          ),
        );
        expect(played.isSuccess, isTrue);

        final discard = controller.applyAction(
          '${ClassicHareegActionIds.discardBlockedCoverPrefix}'
          '${fixture.cover.id}',
        );

        expect(discard.isSuccess, isTrue);
        expect(
          discard.message,
          contains('+17'),
          reason:
              'BUG: table cover discard must surface the "+17" penalty copy.',
        );
      });
    });
  });
}

class _CoverDiscardFixture {
  const _CoverDiscardFixture({
    required this.snapshot,
    required this.meldCards,
    required this.cover,
  });

  final ClassicHareegMatchSnapshot snapshot;
  final List<HareegCard> meldCards;
  final HareegCard cover;
}

_CoverDiscardFixture _coverDiscardFixture(TableStrictness tier) {
  // 5C-6C-7C is the meld; 8C in-hand is a legal cover for the run. Putting
  // it in the discard pile in non-final position is the illegal-cover-discard
  // mistake we exercise per tier. South is already opened so the meld lands
  // immediately, and South still has cards to spare beyond the cover so the
  // discard is NOT the final discard (the final-discard branch would allow
  // any card).
  final meldCards = [
    _card(CardRank.five, CardSuit.clubs, 80),
    _card(CardRank.six, CardSuit.clubs, 80),
    _card(CardRank.seven, CardSuit.clubs, 80),
  ];
  final cover = _card(CardRank.eight, CardSuit.clubs, 80);
  final filler = [
    _card(CardRank.queen, CardSuit.diamonds, 80),
    _card(CardRank.king, CardSuit.spades, 80),
  ];
  final snapshot = _snapshotWithSouthHand(
    southHand: [...meldCards, cover, ...filler],
    currentSeat: PlayerSeat.south,
    turnPhase: TurnPhase.action,
    openingState: _opened(PlayerSeat.south),
    setup: ClassicHareegSetup.defaults().copyWith(tableStrictness: tier),
  );
  return _CoverDiscardFixture(
    snapshot: snapshot,
    meldCards: meldCards,
    cover: cover,
  );
}

class _WrongFiftyFixture {
  const _WrongFiftyFixture({required this.snapshot, required this.discard});

  final ClassicHareegMatchSnapshot snapshot;
  final HareegCard discard;
}

_WrongFiftyFixture _wrongFiftyFixture(
  TableStrictness tier, {
  required DateTime now,
}) {
  // South is in draw phase facing a top-of-discard 9C with a hand that
  // CANNOT prove a Fifty finish on 9C. Hand is chosen to be loud filler:
  // unrelated mid-cards with no meld + a 9C-completing run anywhere. The
  // restoration layer opens a Fifty window automatically because we're in
  // draw phase with a non-empty discard pile.
  final discard = _card(CardRank.nine, CardSuit.clubs, 90);
  final southHand = [
    _card(CardRank.two, CardSuit.hearts, 90),
    _card(CardRank.four, CardSuit.diamonds, 90),
    _card(CardRank.king, CardSuit.spades, 90),
    _card(CardRank.queen, CardSuit.hearts, 90),
    _card(CardRank.ace, CardSuit.diamonds, 90),
    _card(CardRank.three, CardSuit.spades, 90),
    _card(CardRank.jack, CardSuit.diamonds, 90),
    _card(CardRank.ten, CardSuit.spades, 90),
    _card(CardRank.five, CardSuit.hearts, 90),
    _card(CardRank.seven, CardSuit.diamonds, 90),
    _card(CardRank.eight, CardSuit.hearts, 90),
    _card(CardRank.six, CardSuit.spades, 90),
    _card(CardRank.three, CardSuit.diamonds, 90),
    _card(CardRank.king, CardSuit.hearts, 90),
  ];

  final base = ClassicHareegRound.deal(
    setup: ClassicHareegSetup.defaults(),
    seed: 5,
  );
  final snapshot = ClassicHareegMatchSnapshot(
    setup: ClassicHareegSetup.defaults().copyWith(tableStrictness: tier),
    hands: {
      PlayerSeat.south: southHand,
      PlayerSeat.east: base.hands[PlayerSeat.east]!,
      PlayerSeat.north: base.hands[PlayerSeat.north]!,
      PlayerSeat.west: base.hands[PlayerSeat.west]!,
    },
    stock: [_card(CardRank.two, CardSuit.diamonds, 91)],
    discardPile: [discard],
    starter: base.starter,
    currentSeat: PlayerSeat.south,
    turnPhase: TurnPhase.draw,
    savedAt: now,
    fiftyWindowOpenedAt: now,
  );

  return _WrongFiftyFixture(snapshot: snapshot, discard: discard);
}

ClassicHareegMatchSnapshot _snapshotWithSouthHand({
  required List<HareegCard> southHand,
  required PlayerSeat currentSeat,
  required TurnPhase turnPhase,
  OpeningState? openingState,
  ClassicHareegSetup? setup,
}) {
  final effectiveSetup = setup ?? ClassicHareegSetup.defaults();
  final base = ClassicHareegRound.deal(setup: effectiveSetup, seed: 5);
  return ClassicHareegMatchSnapshot(
    setup: effectiveSetup,
    hands: {
      ...base.hands,
      PlayerSeat.south: southHand,
    },
    stock: base.stock,
    discardPile: base.discardPile,
    starter: base.starter,
    currentSeat: currentSeat,
    turnPhase: turnPhase,
    openingState: openingState,
    savedAt: DateTime.utc(2026, 5, 23),
  );
}

OpeningState _opened(PlayerSeat seat) {
  return ClassicHareegOpeningRules.applyOpening(
    state: OpeningState.initial(51),
    seat: seat,
    melds: [const PlacedMeld(cards: [], valueSnapshot: 51)],
  );
}

HareegCard _card(CardRank rank, CardSuit suit, int deckIndex) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);
}
