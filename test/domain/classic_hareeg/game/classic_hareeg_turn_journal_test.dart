import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_turn_journal.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/finish_rules.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

void main() {
  group('ClassicHareegTurnJournal', () {
    test('starts empty with stock source', () {
      final journal = ClassicHareegTurnJournal();
      expect(journal.finishMeldsView, isEmpty);
      expect(journal.openingMeldsView, isEmpty);
      expect(journal.turnMeldsView, isEmpty);
      expect(journal.coverPlaysView, isEmpty);
      expect(journal.consumedPendingDiscard, isNull);
      expect(journal.source, FinishCardSource.stock);
      expect(journal.hasAnyReversible, isFalse);
    });

    group('opening melds round-trip', () {
      test('record then bulk-drain returns the staged plays', () {
        final journal = ClassicHareegTurnJournal();
        final tens = meld([
          card(CardRank.ten, CardSuit.clubs, 100),
          card(CardRank.ten, CardSuit.diamonds, 101),
          card(CardRank.ten, CardSuit.hearts, 102),
        ]);

        journal.recordOpeningMelds([tens]);
        journal.recordFinishMelds([tens]);

        expect(journal.openingMeldsView, [tens]);
        expect(journal.finishMeldsView, [tens]);
        expect(journal.hasAnyReversible, isTrue);

        final drained = journal.drainOpeningMelds();
        expect(drained, [tens]);
        expect(journal.openingMeldsView, isEmpty);
        // Finish view is not auto-cleared by drainOpeningMelds — the controller
        // removes finish plays explicitly per retracted meld.
        expect(journal.finishMeldsView, [tens]);

        journal.removeFinishMeldMatching(tens);
        expect(journal.finishMeldsView, isEmpty);
      });

      test('specific staged opening is found by physical cards', () {
        final journal = ClassicHareegTurnJournal();
        final tens = meld([
          card(CardRank.ten, CardSuit.clubs, 100),
          card(CardRank.ten, CardSuit.diamonds, 101),
          card(CardRank.ten, CardSuit.hearts, 102),
        ]);
        final nines = meld([
          card(CardRank.nine, CardSuit.clubs, 110),
          card(CardRank.nine, CardSuit.diamonds, 111),
          card(CardRank.nine, CardSuit.hearts, 112),
        ]);
        journal.recordOpeningMelds([tens, nines]);

        final index = journal.findStagedOpeningIndexByPhysicalCards(
          nines.cards,
        );
        expect(index, 1);
        expect(journal.isValidStagedOpeningIndex(index), isTrue);
        expect(journal.stagedOpeningMeldAt(index), nines);

        final removed = journal.removeStagedOpeningAt(index);
        expect(removed, nines);
        expect(journal.openingMeldsView, [tens]);
        expect(journal.removeStagedOpeningAt(99), isNull);
      });

      test('commitOpeningMelds clears staged + consumed pending', () {
        final journal = ClassicHareegTurnJournal();
        final pending = card(CardRank.five, CardSuit.spades, 200);
        final tens = meld([
          card(CardRank.ten, CardSuit.clubs, 100),
          card(CardRank.ten, CardSuit.diamonds, 101),
          card(CardRank.ten, CardSuit.hearts, 102),
        ]);
        journal.recordOpeningMelds(
          [tens],
          consumedPendingDiscard: pending,
        );

        expect(journal.consumedPendingDiscard, pending);

        journal.commitOpeningMelds();
        expect(journal.openingMeldsView, isEmpty);
        expect(journal.consumedPendingDiscard, isNull);
      });
    });

    group('turn meld plays round-trip', () {
      test('recordTurnMeld then removeTurnMeld restores empty state', () {
        final journal = ClassicHareegTurnJournal();
        final meldPlay = ClassicHareegTurnMeldPlay(
          owner: PlayerSeat.south,
          meld: meld([
            card(CardRank.five, CardSuit.clubs, 300),
            card(CardRank.six, CardSuit.clubs, 301),
            card(CardRank.seven, CardSuit.clubs, 302),
          ]),
        );

        journal.recordTurnMeld(meldPlay);
        journal.recordFinishMelds([meldPlay.meld]);
        expect(journal.turnMeldsView, [meldPlay]);

        final found = journal.findTurnMeldFor(
          owner: PlayerSeat.south,
          targetMeld: meldPlay.meld,
        );
        expect(found, same(meldPlay));

        final removed = journal.removeTurnMeld(meldPlay);
        expect(removed, isTrue);
        expect(journal.turnMeldsView, isEmpty);
        expect(journal.removeTurnMeld(meldPlay), isFalse);

        journal.removeFinishMeldMatching(meldPlay.meld);
        expect(journal.finishMeldsView, isEmpty);
      });

      test('bulk drain reports all turn melds', () {
        final journal = ClassicHareegTurnJournal();
        final firstPlay = ClassicHareegTurnMeldPlay(
          owner: PlayerSeat.south,
          meld: meld([
            card(CardRank.five, CardSuit.clubs, 300),
            card(CardRank.six, CardSuit.clubs, 301),
            card(CardRank.seven, CardSuit.clubs, 302),
          ]),
        );
        final secondPlay = ClassicHareegTurnMeldPlay(
          owner: PlayerSeat.south,
          meld: meld([
            card(CardRank.two, CardSuit.hearts, 310),
            card(CardRank.three, CardSuit.hearts, 311),
            card(CardRank.four, CardSuit.hearts, 312),
          ]),
        );
        journal.recordTurnMelds([firstPlay, secondPlay]);
        expect(journal.turnMeldsView, [firstPlay, secondPlay]);

        final drained = journal.drainTurnMelds();
        expect(drained, [firstPlay, secondPlay]);
        expect(journal.turnMeldsView, isEmpty);
        expect(journal.drainTurnMelds(), isEmpty);
      });
    });

    group('cover plays round-trip', () {
      test('record then remove cover for target leaves siblings intact', () {
        final journal = ClassicHareegTurnJournal();
        final coverFirst = card(CardRank.six, CardSuit.hearts, 400);
        final coverSecond = card(CardRank.seven, CardSuit.hearts, 401);
        final firstPlay = ClassicHareegTurnCoverPlay(
          targetSeat: PlayerSeat.east,
          meldIndex: 0,
          previousMeld: meld([
            card(CardRank.three, CardSuit.hearts, 402),
            card(CardRank.four, CardSuit.hearts, 403),
            card(CardRank.five, CardSuit.hearts, 404),
          ]),
          coverMeld: PlacedMeld(cards: [coverFirst], valueSnapshot: 6),
          previousOpeningState: opened(PlayerSeat.south),
        );
        final siblingPlay = ClassicHareegTurnCoverPlay(
          targetSeat: PlayerSeat.east,
          meldIndex: 1,
          previousMeld: meld([
            card(CardRank.three, CardSuit.clubs, 405),
            card(CardRank.four, CardSuit.clubs, 406),
            card(CardRank.five, CardSuit.clubs, 407),
          ]),
          coverMeld: PlacedMeld(cards: [coverSecond], valueSnapshot: 7),
          previousOpeningState: opened(PlayerSeat.south),
        );

        journal.recordCoverPlay(firstPlay);
        journal.recordCoverPlay(siblingPlay);
        journal.recordFinishMelds([firstPlay.coverMeld, siblingPlay.coverMeld]);

        expect(
          journal.coverPlaysFor(owner: PlayerSeat.east, meldIndex: 0),
          [firstPlay],
        );

        journal.removeCoverPlaysFor(
          targetSeat: PlayerSeat.east,
          meldIndex: 0,
        );
        journal.removeFinishMeldMatching(firstPlay.coverMeld);

        expect(
          journal.coverPlaysFor(owner: PlayerSeat.east, meldIndex: 0),
          isEmpty,
        );
        expect(journal.coverPlaysView, [siblingPlay]);
        expect(journal.finishMeldsView, [siblingPlay.coverMeld]);
      });
    });

    group('checkpoint projection', () {
      test('captures every play kind as an immutable value', () {
        final journal = ClassicHareegTurnJournal();
        final pending = card(CardRank.five, CardSuit.spades, 500);
        final openingMeld = meld([
          card(CardRank.ten, CardSuit.clubs, 510),
          card(CardRank.ten, CardSuit.diamonds, 511),
          card(CardRank.ten, CardSuit.hearts, 512),
        ]);
        final turnPlay = ClassicHareegTurnMeldPlay(
          owner: PlayerSeat.south,
          meld: meld([
            card(CardRank.five, CardSuit.clubs, 520),
            card(CardRank.six, CardSuit.clubs, 521),
            card(CardRank.seven, CardSuit.clubs, 522),
          ]),
        );
        final cover = card(CardRank.six, CardSuit.hearts, 530);
        final coverPlay = ClassicHareegTurnCoverPlay(
          targetSeat: PlayerSeat.east,
          meldIndex: 0,
          previousMeld: meld([
            card(CardRank.three, CardSuit.hearts, 540),
            card(CardRank.four, CardSuit.hearts, 541),
            card(CardRank.five, CardSuit.hearts, 542),
          ]),
          coverMeld: PlacedMeld(cards: [cover], valueSnapshot: 6),
          previousOpeningState: opened(PlayerSeat.south),
        );

        journal
          ..recordOpeningMelds([openingMeld], consumedPendingDiscard: pending)
          ..recordTurnMeld(turnPlay)
          ..recordCoverPlay(coverPlay)
          ..recordFinishMelds([openingMeld, turnPlay.meld, coverPlay.coverMeld])
          ..setSource(FinishCardSource.previousDiscard);

        final checkpoint = journal.projectCheckpoint();
        expect(checkpoint.openingMelds, [openingMeld]);
        expect(checkpoint.turnMelds, [turnPlay]);
        expect(checkpoint.coverPlays, [coverPlay]);
        expect(checkpoint.finishMelds, [
          openingMeld,
          turnPlay.meld,
          coverPlay.coverMeld,
        ]);
        expect(checkpoint.consumedPendingDiscard, pending);
        expect(checkpoint.source, FinishCardSource.previousDiscard);

        // The checkpoint is a value snapshot: mutating the journal afterwards
        // must not change it.
        journal.resetForNewTurn();
        expect(checkpoint.openingMelds, [openingMeld]);
        expect(checkpoint.turnMelds, [turnPlay]);
        expect(checkpoint.coverPlays, [coverPlay]);
        expect(checkpoint.finishMelds, hasLength(3));

        // Checkpoint lists are unmodifiable.
        expect(
          () => checkpoint.openingMelds.add(openingMeld),
          throwsUnsupportedError,
        );
      });
    });

    test('resetForNewTurn drops all plays and updates source', () {
      final journal = ClassicHareegTurnJournal();
      final pending = card(CardRank.five, CardSuit.spades, 600);
      journal
        ..recordFinishMelds([
          meld([
            card(CardRank.ten, CardSuit.clubs, 610),
            card(CardRank.ten, CardSuit.diamonds, 611),
            card(CardRank.ten, CardSuit.hearts, 612),
          ]),
        ])
        ..recordConsumedPendingDiscard(pending);

      journal.resetForNewTurn(source: FinishCardSource.previousDiscard);
      expect(journal.finishMeldsView, isEmpty);
      expect(journal.openingMeldsView, isEmpty);
      expect(journal.turnMeldsView, isEmpty);
      expect(journal.coverPlaysView, isEmpty);
      expect(journal.consumedPendingDiscard, isNull);
      expect(journal.source, FinishCardSource.previousDiscard);
    });

    test('views are unmodifiable', () {
      final journal = ClassicHareegTurnJournal();
      final tens = meld([
        card(CardRank.ten, CardSuit.clubs, 700),
        card(CardRank.ten, CardSuit.diamonds, 701),
        card(CardRank.ten, CardSuit.hearts, 702),
      ]);
      journal.recordOpeningMelds([tens]);

      expect(() => journal.openingMeldsView.add(tens), throwsUnsupportedError);
      expect(
        () => journal.finishMeldsView.add(tens),
        throwsUnsupportedError,
      );
    });
  });
}

OpeningState opened(PlayerSeat seat) {
  return OpeningState(
    baseRequirement: 51,
    currentRequirement: 51,
    openedSeats: {seat},
  );
}

PlacedMeld meld(List<HareegCard> cards) => PlacedMeld.fromCards(cards);

HareegCard card(CardRank rank, CardSuit suit, [int deckIndex = 800]) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);
}
