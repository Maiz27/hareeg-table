import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_move_plan_pipeline.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';

HareegCard _c(CardRank rank, CardSuit suit, {int deckIndex = 0}) =>
    HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);

/// The lowest-scoring card id in [hand] — the one the discard logic would shed.
String _lowestKeep(List<HareegCard> hand) {
  final scores = handKeepScores(hand);
  String? pick;
  var pickScore = 1 << 30;
  for (final card in hand) {
    final score = scores[card.id] ?? 0;
    if (pick == null || score < pickScore) {
      pick = card.id;
      pickScore = score;
    }
  }
  return pick!;
}

void main() {
  // The keep score of a card is the value of the single meld / group it lands in
  // within the hand's best DISJOINT grouping. Higher = more worth keeping; the
  // discard logic sheds the lowest. Because the grouping is disjoint, no card can
  // double-count a partner another card already used — the root fix for the
  // committed-meld-inflation and redundant-duplicate families.
  group('discardKeepScore — disjoint best-grouping model', () {
    test('an isolated card scores its own pip value (its ceiling)', () {
      // A lone King keeps its potential (a future K set / K-Q-J run worth far
      // more than a low card), so it scores its pip value, not zero.
      final lone = _c(CardRank.king, CardSuit.diamonds);
      final hand = [
        lone,
        _c(CardRank.two, CardSuit.clubs),
        _c(CardRank.seven, CardSuit.hearts),
      ];
      expect(discardKeepScore(lone, hand), CardRank.king.value);
    });

    test('a lone high card outscores a loose low pair', () {
      // The coach must NOT shed a lone King to keep two low cards — the King's
      // ceiling is higher. King (10 solo) > a 2s pair (2 × 2 = 4).
      final king = _c(CardRank.king, CardSuit.diamonds);
      final twoA = _c(CardRank.two, CardSuit.hearts);
      final twoB = _c(CardRank.two, CardSuit.spades);
      final hand = [king, twoA, twoB, _c(CardRank.seven, CardSuit.clubs)];
      expect(
        discardKeepScore(king, hand),
        greaterThan(discardKeepScore(twoA, hand)),
      );
    });

    test('a developing high pair outscores a low complete set', () {
      // Round 2 vs screenshot resolution: a low 3-set (distinct suits, value 9)
      // scores BELOW a developing high pair of 8s (16), so a 3 is shed and the
      // 8s are kept — the model attributes each group's value to its members, so
      // the pair group (16) beats the set group (9) even though the set is
      // already complete.
      final threeA = _c(CardRank.three, CardSuit.hearts);
      final threeB = _c(CardRank.three, CardSuit.clubs);
      final threeC = _c(CardRank.three, CardSuit.spades);
      final eightA = _c(CardRank.eight, CardSuit.diamonds);
      final eightB = _c(CardRank.eight, CardSuit.hearts);
      final hand = [threeA, threeB, threeC, eightA, eightB];

      expect(discardKeepScore(threeA, hand), 9); // 3 × three-card set
      expect(discardKeepScore(eightA, hand), 16); // 8 × developing pair
      expect(_lowestKeep(hand), threeA.id);
    });

    test('a run anchor is protected above a loose low card', () {
      // The 4♣ anchors a complete 4-5-6-7 run; the loose 5♠ is the natural
      // discard. Every run member is attributed the run's value (22), so all
      // four outrank the loose card.
      final fourClubs = _c(CardRank.four, CardSuit.clubs);
      final fiveSpades = _c(CardRank.five, CardSuit.spades);
      final hand = [
        fourClubs,
        _c(CardRank.five, CardSuit.clubs),
        _c(CardRank.six, CardSuit.clubs),
        _c(CardRank.seven, CardSuit.clubs),
        fiveSpades,
      ];
      expect(
        discardKeepScore(fourClubs, hand),
        greaterThan(discardKeepScore(fiveSpades, hand)),
      );
      expect(_lowestKeep(hand), fiveSpades.id);
    });

    test('a redundant duplicate (rank AND suit twin) is shed first', () {
      // A 6-set is 6♥/6♣/6♦; a second 6♥ cannot join (a set needs distinct
      // suits). The set fills with ONE 6♥ (scored 18, like the other members);
      // the redundant copy falls to a 0 solo and is shed before even a lone low
      // card — the duplicate cannot borrow the set value its twin already holds.
      final sixHeartA = _c(CardRank.six, CardSuit.hearts);
      final sixHeartB = _c(CardRank.six, CardSuit.hearts, deckIndex: 1);
      final sixClubs = _c(CardRank.six, CardSuit.clubs);
      final sixDiamonds = _c(CardRank.six, CardSuit.diamonds);
      final loneTwo = _c(CardRank.two, CardSuit.spades);
      final hand = [sixHeartA, sixHeartB, sixClubs, sixDiamonds, loneTwo];
      final scores = handKeepScores(hand);

      // The distinct-suit members carry the set value (6 × 3 = 18).
      expect(scores[sixClubs.id], CardRank.six.value * 3);
      expect(scores[sixDiamonds.id], CardRank.six.value * 3);
      // Exactly one physical 6♥ joins the set; the other is the redundant 0.
      final heartScores = [scores[sixHeartA.id]!, scores[sixHeartB.id]!]..sort();
      expect(heartScores, [0, CardRank.six.value * 3]);
      // The redundant 6♥ ranks below even a lone low card with future upside,
      // so it is the shed card — never the lone 2 and never a distinct member.
      expect(_lowestKeep(hand), anyOf(sixHeartA.id, sixHeartB.id));
      expect(scores[loneTwo.id], greaterThan(0));
    });

    test(
      'a redundant duplicate is shed even when its twin completes a set, '
      'keeping the multi-suit member (Issue R)',
      () {
        // Opened seat holds two 9♣ alongside 9♥/9♦ (a complete 9-set) and a
        // 7♥/8♥ run start. The old per-card sum let the second 9♣ claim a run
        // slot its twin already used (phantom value), so the genuinely useful
        // 9♥ was shed. Disjoint grouping fills the 9-set with one 9♣, drops the
        // second 9♣ to 0, and keeps the 9♥ (a set member).
        final nineClubA = _c(CardRank.nine, CardSuit.clubs);
        final nineClubB = _c(CardRank.nine, CardSuit.clubs, deckIndex: 1);
        final nineHeart = _c(CardRank.nine, CardSuit.hearts);
        final nineDiamond = _c(CardRank.nine, CardSuit.diamonds);
        final sevenHeart = _c(CardRank.seven, CardSuit.hearts);
        final eightHeart = _c(CardRank.eight, CardSuit.hearts);
        final hand = [
          nineClubA,
          nineClubB,
          nineHeart,
          nineDiamond,
          sevenHeart,
          eightHeart,
        ];
        final scores = handKeepScores(hand);

        // The 9-set members each carry 27; one 9♣ is the redundant 0.
        expect(scores[nineHeart.id], CardRank.nine.value * 3);
        expect(scores[nineDiamond.id], CardRank.nine.value * 3);
        final clubScores = [scores[nineClubA.id]!, scores[nineClubB.id]!]
          ..sort();
        expect(clubScores, [0, CardRank.nine.value * 3]);
        // A 9♣ is the shed card; the useful 9♥ is never shed.
        expect(_lowestKeep(hand), anyOf(nineClubA.id, nineClubB.id));
        expect(scores[nineHeart.id], greaterThan(scores[sevenHeart.id]!));
      },
    );

    test(
      'a card committed to a meld does not inflate a loose neighbour (Issue P)',
      () {
        // Unopened: a 3-ace set + loose 2♥/3♥ + a lone K♣. The A♥ is committed
        // to the ace set, so it must NOT count as a heart-run partner for the
        // loose 2♥/3♥ (which would wrongly rank them above the King). Disjoint
        // grouping keeps the ace set intact; the low hearts only score their own
        // 2-run, below the King's solo ceiling — so a low heart is shed, not the
        // King.
        final aceHeart = _c(CardRank.ace, CardSuit.hearts);
        final aceClub = _c(CardRank.ace, CardSuit.clubs);
        final aceDiamond = _c(CardRank.ace, CardSuit.diamonds);
        final twoHeart = _c(CardRank.two, CardSuit.hearts);
        final threeHeart = _c(CardRank.three, CardSuit.hearts);
        final kingClub = _c(CardRank.king, CardSuit.clubs);
        final hand = [
          aceHeart,
          aceClub,
          aceDiamond,
          twoHeart,
          threeHeart,
          kingClub,
        ];
        final scores = handKeepScores(hand);

        // The low hearts (a 2-run worth 5) score below the King (solo 10).
        expect(scores[twoHeart.id], lessThan(scores[kingClub.id]!));
        expect(scores[threeHeart.id], lessThan(scores[kingClub.id]!));
        // The committed aces outrank the King; the King is never the shed card.
        expect(scores[kingClub.id], lessThan(scores[aceHeart.id]!));
        expect(_lowestKeep(hand), anyOf(twoHeart.id, threeHeart.id));
      },
    );

    test('a joker is never treated as deadwood', () {
      final joker = HareegCard.joker(deckIndex: 90, jokerIndex: 0);
      final hand = [joker, _c(CardRank.two, CardSuit.clubs)];
      expect(discardKeepScore(joker, hand), greaterThan(1000));
    });
  });
}
