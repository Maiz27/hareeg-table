import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/analysis/partial_hand_groups.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';

HareegCard _c(CardRank rank, CardSuit suit, {int deckIndex = 0}) =>
    HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);

HareegCard _joker({int index = 0}) =>
    HareegCard.joker(deckIndex: 0, jokerIndex: index);

CardIdentity _id(CardRank rank, CardSuit suit) =>
    CardIdentity(rank: rank, suit: suit);

/// The pip-ceiling solo scorer the CPU layer supplies, reproduced locally: a
/// true duplicate (same rank AND suit) is worth nothing because its twin
/// already carries the rank's potential.
int _solo(HareegCard card, List<HareegCard> hand) {
  if (card.isJoker) {
    return 1 << 20;
  }
  final identity = card.effectiveIdentity;
  if (identity == null) {
    return 1 << 20;
  }
  for (final other in hand) {
    if (other.id == card.id) {
      continue;
    }
    final otherIdentity = other.effectiveIdentity;
    if (otherIdentity != null && otherIdentity == identity) {
      return 0;
    }
  }
  return identity.rank.value;
}

List<PartialHandGroup> _groups(List<HareegCard> cards) =>
    selectPartialGroups(cards: cards, hand: cards, soloValue: _solo);

/// The group [card] landed in.
PartialHandGroup _groupOf(List<PartialHandGroup> groups, HareegCard card) {
  return groups.firstWhere(
    (group) => group.cards.any((member) => member.id == card.id),
  );
}

