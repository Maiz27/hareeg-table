import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/meld_partition.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/meld_partition_enumerator.dart';

void main() {
  group('MeldPartitionEnumerator', () {
    test('empty and short hands yield no partitions', () {
      expect(MeldPartitionEnumerator.partitionsOf(const []), isEmpty);
      expect(
        MeldPartitionEnumerator.partitionsOf([
          card(CardRank.seven, CardSuit.clubs),
          card(CardRank.seven, CardSuit.diamonds),
        ]),
        isEmpty,
      );
    });

    test('three same-rank cards yield one set with no remainder', () {
      final hand = [
        card(CardRank.seven, CardSuit.clubs),
        card(CardRank.seven, CardSuit.diamonds),
        card(CardRank.seven, CardSuit.hearts),
      ];

      final partitions = MeldPartitionEnumerator.partitionsOf(hand).toList();

      expect(partitions, hasLength(1));
      expect(partitions.single.meldCount, 1);
      expect(partitions.single.totalValue, 21);
      expect(partitions.single.cardsRemaining, isEmpty);
      expect(
        partitions.single.cardsUsed.map((card) => card.id),
        unorderedEquals([for (final card in hand) card.id]),
      );
      expect(partitions.single.jokerCount, 0);
    });

    test('seven-card sequence includes full and split partitions', () {
      final hand = [
        card(CardRank.five, CardSuit.clubs),
        card(CardRank.six, CardSuit.clubs),
        card(CardRank.seven, CardSuit.clubs),
        card(CardRank.eight, CardSuit.clubs),
        card(CardRank.nine, CardSuit.clubs),
        card(CardRank.ten, CardSuit.clubs),
        card(CardRank.jack, CardSuit.clubs),
      ];

      final partitions = MeldPartitionEnumerator.partitionsOf(
        hand,
        safetyCap: 128,
      ).toList();

      expect(
        _containsShape(partitions, const ['5C-6C-7C', '8C-9C-10C-JC']),
        isTrue,
      );
      expect(
        _containsShape(partitions, const ['5C-6C-7C-8C', '9C-10C-JC']),
        isTrue,
      );
      expect(
        _containsShape(partitions, const ['5C-6C-7C-8C-9C-10C-JC']),
        isTrue,
      );
    });

    test('mustUseCardId filters to partitions consuming that card', () {
      final sevenDiamonds = card(CardRank.seven, CardSuit.diamonds);
      final hand = [
        card(CardRank.seven, CardSuit.clubs),
        sevenDiamonds,
        card(CardRank.seven, CardSuit.hearts),
        card(CardRank.five, CardSuit.spades),
        card(CardRank.six, CardSuit.spades),
        card(CardRank.seven, CardSuit.spades),
      ];

      final partitions = MeldPartitionEnumerator.partitionsOf(
        hand,
        mustUseCardId: sevenDiamonds.id,
      ).toList();

      expect(partitions, isNotEmpty);
      expect(
        partitions.every((partition) => partition.usesCardId(sevenDiamonds.id)),
        isTrue,
      );
    });

    test('minTotalValue filters low-value partitions', () {
      final hand = [
        card(CardRank.three, CardSuit.clubs),
        card(CardRank.four, CardSuit.clubs),
        card(CardRank.five, CardSuit.clubs),
        card(CardRank.jack, CardSuit.hearts),
        card(CardRank.queen, CardSuit.hearts),
        card(CardRank.king, CardSuit.hearts),
      ];

      final partitions = MeldPartitionEnumerator.partitionsOf(
        hand,
        minTotalValue: 30,
      ).toList();

      expect(partitions, isNotEmpty);
      expect(
        partitions.every((partition) => partition.totalValue >= 30),
        isTrue,
      );
      expect(
        partitions.any((partition) => partition.totalValue == 12),
        isFalse,
      );
      expect(partitions.any((partition) => partition.totalValue == 30), isTrue);
    });

    test('joker expansion records represented identity in used cards', () {
      const joker = HareegCard.joker(deckIndex: 9, jokerIndex: 0);
      final hand = [
        card(CardRank.six, CardSuit.clubs),
        card(CardRank.seven, CardSuit.clubs),
        joker,
        card(CardRank.nine, CardSuit.clubs),
        card(CardRank.ten, CardSuit.clubs),
      ];

      final partitions = MeldPartitionEnumerator.partitionsOf(
        hand,
        safetyCap: 64,
      ).toList();

      final fullSequence = partitions.where((partition) {
        return partition.meldCount == 1 &&
            _meldLabels(partition).single == '6C-7C-J(8C)-9C-10C';
      });
      expect(fullSequence, isNotEmpty);
      expect(fullSequence.first.jokerAssignments, hasLength(1));
      expect(
        fullSequence.first.jokerAssignments.single.identity,
        const CardIdentity(rank: CardRank.eight, suit: CardSuit.clubs),
      );
      expect(
        fullSequence.first.cardsUsed.firstWhere((card) => card.isJoker).label,
        'J(8C)',
      );
    });

    test('safetyCap stops lazy enumeration by traversal node count', () {
      final hand = [
        for (final rank in CardRank.values) card(rank, CardSuit.clubs),
        const HareegCard.joker(deckIndex: 9, jokerIndex: 0),
        const HareegCard.joker(deckIndex: 9, jokerIndex: 1),
      ];

      // Baseline run with a generous cap captures the full enumeration.
      final full = MeldPartitionEnumerator.partitionsOf(
        hand,
        safetyCap: 4096,
      ).toList();
      expect(full, isNotEmpty);

      // A tight cap caps the search regardless of whether partitions are
      // emitted — the count is on traversal nodes, not emissions, so a
      // filter-heavy search can't blow past the cap by silently rejecting
      // partitions.
      final capped = MeldPartitionEnumerator.partitionsOf(
        hand,
        safetyCap: 8,
      ).toList();
      expect(capped.length, lessThan(full.length));

      // A safetyCap of 1 stops before any node can finish — no partitions
      // are emitted because the first traversal step trips the guard.
      final zero = MeldPartitionEnumerator.partitionsOf(
        hand,
        safetyCap: 1,
      ).toList();
      expect(zero, isEmpty);
    });

    test('enumeration is deterministic', () {
      final hand = [
        card(CardRank.five, CardSuit.clubs),
        card(CardRank.six, CardSuit.clubs),
        card(CardRank.seven, CardSuit.clubs),
        card(CardRank.eight, CardSuit.clubs),
        card(CardRank.nine, CardSuit.clubs),
        card(CardRank.ten, CardSuit.clubs),
        card(CardRank.jack, CardSuit.clubs),
      ];

      final first = MeldPartitionEnumerator.partitionsOf(
        hand,
        safetyCap: 128,
      ).map(_partitionSignature).toList();
      final second = MeldPartitionEnumerator.partitionsOf(
        hand,
        safetyCap: 128,
      ).map(_partitionSignature).toList();

      expect(second, first);
    });

    test('rankers can select the highest-value single meld', () {
      final hand = [
        card(CardRank.three, CardSuit.clubs),
        card(CardRank.four, CardSuit.clubs),
        card(CardRank.five, CardSuit.clubs),
        card(CardRank.jack, CardSuit.hearts),
        card(CardRank.queen, CardSuit.hearts),
        card(CardRank.king, CardSuit.hearts),
      ];

      final top = MeldPartitionEnumerator.topPartitions(
        hand,
        comparator: MeldPartitionRankers.byTotalValueDesc,
        take: 1,
        maxMelds: 1,
      );

      expect(top, hasLength(1));
      expect(top.single.totalValue, 30);
      expect(_meldLabels(top.single), const ['JH-QH-KH']);
    });
  });
}

HareegCard card(CardRank rank, CardSuit suit) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: 1);
}

bool _containsShape(List<MeldPartition> partitions, List<String> expected) {
  final expectedSorted = [...expected]..sort();
  return partitions.any((partition) {
    final actual = _meldLabels(partition);
    return _listEquals(actual, expectedSorted);
  });
}

List<String> _meldLabels(MeldPartition partition) {
  return partition.melds
      .map((meld) => meld.cards.map((card) => card.label).join('-'))
      .toList()
    ..sort();
}

String _partitionSignature(MeldPartition partition) {
  return [
    ..._meldLabels(partition),
    'remaining:${partition.cardsRemaining.map((card) => card.label).join(',')}',
    'value:${partition.totalValue}',
  ].join('|');
}

bool _listEquals(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
