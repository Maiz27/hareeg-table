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
    final hint = CoachHintPresenter.present(
      insight: insight,
      strings: strings,
      identityForCardId: lookup,
      topDiscardIdentity: topDiscard,
    );
    return hint!;
  }

  CoachHint? presentOrNull(CoachingInsight insight, {CardIdentity? topDiscard}) {
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

    test('joker swap folds in the meld the swap card anchors', () {
      // The swap card also forms a meld in hand: the copy must teach the
      // order (swap first, the meld still works with the freed joker).
      final hint = present(
        const CoachingInsight(
          category: CoachingInsightCategory.jokerAdvice,
          priority: 750,
          jokerCardId: 'c1',
          highlightCardIds: ['c1', 'm1', 'm2', 'm3', 'h1', 'h2'],
          meldGroups: [
            ['h1', 'h2', 'c1'],
          ],
        ),
      );
      expect(hint.body, contains('swap'));
      expect(hint.body, contains('Swap first'));
      expect(hint.body, contains('melding first burns the swap'));
      expect(hint.ringGroups, [
        ['h1', 'h2', 'c1'],
      ]);
    });

    test('discard suggestion folds in a collecting hold-back warning', () {
      final hint = present(
        const CoachingInsight(
          category: CoachingInsightCategory.discardSuggestion,
          priority: 350,
          discardCardId: 'd1',
          avoidCardId: 'c1',
          avoidOpponent: PlayerSeat.east,
          avoidReason: CoachAvoidReason.collecting,
          avoidRank: CardRank.king,
          highlightCardIds: ['d1'],
        ),
      );
      expect(hint.body, contains('Hold back the King of Spades'));
      expect(hint.body, contains('picking up'));
      // The hold-back card rings cool (it stays in hand); the recommended
      // throw rings warm.
      expect(hint.ringCardIds, ['c1']);
      expect(hint.discardRingCardIds, ['d1']);
      // The hold-back card participates in the situation key so a changed
      // warning re-animates the callout.
      expect(hint.situationKey, contains('c1'));
    });

    test('discard suggestion folds in a run-end hold-back warning', () {
      final hint = present(
        const CoachingInsight(
          category: CoachingInsightCategory.discardSuggestion,
          priority: 350,
          discardCardId: 'd1',
          avoidCardId: 'c1',
          avoidOpponent: PlayerSeat.east,
          avoidReason: CoachAvoidReason.runEnd,
          highlightCardIds: ['d1'],
        ),
      );
      expect(hint.body, contains('Hold back the King of Spades'));
      expect(hint.body, contains('run'));
    });

    test('discard suggestion narrates a deliberately held cover', () {
      // The brain sees the legal lay-off and keeps it (Fifty development);
      // the hint must say so and ring the cover with its target meld as a
      // cool keep group — silence about a drawn cover reads as blindness.
      final hint = present(
        const CoachingInsight(
          category: CoachingInsightCategory.discardSuggestion,
          priority: 350,
          discardCardId: 'd1',
          coverCardId: 'c1',
          coverMeldOwner: PlayerSeat.east,
          coverMeldIndex: 0,
          holdCoverReason: CoachCoverHoldReason.fiftyDevelopment,
          highlightCardIds: ['d1', 'c1', 'm1', 'm2'],
          meldGroups: [
            ['c1', 'm1', 'm2'],
          ],
        ),
      );
      expect(
        hint.body,
        contains('The King of Spades could cover the highlighted meld'),
      );
      expect(hint.body, contains('Fifty'));
      expect(hint.ringCardIds, containsAll(['c1', 'm1', 'm2']));
      expect(hint.ringGroups, [
        ['c1', 'm1', 'm2'],
      ]);
      expect(hint.discardRingCardIds, ['d1']);
    });

    test('discard suggestion narrates a guarded joker cover', () {
      final hint = present(
        const CoachingInsight(
          category: CoachingInsightCategory.discardSuggestion,
          priority: 350,
          discardCardId: 'd1',
          coverCardId: 'j1',
          holdCoverReason: CoachCoverHoldReason.jokerGuard,
          meldGroups: [
            ['j1', 'm1'],
          ],
        ),
      );
      expect(hint.body, contains('never burn a joker'));
    });

    test('take-and-finish is an urgent discard-zone win moment', () {
      final hint = present(
        const CoachingInsight(
          category: CoachingInsightCategory.takeAndFinish,
          priority: 880,
          highlightCardIds: ['top'],
        ),
        topDiscard: seven,
      );
      expect(hint.intensity, CoachIntensity.popIn);
      expect(hint.accent, CoachAccent.finish);
      expect(hint.zone, CoachZone.discard);
      expect(hint.title, 'Take it and finish');
      expect(hint.body, contains('Seven of Hearts'));
      expect(hint.body, contains('−1'));
    });

    test('fifty-hold explains the trade against an opponent score', () {
      final hint = present(
        const CoachingInsight(
          category: CoachingInsightCategory.fiftyHold,
          priority: 860,
          subjectSeat: PlayerSeat.west,
          subjectValue: 27,
          highlightCardIds: ['a', 'b', 'c'],
          meldGroups: [
            ['a', 'b', 'c'],
          ],
        ),
      );
      expect(hint.accent, CoachAccent.fifty);
      expect(hint.intensity, CoachIntensity.quiet);
      expect(hint.body, contains('finish now'));
      expect(hint.body, contains('27'));
      expect(hint.ringCardIds, ['a', 'b', 'c']);
    });

    test('fifty-hold self variant cites the player\'s own score', () {
      final hint = present(
        const CoachingInsight(
          category: CoachingInsightCategory.fiftyHold,
          priority: 860,
          subjectSeat: PlayerSeat.south,
          subjectIsSelf: true,
          subjectValue: 26,
        ),
      );
      expect(hint.body, contains('26'));
      expect(hint.body, contains('you'));
    });

    test('fifty-hold names the throw that keeps the hold alive', () {
      // Playtest: the hold hint never said how to end the turn (and the
      // obvious guess could be an illegal cover-blocked throw). The advisor
      // now passes the Expert plan's legal discard; the copy names it and it
      // rings warm.
      final hint = present(
        const CoachingInsight(
          category: CoachingInsightCategory.fiftyHold,
          priority: 860,
          subjectSeat: PlayerSeat.west,
          subjectValue: 27,
          discardCardId: 'c1',
          highlightCardIds: ['a', 'b'],
        ),
      );
      expect(hint.body, contains('To keep waiting, throw the King of Spades'));
      expect(hint.discardRingCardIds, ['c1']);
      // The punished seat is the one whose discard the claim takes.
      expect(hint.body, contains('next discard'));
    });

    test('finish with a plan names the final discard and rings it warm', () {
      final hint = present(
        const CoachingInsight(
          category: CoachingInsightCategory.finishAvailable,
          priority: 1000,
          discardCardId: 'c1',
          coverFinishes: true,
          highlightCardIds: ['a', 'b', 'c'],
          meldGroups: [
            ['a', 'b', 'c'],
          ],
        ),
      );
      expect(hint.body, contains('throw the King of Spades'));
      expect(hint.body, contains('win the round'));
      expect(hint.discardRingCardIds, ['c1']);
      expect(hint.ringCardIds, ['a', 'b', 'c']);
    });

    test('finish that doubles as the opening teaches the bypass', () {
      final hint = present(
        const CoachingInsight(
          category: CoachingInsightCategory.finishAvailable,
          priority: 1000,
          discardCardId: 'c1',
          bypassesOpening: true,
          highlightCardIds: ['a', 'b', 'c'],
        ),
      );
      expect(hint.body, contains('throw the King of Spades'));
      expect(hint.body, contains('opening'));
    });

    test('self vs target situation keys differ even at the same seat', () {
      // Key hygiene: scorePosture renders materially different copy for the
      // seat itself vs a target opponent. Self is the south seat today so the
      // seat token differs anyway, but the situation key must carry the
      // self/target dimension on its own, not lean on that invariant — so two
      // insights identical except subjectIsSelf must re-animate the callout.
      const selfPosture = CoachingInsight(
        category: CoachingInsightCategory.scorePosture,
        priority: 380,
        subjectSeat: PlayerSeat.south,
        subjectIsSelf: true,
        subjectValue: 27,
        subjectThreshold: 31,
      );
      const targetPosture = CoachingInsight(
        category: CoachingInsightCategory.scorePosture,
        priority: 380,
        subjectSeat: PlayerSeat.south,
        subjectValue: 27,
        subjectThreshold: 31,
      );
      expect(
        present(selfPosture).situationKey,
        isNot(present(targetPosture).situationKey),
      );
    });

    test('a target banner missing its subject seat trips the guard', () {
      // FIX 4: the target variant names the pressed opponent, so it requires a
      // subjectSeat. In debug (asserts on, as under `flutter test`) the guard
      // fires; in release it returns null and skips the banner rather than
      // force-unwrapping into a crash. Pin both: the malformed target trips the
      // assertion here, while the well-formed self variant still renders.
      expect(
        () => presentOrNull(
          const CoachingInsight(
            category: CoachingInsightCategory.scorePosture,
            priority: 380,
            subjectIsSelf: false,
          ),
        ),
        throwsAssertionError,
      );
      final selfHint = presentOrNull(
        const CoachingInsight(
          category: CoachingInsightCategory.scorePosture,
          priority: 380,
          subjectSeat: PlayerSeat.south,
          subjectIsSelf: true,
          subjectValue: 27,
          subjectThreshold: 31,
        ),
      );
      expect(selfHint, isNotNull);
    });

    test('score posture banners pick the self vs target copy', () {
      final self = present(
        const CoachingInsight(
          category: CoachingInsightCategory.scorePosture,
          priority: 380,
          subjectSeat: PlayerSeat.south,
          subjectIsSelf: true,
          subjectValue: 27,
          subjectThreshold: 31,
        ),
      );
      expect(self.title, 'Watch your score');
      expect(self.body, contains('27'));
      expect(self.body, contains('31'));

      final target = present(
        const CoachingInsight(
          category: CoachingInsightCategory.scorePosture,
          priority: 380,
          subjectSeat: PlayerSeat.east,
          subjectValue: 29,
        ),
      );
      expect(target.title, 'Press the lead');
      expect(target.body, contains('29'));
    });

    test('stock-low banner anchors to the discard zone with the count', () {
      final hint = present(
        const CoachingInsight(
          category: CoachingInsightCategory.endgameStockLow,
          priority: 375,
          subjectValue: 5,
        ),
      );
      expect(hint.zone, CoachZone.discard);
      expect(hint.body, contains('5'));
      expect(hint.body, contains('draw'));
    });

    test('opponent-close banner names the seat and count', () {
      final hint = present(
        const CoachingInsight(
          category: CoachingInsightCategory.opponentCloseToFinish,
          priority: 370,
          subjectSeat: PlayerSeat.north,
          subjectValue: 2,
        ),
      );
      expect(hint.body, contains('2 cards'));
    });

    test('benchmark banner carries the raised requirement', () {
      final hint = present(
        const CoachingInsight(
          category: CoachingInsightCategory.benchmarkAlert,
          priority: 365,
          subjectSeat: PlayerSeat.west,
          openingRequirement: 68,
        ),
      );
      expect(hint.title, 'The bar was raised');
      expect(hint.body, contains('68'));
    });

    test('bait banner explains why the tempting discard stays', () {
      final hint = present(
        const CoachingInsight(
          category: CoachingInsightCategory.baitDiscard,
          priority: 360,
          highlightCardIds: ['top'],
        ),
        topDiscard: seven,
      );
      expect(hint.zone, CoachZone.discard);
      expect(hint.title, 'Let it lie');
      expect(hint.body, contains('Seven of Hearts'));
      expect(hint.body, contains('reveals'));
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

    test('draw hint with a zero shortfall says open after drawing', () {
      // Draw phase, but the hand already meets the opening value: the draw
      // still comes first; opening is framed as the immediate next step.
      final hint = present(
        const CoachingInsight(
          category: CoachingInsightCategory.drawStock,
          priority: 250,
          openingBestValue: 60,
          openingRequirement: 51,
          openingShortfall: 0,
        ),
      );
      expect(hint.title, 'Draw a card');
      expect(hint.body, contains('already meets'));
      expect(hint.body, contains('Draw first'));
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