void main() {
  group('the selector returns group structure, not a score map', () {
    test('a pair is reported as a pair with both members', () {
      final a = _c(CardRank.seven, CardSuit.hearts);
      final b = _c(CardRank.seven, CardSuit.spades);
      final groups = _groups([a, b]);

      expect(groups, hasLength(1));
      expect(groups.single.kind, PartialGroupKind.pair);
      expect(groups.single.isDeveloping, isTrue);
      expect(
        groups.single.cards.map((card) => card.id),
        containsAll([a.id, b.id]),
      );
      expect(groups.single.value, CardRank.seven.value * 2);
    });

    test('a two-run is reported as a run with the pip sum', () {
      final a = _c(CardRank.eight, CardSuit.clubs);
      final b = _c(CardRank.nine, CardSuit.clubs);
      final groups = _groups([a, b]);

      expect(groups.single.kind, PartialGroupKind.run);
      expect(
        groups.single.value,
        CardRank.eight.value + CardRank.nine.value,
      );
    });

    test('a lone card is a solo group carrying its pip ceiling', () {
      final king = _c(CardRank.king, CardSuit.diamonds);
      final groups = _groups([king]);

      expect(groups.single.kind, PartialGroupKind.solo);
      expect(groups.single.isDeveloping, isFalse);
      expect(groups.single.value, CardRank.king.value);
    });

    test('the groups are disjoint — every card lands in exactly one', () {
      final cards = [
        _c(CardRank.seven, CardSuit.hearts),
        _c(CardRank.seven, CardSuit.spades),
        _c(CardRank.eight, CardSuit.clubs),
        _c(CardRank.nine, CardSuit.clubs),
        _c(CardRank.king, CardSuit.diamonds),
      ];
      final groups = _groups(cards);
      final placed = [
        for (final group in groups)
          for (final card in group.cards) card.id,
      ];

      expect(placed, hasLength(cards.length));
      expect(placed.toSet(), cards.map((card) => card.id).toSet());
    });

    test('the member list is immutable', () {
      final groups = _groups([_c(CardRank.two, CardSuit.clubs)]);
      expect(
        () => groups.single.cards.add(_joker()),
        throwsUnsupportedError,
      );
    });
  });

  group('the pinned grouping behaviour', () {
    test('a tying group beats leaving both cards solo', () {
      // Two 5s: as a pair the group is worth 10, as two solos also 10. The
      // developing pair must win, or every low pair would dissolve.
      final a = _c(CardRank.five, CardSuit.hearts);
      final b = _c(CardRank.five, CardSuit.spades);
      final groups = _groups([a, b]);

      expect(groups.single.kind, PartialGroupKind.pair);
    });

    test('a true duplicate cannot pair or run with itself and stays solo', () {
      final first = _c(CardRank.six, CardSuit.clubs);
      final twin = _c(CardRank.six, CardSuit.clubs, deckIndex: 1);
      final groups = _groups([first, twin]);

      expect(groups, hasLength(2));
      for (final group in groups) {
        expect(group.kind, PartialGroupKind.solo);
      }
      expect(
        cardsCanMeldTogether(
          _id(CardRank.six, CardSuit.clubs),
          _id(CardRank.six, CardSuit.clubs),
        ),
        isFalse,
      );
    });

    test('a joker never anchors or joins a partial group', () {
      final joker = _joker();
      final seven = _c(CardRank.seven, CardSuit.hearts);
      final groups = _groups([joker, seven]);

      expect(groups, hasLength(2));
      expect(_groupOf(groups, joker).kind, PartialGroupKind.solo);
      expect(_groupOf(groups, seven).kind, PartialGroupKind.solo);
    });

    test('a joker holding a representation still does not join a group', () {
      // `effectiveIdentity` would make it look like a partner; the selector
      // checks `isJoker` as well so a wild card is never counted as material.
      final joker = HareegCard.joker(
        deckIndex: 0,
        jokerIndex: 0,
        representedIdentity: _id(CardRank.seven, CardSuit.spades),
      );
      final seven = _c(CardRank.seven, CardSuit.hearts);
      final groups = _groups([joker, seven]);

      expect(_groupOf(groups, joker).kind, PartialGroupKind.solo);
      expect(_groupOf(groups, seven).kind, PartialGroupKind.solo);
    });

    test('run distance is one or two, never three', () {
      expect(
        cardsCanMeldTogether(
          _id(CardRank.five, CardSuit.clubs),
          _id(CardRank.seven, CardSuit.clubs),
        ),
        isTrue,
      );
      expect(
        cardsCanMeldTogether(
          _id(CardRank.five, CardSuit.clubs),
          _id(CardRank.eight, CardSuit.clubs),
        ),
        isFalse,
      );
    });

    test('a set needs distinct suits and a run needs one suit', () {
      expect(
        cardsCanMeldTogether(
          _id(CardRank.five, CardSuit.clubs),
          _id(CardRank.five, CardSuit.hearts),
        ),
        isTrue,
      );
      expect(
        cardsCanMeldTogether(
          _id(CardRank.five, CardSuit.clubs),
          _id(CardRank.six, CardSuit.hearts),
        ),
        isFalse,
      );
    });
  });

  group('the tie rule is order-sensitive, and that is preserved', () {
    // Same-suit 5, 6, 8. Only one two-card group can be formed from a 5-6
    // adjacency or a 6-8 gap, and both total the same against the leftover
    // solo. The matcher resolves that tie by first-found, which is input
    // order — so the two permutations really do score differently. This is
    // the shipped behaviour, frozen here rather than "fixed".
    final five = _c(CardRank.five, CardSuit.clubs);
    final six = _c(CardRank.six, CardSuit.clubs);
    final eight = _c(CardRank.eight, CardSuit.clubs);

    test('ascending order [5, 6, 8] selects the 5-6 run', () {
      final groups = _groups([five, six, eight]);

      final fiveGroup = _groupOf(groups, five);
      expect(fiveGroup.kind, PartialGroupKind.run);
      expect(fiveGroup.value, 11);
      expect(_groupOf(groups, six).value, 11);
      expect(_groupOf(groups, eight).kind, PartialGroupKind.solo);
      expect(_groupOf(groups, eight).value, 8);
    });

    test('descending order [8, 6, 5] selects the 8-6 run instead', () {
      final groups = _groups([eight, six, five]);

      final eightGroup = _groupOf(groups, eight);
      expect(eightGroup.kind, PartialGroupKind.run);
      expect(eightGroup.value, 14);
      expect(_groupOf(groups, six).value, 14);
      expect(_groupOf(groups, five).kind, PartialGroupKind.solo);
      expect(_groupOf(groups, five).value, 5);
    });

    test('the two permutations disagree, deliberately', () {
      // Stated as its own assertion so nobody reads the pair above as two
      // independent examples that happen to differ. Input-order independence
      // is explicitly NOT a property of this selector: making it canonical
      // would move keep scores across the whole game and is out of scope.
      final ascending = _groups([five, six, eight]);
      final descending = _groups([eight, six, five]);

      expect(
        _groupOf(ascending, five).value,
        isNot(_groupOf(descending, five).value),
      );
      expect(
        _groupOf(ascending, eight).value,
        isNot(_groupOf(descending, eight).value),
      );
    });
  });

  group('there is one grouping algorithm', () {
    test('the selector is the only pair/two-run chooser in lib/', () {
      // C4 in prose: the pipeline derives its keep scores from these groups
      // rather than re-deriving them. A second implementation would show up
      // as another private best-partials search under lib/.
      final offenders = <String>[];
      final libRoot = Directory.current.path.replaceAll(r'\', '/');
      final files = Directory('$libRoot/lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));

      for (final file in files) {
        final path = file.path.replaceAll(r'\', '/');
        if (path.endsWith('analysis/partial_hand_groups.dart')) {
          continue;
        }
        final source = file.readAsStringSync();
        if (source.contains('_bestPartials') ||
            RegExp(r'\bbool\s+cardsCanMeldTogether\s*\(').hasMatch(source)) {
          offenders.add(path.substring(libRoot.length + 1));
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'The pair/two-run selection lives in partial_hand_groups.dart and '
            'nowhere else. A second copy would let keep scores and liveness '
            'drift apart:\n${offenders.join('\n')}',
      );
    });
  });
}
