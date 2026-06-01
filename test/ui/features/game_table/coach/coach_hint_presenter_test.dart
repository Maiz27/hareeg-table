import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/coaching/coaching_insight.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/features/game_table/coach/coach_hint.dart';

void main() {
  const strings = AppStrings.english;
  const king = CardIdentity(rank: CardRank.king, suit: CardSuit.spades);
  const seven = CardIdentity(rank: CardRank.seven, suit: CardSuit.hearts);

  CardIdentity? lookup(String id) => id == 'c1' ? king : null;

  CoachHint present(CoachingInsight insight, {CardIdentity? topDiscard}) {
    return CoachHintPresenter.present(
      insight: insight,
      strings: strings,
      identityForCardId: lookup,
      topDiscardIdentity: topDiscard,
    );
  }

  group('CoachHintPresenter', () {
    test('finish is an urgent hand pop-in that rings the played cards', () {
      final hint = present(
        const CoachingInsight(
          category: CoachingInsightCategory.finishAvailable,
          priority: 1000,
          highlightCardIds: ['a', 'b', 'c'],
        ),
      );
      expect(hint.intensity, CoachIntensity.popIn);
      expect(hint.accent, CoachAccent.finish);
      expect(hint.zone, CoachZone.hand);
      expect(hint.ringCardIds, ['a', 'b', 'c']);
      expect(hint.title, 'You can win');
    });

    test('Fifty uses the flame accent and rings nothing (flame cue owns it)', () {
      final hint = present(
        const CoachingInsight(
          category: CoachingInsightCategory.fiftyAvailable,
          priority: 900,
          highlightCardIds: ['top'],
        ),
        topDiscard: seven,
      );
      expect(hint.intensity, CoachIntensity.popIn);
      expect(hint.accent, CoachAccent.fifty);
      expect(hint.zone, CoachZone.discard);
      expect(hint.ringCardIds, isEmpty);
      expect(hint.body, contains('Seven of Hearts'));
      // The situation key still tracks the situation via the insight highlight.
      expect(hint.situationKey, contains('top'));
    });

    test('cover advice is framed as a positive keep hint', () {
      final hint = present(
        const CoachingInsight(
          category: CoachingInsightCategory.coverKeep,
          priority: 500,
          coverCardId: 'c1',
          highlightCardIds: ['c1'],
        ),
      );
      expect(hint.accent, CoachAccent.coach);
      expect(hint.intensity, CoachIntensity.quiet);
      expect(hint.title, 'Worth keeping');
      expect(hint.body, contains('Keep the King of Spades'));
      expect(hint.body, isNot(contains('discard')));
    });

    test('joker advice is an unambiguous swap action, not a keep hint', () {
      // Regression: the copy used to say "Keep the X. Play it to swap…", which
      // contradicts itself. It must read as a single clear action and rings the
      // hand card plus the table meld holding the joker.
      final hint = present(
        const CoachingInsight(
          category: CoachingInsightCategory.jokerAdvice,
          priority: 400,
          jokerCardId: 'c1',
          highlightCardIds: ['c1', 'm1', 'm2', 'm3'],
        ),
      );
      expect(hint.body, contains('swap'));
      expect(hint.body, contains('joker'));
      expect(hint.body, isNot(contains('Keep')));
      expect(hint.ringCardIds, ['c1', 'm1', 'm2', 'm3']);
    });

    test('defensive discard is the only avoid-framed hint', () {
      final hint = present(
        const CoachingInsight(
          category: CoachingInsightCategory.defensiveDiscard,
          priority: 300,
          discardCardId: 'c1',
          hotOpponent: PlayerSeat.east,
          hotSuit: CardSuit.hearts,
          highlightCardIds: ['c1'],
        ),
      );
      expect(hint.title, 'Hold this back');
      expect(hint.body, contains('Avoid discarding the King of Spades'));
      expect(hint.body, contains('Hearts'));
    });

    test('open-now carries the meld groups for grouped ring colours', () {
      final hint = present(
        const CoachingInsight(
          category: CoachingInsightCategory.openNow,
          priority: 800,
          highlightCardIds: ['a', 'b', 'c', 'd', 'e', 'f'],
          meldGroups: [
            ['a', 'b', 'c'],
            ['d', 'e', 'f'],
          ],
        ),
      );
      expect(hint.ringGroups, [
        ['a', 'b', 'c'],
        ['d', 'e', 'f'],
      ]);
    });

    test('play-meld softens to play-or-hold and folds in an available cover', () {
      final hint = present(
        const CoachingInsight(
          category: CoachingInsightCategory.playMeld,
          priority: 700,
          coverCardId: 'c1',
          highlightCardIds: ['a', 'b', 'c', 'c1', 'm1', 'm2', 'm3'],
          meldGroups: [
            ['a', 'b', 'c'],
            ['c1', 'm1', 'm2', 'm3'],
          ],
        ),
      );
      // Nuance: not a command — presents holding for a bigger meld / a Fifty.
      expect(hint.body, contains('hold'));
      expect(hint.body, contains('Fifty'));
      // Combined: also names the lay-off cover, and rings it as a second group.
      expect(hint.body, contains('also lay the King of Spades'));
      expect(hint.ringGroups.length, 2);
    });

    test('play-meld without a cover stays a plain play-or-hold hint', () {
      final hint = present(
        const CoachingInsight(
          category: CoachingInsightCategory.playMeld,
          priority: 700,
          highlightCardIds: ['a', 'b', 'c'],
          meldGroups: [
            ['a', 'b', 'c'],
          ],
        ),
      );
      expect(hint.body, contains('hold'));
      expect(hint.body, isNot(contains('also lay')));
    });

    test('play-cover tells the player to lay the card onto the meld', () {
      final hint = present(
        const CoachingInsight(
          category: CoachingInsightCategory.playCover,
          priority: 550,
          coverCardId: 'c1',
          coverMeldOwner: PlayerSeat.north,
          coverMeldIndex: 0,
          highlightCardIds: ['c1', 'm1', 'm2', 'm3'],
        ),
      );
      expect(hint.title, 'Lay it off');
      expect(hint.ringCardIds, ['c1', 'm1', 'm2', 'm3']);
      expect(hint.body, contains('King of Spades'));
      expect(hint.body, contains('highlighted meld'));
    });

    test('cover choice frames multiple covers as "either works"', () {
      final hint = present(
        const CoachingInsight(
          category: CoachingInsightCategory.playCover,
          priority: 550,
          coverCardId: 'c1',
          coverIsChoice: true,
          highlightCardIds: ['c1', 'm1', 'c2', 'n1'],
          meldGroups: [
            ['c1', 'm1'],
            ['c2', 'n1'],
          ],
        ),
      );
      expect(hint.title, 'Lay it off');
      expect(hint.body, contains('Either works'));
      // Each option rings as its own group so the player sees both covers.
      expect(hint.ringGroups.length, 2);
    });

    test('finish-by-cover reframes the finish as "cover to win"', () {
      final hint = present(
        const CoachingInsight(
          category: CoachingInsightCategory.finishAvailable,
          priority: 1000,
          coverFinishes: true,
          highlightCardIds: ['c1', 'm1', 'm2', 'm3'],
          meldGroups: [
            ['c1', 'm1', 'm2', 'm3'],
          ],
        ),
      );
      // Still the urgent finish pop-in, but the body tells the player to COVER
      // to win rather than the generic "empty your hand".
      expect(hint.intensity, CoachIntensity.popIn);
      expect(hint.accent, CoachAccent.finish);
      expect(hint.title, 'You can win');
      expect(hint.body, contains('Cover'));
      expect(hint.ringCardIds, ['c1', 'm1', 'm2', 'm3']);
    });

    test('discard suggestion rings the card in the warm discard hue', () {
      final hint = present(
        const CoachingInsight(
          category: CoachingInsightCategory.discardSuggestion,
          priority: 350,
          discardCardId: 'c1',
          highlightCardIds: ['c1'],
        ),
      );
      expect(hint.intensity, CoachIntensity.quiet);
      expect(hint.accent, CoachAccent.coach);
      // "Discard this" rings warm (discardRingCardIds), not teal (ringCardIds).
      expect(hint.ringCardIds, isEmpty);
      expect(hint.discardRingCardIds, ['c1']);
      expect(hint.body, contains('King of Spades'));
      expect(hint.body, contains('end your turn'));
    });

    test('opening progress combines keep cards with a discard suggestion', () {
      // The combined hint: keep cards ring teal/grouped (ringCardIds), the
      // recommended discard rings warm (discardRingCardIds), and the body says
      // both build-toward and discard.
      final hint = present(
        const CoachingInsight(
          category: CoachingInsightCategory.openingProgress,
          priority: 200,
          openingRequirement: 51,
          openingBestValue: 46,
          openingShortfall: 5,
          highlightCardIds: ['a', 'b', 'c'],
          discardCardId: 'c1',
        ),
      );
      expect(hint.ringCardIds, ['a', 'b', 'c']);
      expect(hint.discardRingCardIds, ['c1']);
      expect(hint.body, contains('46'));
      expect(hint.body, contains('Discard the King of Spades'));
    });

    test('draw hint without opening progress is the plain draw advice', () {
      final hint = present(
        const CoachingInsight(
          category: CoachingInsightCategory.drawStock,
          priority: 250,
        ),
      );
      expect(hint.title, 'Draw a card');
      expect(hint.zone, CoachZone.discard);
      expect(hint.body, contains('Draw from the stock'));
      expect(hint.body, isNot(contains('to go')));
    });

    test('draw hint folds in the opening shortfall when present', () {
      // Issue A: an unopened seat in the draw phase is told to draw, with the
      // opening progress folded into the body so the shortfall is not lost.
      final hint = present(
        const CoachingInsight(
          category: CoachingInsightCategory.drawStock,
          priority: 250,
          openingBestValue: 18,
          openingRequirement: 72,
          openingShortfall: 54,
          highlightCardIds: ['a', 'b', 'c'],
          meldGroups: [
            ['a', 'b', 'c'],
          ],
        ),
      );
      expect(hint.title, 'Draw a card');
      expect(hint.body, contains('18'));
      expect(hint.body, contains('54'));
      expect(hint.body, contains('to go'));
      // Regression: the in-hand meld-in-progress cards are ringed (the stock is
      // ringed separately via the drawStock category in the screen).
      expect(hint.ringCardIds, ['a', 'b', 'c']);
      expect(hint.ringGroups, [
        ['a', 'b', 'c'],
      ]);
    });

    test('opening progress with no meld teaches the requirement', () {
      final hint = present(
        const CoachingInsight(
          category: CoachingInsightCategory.openingProgress,
          priority: 200,
          openingRequirement: 51,
          openingBestValue: 0,
          openingShortfall: 51,
        ),
      );
      expect(hint.intensity, CoachIntensity.quiet);
      expect(hint.body, contains('51'));
      expect(hint.ringCardIds, isEmpty);
    });
  });
}
