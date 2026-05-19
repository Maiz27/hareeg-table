import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';

void main() {
  group('HareegCard', () {
    test('fromJson rejects fractional deck indexes', () {
      expect(
        () => HareegCard.fromJson({
          'deckIndex': 1.5,
          'identity': {'rank': CardRank.ace.name, 'suit': CardSuit.spades.name},
        }),
        throwsFormatException,
      );
    });

    test('fromJson accepts integer-valued numeric deck indexes', () {
      final card = HareegCard.fromJson({
        'deckIndex': 1.0,
        'identity': {'rank': CardRank.ace.name, 'suit': CardSuit.spades.name},
      });

      expect(card.id, 'deck-1-ace-spades');
    });
  });
}
