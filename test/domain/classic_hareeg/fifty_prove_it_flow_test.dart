import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/match_progression_rules.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

/// End-to-end coverage for the Fifty prove-it claim flow (issue #83):
/// untimed proofs, cover-routed claims, mid-proof retracts, the locked
/// return-pending exit, and the first-dealt-round scoring exception.
void main() {
  group('Fifty prove-it flow', () {
    test('the proof is untimed: the clock may pass the window mid-proof', () {
      var now = DateTime.utc(2026, 6, 7, 12);
      final discarded = _card(CardRank.nine, CardSuit.clubs, 401);
      final controller = _controller(
        eastHand: [
          _card(CardRank.seven, CardSuit.clubs, 401),
          _card(CardRank.eight, CardSuit.clubs, 401),
          _card(CardRank.two, CardSuit.hearts, 401),
        ],
        discardPile: [discarded],
        savedAt: now,
        now: () => now,
      );

      expect(controller.fiftySecondsRemaining, isNotNull);
      expect(
        controller.applyAction(ClassicHareegActionIds.claimFifty).isSuccess,
        isTrue,
      );
      // The window is consumed by the call; the ring disappears.
      expect(controller.fiftySecondsRemaining, isNull);

      // Way past the timer: the proof still completes.
      now = now.add(const Duration(minutes: 5));
      _driveProof(controller, PlayerSeat.east);

      expect(controller.roundOutcome, RoundOutcomeType.fiftyFinish);
    });

    test('a covers-only claim proves through the live cover path', () {
      // Owner-named scenario: east's own 8S opens the spot on north's
      // 5-6-7S run, the claimed 9S covers after it, 2H closes.
      final now = DateTime.utc(2026, 6, 7, 12);
      final claimed = _card(CardRank.nine, CardSuit.spades, 402);
      final northRun = [
        _card(CardRank.five, CardSuit.spades, 402),
        _card(CardRank.six, CardSuit.spades, 402),
        _card(CardRank.seven, CardSuit.spades, 402),
      ];
      final controller = _controller(
        eastHand: [
          _card(CardRank.eight, CardSuit.spades, 402),
          _card(CardRank.two, CardSuit.hearts, 402),
        ],
        discardPile: [claimed],
        tableMelds: {
          PlayerSeat.north: [PlacedMeld.fromCards(northRun)],
        },
        openingState: _opened(PlayerSeat.east),
        savedAt: now,
        now: () => now,
      );

      expect(
        controller.legalActionIdsFor(PlayerSeat.east),
        contains(ClassicHareegActionIds.claimFifty),
        reason: 'cover-aware planning must make the covers-only claim legal',
      );
      expect(
        controller.applyAction(ClassicHareegActionIds.claimFifty).isSuccess,
        isTrue,
      );
      _driveProof(controller, PlayerSeat.east);

      expect(controller.roundOutcome, RoundOutcomeType.fiftyFinish);
      expect(controller.roundResult?.winner, PlayerSeat.east);
      final grownRun = controller.tableMeldsFor(PlayerSeat.north).single;
      expect(grownRun.cards, hasLength(5));
      expect(
        grownRun.cards.map((card) => card.id),
        contains(claimed.id),
        reason: 'the claimed card landed as the second cover of the chain',
      );
      expect(controller.handFor(PlayerSeat.east), isEmpty);
    });

    test('retracts work mid-proof and restore the claimed card to pending',
        () {
      final now = DateTime.utc(2026, 6, 7, 12);
      final claimed = _card(CardRank.nine, CardSuit.clubs, 403);
      final controller = _controller(
        eastHand: [
          _card(CardRank.seven, CardSuit.clubs, 403),
          _card(CardRank.eight, CardSuit.clubs, 403),
          _card(CardRank.two, CardSuit.hearts, 403),
        ],
        discardPile: [claimed],
        savedAt: now,
        now: () => now,
      );
      expect(
        controller.applyAction(ClassicHareegActionIds.claimFifty).isSuccess,
        isTrue,
      );

      // Lay the 7-8-9C run (consumes the claimed card)...
      final meldStep = controller.cpuActionIdsFor(PlayerSeat.east).single;
      expect(controller.applyAction(meldStep).isSuccess, isTrue);
      expect(controller.pendingDiscard, isNull);
      final meldIndex =
          controller.tableMeldsFor(PlayerSeat.east).length - 1;

      // ...then take it back: the claimed card returns to pending and the
      // proof turn is still live.
      final retract = controller.applyAction(
        ClassicHareegActionIds.returnTablePlayActionId(
          owner: PlayerSeat.east,
          meldIndex: meldIndex,
        ),
      );
      expect(retract.isSuccess, isTrue, reason: retract.message);
      expect(controller.isFiftyProofTurn, isTrue);
      expect(controller.pendingDiscard?.id, claimed.id);
      expect(controller.cardCountFor(PlayerSeat.east), 4);

      // The proof still completes from the restored shape.
      _driveProof(controller, PlayerSeat.east);
      expect(controller.roundOutcome, RoundOutcomeType.fiftyFinish);
    });

    test('the claimed card cannot be returned during the proof', () {
      final now = DateTime.utc(2026, 6, 7, 12);
      final claimed = _card(CardRank.nine, CardSuit.clubs, 404);
      final controller = _controller(
        eastHand: [
          _card(CardRank.seven, CardSuit.clubs, 404),
          _card(CardRank.eight, CardSuit.clubs, 404),
          _card(CardRank.two, CardSuit.hearts, 404),
        ],
        discardPile: [claimed],
        savedAt: now,
        now: () => now,
      );
      expect(
        controller.applyAction(ClassicHareegActionIds.claimFifty).isSuccess,
        isTrue,
      );

      expect(
        controller.legalActionIdsFor(PlayerSeat.east),
        isNot(contains(ClassicHareegActionIds.returnPendingDiscard)),
      );
      final returned = controller.applyAction(
        ClassicHareegActionIds.returnPendingDiscard,
      );
      expect(returned.isSuccess, isFalse);
      expect(controller.isFiftyProofTurn, isTrue);
    });

    test('penalty tiers: returning the claimed card gives up the Fifty', () {
      // Strict tier: an unprovable claim (4 cards can't form a perfect hand)
      // is accepted into a proof turn, and returning the claimed card is the
      // discoverable give-up — +3, the claim is called off, the seat stays.
      final now = DateTime.utc(2026, 6, 7, 12);
      final claimed = _card(CardRank.nine, CardSuit.clubs, 410);
      final controller = _controller(
        strictness: TableStrictness.strict,
        eastHand: [
          _card(CardRank.seven, CardSuit.clubs, 410),
          _card(CardRank.eight, CardSuit.clubs, 410),
          _card(CardRank.two, CardSuit.hearts, 410),
          _card(CardRank.three, CardSuit.diamonds, 410),
        ],
        discardPile: [claimed],
        savedAt: now,
        now: () => now,
      );
      expect(
        controller.applyAction(ClassicHareegActionIds.claimFifty).isSuccess,
        isTrue,
      );
      expect(controller.isFiftyProofTurn, isTrue);
      expect(
        controller.legalActionIdsFor(PlayerSeat.east),
        contains(ClassicHareegActionIds.returnPendingDiscard),
      );

      final before = controller.scores[PlayerSeat.east] ?? 0;
      final result = controller.applyAction(
        ClassicHareegActionIds.returnPendingDiscard,
      );
      expect(result.isSuccess, isTrue, reason: result.message);
      expect(controller.scores[PlayerSeat.east], before + 3);
      // Strict keeps the player in the round; only the claim is called off.
      expect(controller.removedSeats.contains(PlayerSeat.east), isFalse);
      expect(controller.isFiftyProofTurn, isFalse);
      expect(controller.pendingDiscard, isNull);
    });

    test('a first-dealt-round proof scores the -1 exception', () {
      final now = DateTime.utc(2026, 6, 7, 12);
      final claimed = _card(CardRank.nine, CardSuit.clubs, 405);
      final controller = _controller(
        eastHand: [
          _card(CardRank.seven, CardSuit.clubs, 405),
          _card(CardRank.eight, CardSuit.clubs, 405),
          _card(CardRank.two, CardSuit.hearts, 405),
        ],
        discardPile: [claimed],
        roundNumber: 1,
        savedAt: now,
        now: () => now,
      );
      expect(
        controller.applyAction(ClassicHareegActionIds.claimFifty).isSuccess,
        isTrue,
      );
      _driveProof(controller, PlayerSeat.east);

      expect(controller.roundOutcome, RoundOutcomeType.fiftyFinish);
      expect(controller.roundResult?.firstRoundFiftyException, isTrue);
      expect(controller.scores[PlayerSeat.east], -1);
    });
  });

  group('relaxed taken-discard return', () {
    test('an opened seat may return the taken card after an unrelated cover',
        () {
      final now = DateTime.utc(2026, 6, 7, 12);
      final taken = _card(CardRank.two, CardSuit.hearts, 406);
      final coverCard = _card(CardRank.eight, CardSuit.spades, 406);
      final ownRun = [
        _card(CardRank.five, CardSuit.spades, 406),
        _card(CardRank.six, CardSuit.spades, 406),
        _card(CardRank.seven, CardSuit.spades, 406),
      ];
      final controller = _controller(
        eastHand: [
          coverCard,
          _card(CardRank.four, CardSuit.diamonds, 406),
          _card(CardRank.king, CardSuit.clubs, 406),
        ],
        tableMelds: {
          PlayerSeat.east: [PlacedMeld.fromCards(ownRun)],
        },
        openingState: _opened(PlayerSeat.east),
        turnPhase: TurnPhase.action,
        pendingDiscard: taken,
        savedAt: now,
        now: () => now,
      );
      // The snapshot helper injects the pending card into the hand too.

      // Cover with an unrelated card while the taken two sits unused.
      final cover = controller.applyAction(
        ClassicHareegActionIds.placeCoverActionId(
          targetSeat: PlayerSeat.east,
          meldIndex: 0,
          cardIds: [coverCard.id],
        ),
      );
      expect(cover.isSuccess, isTrue, reason: cover.message);
      expect(controller.pendingDiscard?.id, taken.id);

      // The opened seat may still return the unused taken card; the cover
      // stays committed on the table and the turn resumes at the draw.
      final returned = controller.applyAction(
        ClassicHareegActionIds.returnPendingDiscard,
      );
      expect(returned.isSuccess, isTrue, reason: returned.message);
      expect(controller.pendingDiscard, isNull);
      expect(controller.topDiscard?.id, taken.id);
      expect(controller.turnPhase, TurnPhase.draw);
      expect(
        controller.tableMeldsFor(PlayerSeat.east).single.cards,
        hasLength(4),
        reason: 'the committed cover survives the return',
      );

      // Drawing continues the SAME turn: the earlier cover stays
      // finish-eligible in the journal across the return -> draw.
      expect(
        controller.applyAction(ClassicHareegActionIds.drawStock).isSuccess,
        isTrue,
      );
      expect(
        controller.canReturnTablePlayFromMeld(PlayerSeat.east, 0),
        isTrue,
        reason: 'this turn\'s cover stays retractable after the draw',
      );
    });
  });
}

