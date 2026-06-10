import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/match_progression_rules.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

/// Regression coverage for the stock-exhaustion finish-detection vs CPU-pickup
/// disagreement (issue #94).
///
/// The cover-aware finish detector routes a finish through covers of existing
/// table melds. But the *pickup* flow takes the discard as a pending card that
/// must be used immediately, and an unopened seat cannot place a cover until it
/// has opened. So a finish that routes the taken discard through a cover is
/// unplayable by pickup for an unopened seat: it takes the card, fails to place
/// it, returns it, and the round livelocks until the liveness backstop forces a
/// draw. Detection must therefore decline that pickup finish at the source.
void main() {
  group('pickup finish liveness (issue #94)', () {
    test(
      'an unopened seat is NOT kept alive by a cover-only pickup finish; the '
      'stock-exhausted round draws without the liveness backstop',
      () {
        // East (unopened) holds 4C 5C 6C (opens at the lowered requirement) plus
        // a 2D it would discard. The previous discard is 7H, which only EXTENDS
        // North's 8H 9H 10H as a cover — East cannot meld 7H. The detector sees a
        // cover-routed finish (meld 4C5C6C, cover 7H, discard 2D), but an
        // unopened seat can never place that cover, so the pickup is a dead end.
        final controller = _controller(
          eastHand: [
            _c(CardRank.four, CardSuit.clubs),
            _c(CardRank.five, CardSuit.clubs),
            _c(CardRank.six, CardSuit.clubs),
            _c(CardRank.two, CardSuit.diamonds),
          ],
          discardTop: _c(CardRank.seven, CardSuit.hearts),
          northMeld: [
            _c(CardRank.eight, CardSuit.hearts),
            _c(CardRank.nine, CardSuit.hearts),
            _c(CardRank.ten, CardSuit.hearts),
          ],
        );

        expect(
          controller.isRoundOver,
          isTrue,
          reason: 'the unrealizable pickup finish must not keep the round alive',
        );
        expect(controller.roundResult?.type, RoundOutcomeType.draw);
        expect(
          controller.roundEndedByLivelockBackstop,
          isFalse,
          reason: 'the round must draw through the normal planner path, not be '
              'rescued by the stock-exhaustion liveness backstop',
        );
      },
    );

    test(
      'an unopened seat IS kept alive by a realizable pickup finish, and the '
      'seat plays it out to a finish (no over-declining)',
      () {
        // Same shape, but the previous discard is 6C: East can MELD it
        // (4C 5C 6C), open, and finish on 2D. The detector must keep the round
        // alive and the pickup must actually complete.
        final controller = _controller(
          eastHand: [
            _c(CardRank.four, CardSuit.clubs),
            _c(CardRank.five, CardSuit.clubs),
            _c(CardRank.two, CardSuit.diamonds),
          ],
          discardTop: _c(CardRank.six, CardSuit.clubs),
          northMeld: [
            _c(CardRank.eight, CardSuit.hearts),
            _c(CardRank.nine, CardSuit.hearts),
            _c(CardRank.ten, CardSuit.hearts),
          ],
        );

        expect(
          controller.isRoundOver,
          isFalse,
          reason: 'a realizable pickup finish must keep the round alive',
        );

        // Drive East through the forced CPU surface; it must reach a finish, not
        // loop on take/return.
        var safety = 0;
        while (!controller.isRoundOver && safety < 16) {
          final ids = controller.cpuActionIdsFor(PlayerSeat.east);
          expect(ids, isNotEmpty, reason: 'East must always have a play');
          expect(
            ClassicHareegActionIds.describe(ids.first).kind,
            isNot(ClassicHareegActionKind.returnPendingDiscard),
            reason: 'a realizable finish must never fall back to returning the '
                'taken card',
          );
          final result = controller.applyAction(ids.first);
          expect(result.isSuccess, isTrue, reason: result.message);
          safety += 1;
        }

        expect(controller.isRoundOver, isTrue);
        expect(controller.roundResult?.winner, PlayerSeat.east);
        expect(controller.roundEndedByLivelockBackstop, isFalse);
      },
    );
  });
}

HareegCard _c(CardRank rank, CardSuit suit, [int deckIndex = 0]) =>
    HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);

/// Builds a stock-empty, draw-phase round with East unopened and on turn, an
/// expired Fifty window (so only the plain pickup path is in play), and a
/// lowered opening requirement so a single low club run opens.
ClassicHareegGameController _controller({
  required List<HareegCard> eastHand,
  required HareegCard discardTop,
  required List<HareegCard> northMeld,
}) {
  final setup = ClassicHareegSetup.defaults();
  final t0 = DateTime.utc(2026, 1, 1, 12);
  // Past the Fifty timer: the window is expired, so the seat can only take the
  // discard normally (the claim path, which would realize a cover finish via its
  // proof script, is unavailable).
  final now = t0.add(Duration(seconds: setup.fiftyTimerSeconds + 60));

  return ClassicHareegGameController.fromSnapshot(
    ClassicHareegMatchSnapshot(
      setup: setup,
      hands: {
        PlayerSeat.south: [_c(CardRank.three, CardSuit.spades)],
        PlayerSeat.east: eastHand,
        PlayerSeat.north: [_c(CardRank.king, CardSuit.spades)],
        PlayerSeat.west: [_c(CardRank.four, CardSuit.spades)],
      },
      stock: const [],
      discardPile: [discardTop],
      tableMelds: {
        PlayerSeat.north: [PlacedMeld.fromCards(northMeld)],
      },
      starter: PlayerSeat.south,
      currentSeat: PlayerSeat.east,
      turnPhase: TurnPhase.draw,
      openingState: OpeningState.initial(15),
      roundNumber: 2,
      savedAt: t0,
      fiftyWindowOpenedAt: t0,
    ),
    now: () => now,
  );
}
