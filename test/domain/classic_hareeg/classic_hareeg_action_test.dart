import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';

void main() {
  group('ClassicHareegActionIds.describe', () {
    test('classifies exact control actions', () {
      expect(
        ClassicHareegActionIds.describe(ClassicHareegActionIds.drawStock).kind,
        ClassicHareegActionKind.drawStock,
      );
      expect(
        ClassicHareegActionIds.describe(
          ClassicHareegActionIds.takeDiscard,
        ).kind,
        ClassicHareegActionKind.takeDiscard,
      );
      expect(
        ClassicHareegActionIds.describe(
          ClassicHareegActionIds.returnPendingDiscard,
        ).kind,
        ClassicHareegActionKind.returnPendingDiscard,
      );
      expect(
        ClassicHareegActionIds.describe(
          ClassicHareegActionIds.returnOpeningMelds,
        ).kind,
        ClassicHareegActionKind.returnOpeningMelds,
      );
      expect(
        ClassicHareegActionIds.describe(ClassicHareegActionIds.claimFifty).kind,
        ClassicHareegActionKind.claimFifty,
      );
    });

    test('parses plain meld actions', () {
      final action = ClassicHareegActionIds.describe(
        ClassicHareegActionIds.playMeldActionId(['c1', 'c2', 'c3']),
      );

      expect(action.kind, ClassicHareegActionKind.playMeld);
      expect(action.cardIds, ['c1', 'c2', 'c3']);
      expect(action.isMeldPlay, isTrue);
      expect(action.isTablePlay, isTrue);
    });

    test('parses explicit joker meld actions', () {
      const identity = CardIdentity(rank: CardRank.ace, suit: CardSuit.spades);
      final action = ClassicHareegActionIds.describe(
        ClassicHareegActionIds.playMeldWithJokerIdentityActionId(
          cardIds: ['joker', 'c2', 'c3'],
          jokerId: 'joker',
          identity: identity,
        ),
      );

      expect(action.kind, ClassicHareegActionKind.playMeldWithJoker);
      expect(action.cardIds, ['joker', 'c2', 'c3']);
      expect(action.jokerMeldChoice?.jokerId, 'joker');
      expect(action.jokerMeldChoice?.identity, identity);
    });

    test('parses explicit multi-joker meld actions', () {
      const first = JokerMeldAssignment(
        jokerId: 'joker-a',
        identity: CardIdentity(rank: CardRank.nine, suit: CardSuit.clubs),
      );
      const second = JokerMeldAssignment(
        jokerId: 'joker-b',
        identity: CardIdentity(rank: CardRank.queen, suit: CardSuit.clubs),
      );
      final actionId =
          ClassicHareegActionIds.playMeldWithJokerIdentitiesActionId(
            cardIds: ['joker-a', 'c2', 'c3', 'joker-b'],
            assignments: [first, second],
          );

      final action = ClassicHareegActionIds.describe(actionId);

      expect(
        actionId,
        startsWith(ClassicHareegActionIds.playMeldWithJokersPrefix),
      );
      expect(action.kind, ClassicHareegActionKind.playMeldWithJoker);
      expect(action.cardIds, ['joker-a', 'c2', 'c3', 'joker-b']);
      expect(action.jokerMeldChoice?.assignments, hasLength(2));
      expect(action.jokerMeldChoice?.assignments.first.jokerId, 'joker-a');
      expect(
        action.jokerMeldChoice?.assignments.last.identity,
        second.identity,
      );
    });

    test('parses table play actions with their targets', () {
      final coverAction = ClassicHareegActionIds.describe(
        ClassicHareegActionIds.placeCoverActionId(
          targetSeat: PlayerSeat.west,
          meldIndex: 2,
          cardIds: ['cover-1', 'cover-2'],
        ),
      );
      expect(coverAction.kind, ClassicHareegActionKind.placeCover);
      expect(coverAction.cardIds, ['cover-1', 'cover-2']);
      expect(coverAction.coverTarget?.targetSeat, PlayerSeat.west);
      expect(coverAction.coverTarget?.meldIndex, 2);

      final replacementAction = ClassicHareegActionIds.describe(
        ClassicHareegActionIds.replaceJokerActionId(
          targetSeat: PlayerSeat.north,
          meldIndex: 1,
          cardId: 'replacement',
        ),
      );
      expect(replacementAction.kind, ClassicHareegActionKind.replaceJoker);
      expect(replacementAction.cardId, 'replacement');
      expect(
        replacementAction.jokerReplacementTarget?.targetSeat,
        PlayerSeat.north,
      );
      expect(replacementAction.jokerReplacementTarget?.meldIndex, 1);

      final returnAction = ClassicHareegActionIds.describe(
        ClassicHareegActionIds.returnTablePlayActionId(
          owner: PlayerSeat.south,
          meldIndex: 0,
        ),
      );
      expect(returnAction.kind, ClassicHareegActionKind.returnTablePlay);
      expect(returnAction.returnTablePlayTarget?.owner, PlayerSeat.south);
      expect(returnAction.returnTablePlayTarget?.meldIndex, 0);
    });

    test('classifies discard variants', () {
      final plain = ClassicHareegActionIds.describe('discard:plain-card');
      final blocked = ClassicHareegActionIds.describe(
        'discard-blocked-cover:cover-card',
      );
      final joker = ClassicHareegActionIds.describe('discard-joker:joker-card');

      expect(plain.kind, ClassicHareegActionKind.discard);
      expect(plain.cardId, 'plain-card');
      expect(plain.isDiscard, isTrue);
      expect(plain.isSafeDiscard, isTrue);

      expect(blocked.kind, ClassicHareegActionKind.discardBlockedCover);
      expect(blocked.cardId, 'cover-card');
      expect(blocked.isDiscard, isTrue);
      expect(blocked.isSafeDiscard, isFalse);

      expect(joker.kind, ClassicHareegActionKind.discardJoker);
      expect(joker.cardId, 'joker-card');
      expect(joker.isDiscard, isTrue);
      expect(joker.isSafeDiscard, isFalse);
    });

    test('centralizes human selection clearing rules', () {
      expect(
        ClassicHareegActionIds.describe('discard:c1').clearsSelection,
        isTrue,
      );
      expect(
        ClassicHareegActionIds.describe(
          ClassicHareegActionIds.playMeldActionId(['c1', 'c2', 'c3']),
        ).clearsSelection,
        isTrue,
      );
      expect(
        ClassicHareegActionIds.describe(
          ClassicHareegActionIds.returnOpeningMelds,
        ).clearsSelection,
        isTrue,
      );
      expect(
        ClassicHareegActionIds.describe(
          ClassicHareegActionIds.returnPendingDiscard,
        ).clearsSelection,
        isTrue,
      );
      expect(
        ClassicHareegActionIds.describe(
          ClassicHareegActionIds.drawStock,
        ).clearsSelection,
        isFalse,
      );
      expect(
        ClassicHareegActionIds.describe(
          ClassicHareegActionIds.takeDiscard,
        ).clearsSelection,
        isFalse,
      );
      expect(
        ClassicHareegActionIds.describe(
          ClassicHareegActionIds.claimFifty,
        ).clearsSelection,
        isFalse,
      );
    });

    test('classifies unknown and malformed actions as unknown', () {
      expect(
        ClassicHareegActionIds.describe('not-an-action').kind,
        ClassicHareegActionKind.unknown,
      );
      expect(
        ClassicHareegActionIds.describe('place-cover:west:0').kind,
        ClassicHareegActionKind.unknown,
      );
    });
  });
}
