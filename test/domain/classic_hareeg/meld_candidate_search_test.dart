import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/meld_candidate_search.dart';

void main() {
  group('ClassicHareegMeldCandidateSearch', () {
    test('includes meld candidates requiring multiple unresolved jokers', () {
      final sevenClubs = card(CardRank.seven, CardSuit.clubs, deckIndex: 1);
      const firstJoker = HareegCard.joker(deckIndex: 90, jokerIndex: 0);
      const secondJoker = HareegCard.joker(deckIndex: 90, jokerIndex: 1);
      final discard = card(CardRank.two, CardSuit.diamonds, deckIndex: 1);

      final groups = ClassicHareegMeldCandidateSearch.candidateMeldGroups([
        sevenClubs,
        firstJoker,
        secondJoker,
        discard,
      ]);

      expect(
        groups.any((group) {
          final ids = group.map((card) => card.id).toSet();
          return ids.containsAll({
                sevenClubs.id,
                firstJoker.id,
                secondJoker.id,
              }) &&
              group.length == 3;
        }),
        isTrue,
      );
    });
  });
}

HareegCard card(CardRank rank, CardSuit suit, {required int deckIndex}) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);
}