/// Replays the CPU proof surface until the claim resolves.
void _driveProof(ClassicHareegGameController controller, PlayerSeat seat) {
  var safety = 0;
  while (!controller.isRoundOver &&
      controller.isFiftyProofTurn &&
      safety < 24) {
    final actions = controller.cpuActionIdsFor(seat);
    expect(actions, isNotEmpty, reason: 'proof step must be offered');
    final result = controller.applyAction(actions.first);
    expect(result.isSuccess, isTrue, reason: result.message);
    safety += 1;
  }
}

ClassicHareegGameController _controller({
  required List<HareegCard> eastHand,
  List<HareegCard> discardPile = const [],
  Map<PlayerSeat, List<PlacedMeld>> tableMelds = const {},
  OpeningState? openingState,
  TurnPhase turnPhase = TurnPhase.draw,
  HareegCard? pendingDiscard,
  int roundNumber = 2,
  TableStrictness? strictness,
  required DateTime savedAt,
  required DateTime Function() now,
}) {
  final setup = strictness == null
      ? ClassicHareegSetup.defaults()
      : ClassicHareegSetup.defaults().copyWith(tableStrictness: strictness);
  final base = ClassicHareegRound.deal(setup: setup, seed: 5);
  return ClassicHareegGameController.fromSnapshot(
    ClassicHareegMatchSnapshot(
      setup: setup,
      hands: {
        PlayerSeat.south: base.hands[PlayerSeat.south]!,
        PlayerSeat.east: [?pendingDiscard, ...eastHand],
        PlayerSeat.north: base.hands[PlayerSeat.north]!,
        PlayerSeat.west: base.hands[PlayerSeat.west]!,
      },
      stock: base.stock,
      discardPile: discardPile,
      tableMelds: tableMelds,
      starter: base.starter,
      currentSeat: PlayerSeat.east,
      turnPhase: turnPhase,
      pendingDiscard: pendingDiscard,
      openingState: openingState,
      roundNumber: roundNumber,
      savedAt: savedAt,
      fiftyWindowOpenedAt: savedAt,
    ),
    now: now,
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
