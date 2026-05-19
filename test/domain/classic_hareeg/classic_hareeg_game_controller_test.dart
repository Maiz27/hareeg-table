import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_strategy.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/match_progression_rules.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

void main() {
  group('ClassicHareegGameController legal action enforcement', () {
    test('rejects normal joker discards under any preset', () {
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [
              defaults[PlayerSeat.south]!.firstWhere((c) => !c.isJoker),
              HareegCard.joker(deckIndex: 0, jokerIndex: 0),
              defaults[PlayerSeat.south]!.firstWhere(
                (c) => !c.isJoker,
                orElse: () => throw 'no card',
              ),
            ].followedBy(defaults[PlayerSeat.south]!.skip(2)).toList(),
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
        ),
      );

      final legal = controller.legalActionIdsFor(PlayerSeat.south);
      expect(
        legal,
        isNot(
          contains(
            '${ClassicHareegActionIds.discardJokerPrefix}deck-0-joker-0',
          ),
        ),
        reason: 'Normal joker discards are hard-blocked in every preset.',
      );

      final joker = controller
          .handFor(PlayerSeat.south)
          .firstWhere((card) => card.isJoker);
      final result = controller.applyAction(
        '${ClassicHareegActionIds.discardJokerPrefix}${joker.id}',
      );

      expect(result.isSuccess, isFalse);
      expect(result.message, contains('not legal'));
      expect(controller.handFor(PlayerSeat.south), contains(joker));
    });

    test(
      'legalActionIdsFor in action phase enumerates each non-joker card',
      () {
        final controller = _freshControllerInActionPhase();

        final hand = controller.handFor(PlayerSeat.south);
        final nonJokerCount = hand.where((card) => !card.isJoker).length;

        final legal = controller.legalActionIdsFor(PlayerSeat.south);
        final discards = legal
            .where((id) => id.startsWith(ClassicHareegActionIds.discardPrefix))
            .toList();

        expect(discards, hasLength(nonJokerCount));
      },
    );

    test('a successful human discard advances the seat and turn phase', () {
      final controller = _freshControllerInActionPhase();
      final hand = controller.handFor(PlayerSeat.south);
      final card = hand.firstWhere((c) => !c.isJoker);

      final result = controller.applyAction(
        '${ClassicHareegActionIds.discardPrefix}${card.id}',
      );

      expect(result.isSuccess, isTrue);
      expect(controller.currentSeat, PlayerSeat.east);
      expect(controller.turnPhase, TurnPhase.draw);
      expect(controller.topDiscard?.id, card.id);
    });

    test('applying an unrelated action id reports failure', () {
      final controller = _freshControllerInActionPhase();

      final result = controller.applyAction('nope');

      expect(result.isSuccess, isFalse);
    });

    test('only the immediate next seat may take the previous discard', () {
      final controller = _freshControllerInActionPhase();
      final hand = controller.handFor(PlayerSeat.south);
      final card = hand.firstWhere((c) => !c.isJoker);
      controller.applyAction(
        '${ClassicHareegActionIds.discardPrefix}${card.id}',
      );

      expect(
        controller.legalActionIdsFor(PlayerSeat.east),
        contains(ClassicHareegActionIds.takeDiscard),
      );
      expect(
        controller.legalActionIdsFor(PlayerSeat.north),
        isEmpty,
        reason: 'It is not yet North\'s turn.',
      );
    });

    test('pending state limits legal actions to use or return', () {
      final controller = _freshControllerInActionPhase();
      final south = controller.handFor(PlayerSeat.south);
      final discardedByHuman = south.firstWhere((c) => !c.isJoker);
      controller.applyAction(
        '${ClassicHareegActionIds.discardPrefix}${discardedByHuman.id}',
      );

      final result = controller.applyAction(ClassicHareegActionIds.takeDiscard);

      expect(result.isSuccess, isTrue);
      expect(controller.pendingDiscard?.id, discardedByHuman.id);
      expect(
        controller.legalActionIdsFor(PlayerSeat.east),
        equals([ClassicHareegActionIds.returnPendingDiscard]),
      );
    });

    test('returning a pending discard puts the card back on the pile', () {
      final controller = _freshControllerInActionPhase();
      final south = controller.handFor(PlayerSeat.south);
      final discarded = south.firstWhere((c) => !c.isJoker);
      controller.applyAction(
        '${ClassicHareegActionIds.discardPrefix}${discarded.id}',
      );
      controller.applyAction(ClassicHareegActionIds.takeDiscard);

      final stockBefore = controller.stockCount;
      final eastHandBefore = controller.cardCountFor(PlayerSeat.east);
      controller.applyAction(ClassicHareegActionIds.returnPendingDiscard);

      expect(controller.pendingDiscard, isNull);
      expect(controller.topDiscard?.id, discarded.id);
      expect(controller.stockCount, stockBefore - 1);
      expect(controller.cardCountFor(PlayerSeat.east), eastHandBefore);
    });

    test('playing a valid meld removes cards and keeps the turn active', () {
      final meldCards = [
        _card(CardRank.seven, CardSuit.clubs, 20),
        _card(CardRank.seven, CardSuit.diamonds, 20),
        _card(CardRank.seven, CardSuit.hearts, 20),
      ];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [...meldCards, ...defaults[PlayerSeat.south]!],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
        ),
      );

      final result = controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(
          meldCards.map((card) => card.id),
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(controller.currentSeat, PlayerSeat.south);
      expect(controller.turnPhase, TurnPhase.action);
      expect(controller.tableMeldsFor(PlayerSeat.south), hasLength(1));
      expect(
        controller.tableMeldsFor(PlayerSeat.south).single.valueSnapshot,
        21,
      );
      expect(
        controller.handFor(PlayerSeat.south).map((card) => card.id),
        isNot(containsAll(meldCards.map((card) => card.id))),
      );
    });

    test('playing a three-card sequence is legal', () {
      final meldCards = [
        _card(CardRank.five, CardSuit.clubs, 23),
        _card(CardRank.six, CardSuit.clubs, 23),
        _card(CardRank.seven, CardSuit.clubs, 23),
      ];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [...meldCards, ...defaults[PlayerSeat.south]!],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
        ),
      );

      final result = controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(
          meldCards.map((card) => card.id),
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(
        controller.tableMeldsFor(PlayerSeat.south).single.cards,
        hasLength(3),
      );
    });

    test('playing a sequence with one obvious joker assigns its identity', () {
      final joker = HareegCard.joker(deckIndex: 25, jokerIndex: 0);
      final meldCards = [
        _card(CardRank.nine, CardSuit.spades, 25),
        _card(CardRank.ten, CardSuit.spades, 25),
        joker,
        _card(CardRank.queen, CardSuit.spades, 25),
      ];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [...meldCards, ...defaults[PlayerSeat.south]!],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
        ),
      );

      final selectedIds = meldCards.map((card) => card.id).toList();
      final validation = controller.meldValidationFor(
        PlayerSeat.south,
        selectedIds,
      );
      final result = controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(selectedIds),
      );

      expect(validation.isValid, isTrue);
      expect(validation.message, contains('Joker as JS'));
      expect(result.isSuccess, isTrue);
      expect(
        controller
            .tableMeldsFor(PlayerSeat.south)
            .single
            .cards
            .map((card) => card.label),
        ['9S', '10S', 'J(JS)', 'QS'],
      );
      expect(
        controller.tableMeldsFor(PlayerSeat.south).single.valueSnapshot,
        39,
      );
    });

    test('playing a three-card sequence with one obvious joker is legal', () {
      final joker = HareegCard.joker(deckIndex: 26, jokerIndex: 0);
      final meldCards = [
        _card(CardRank.ten, CardSuit.spades, 26),
        joker,
        _card(CardRank.queen, CardSuit.spades, 26),
      ];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [...meldCards, ...defaults[PlayerSeat.south]!],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
        ),
      );

      final result = controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(
          meldCards.map((card) => card.id),
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(
        controller
            .tableMeldsFor(PlayerSeat.south)
            .single
            .cards
            .map((card) => card.label),
        ['10S', 'J(JS)', 'QS'],
      );
    });

    test('ambiguous joker melds require an explicit represented identity', () {
      final joker = HareegCard.joker(deckIndex: 28, jokerIndex: 0);
      final meldCards = [
        _card(CardRank.seven, CardSuit.clubs, 28),
        joker,
        _card(CardRank.seven, CardSuit.diamonds, 28),
      ];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [...meldCards, ...defaults[PlayerSeat.south]!],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
        ),
      );
      final selectedIds = meldCards.map((card) => card.id).toList();

      final options = controller.jokerRepresentationOptionsFor(
        PlayerSeat.south,
        selectedIds,
      );
      final blocked = controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(selectedIds),
      );
      final played = controller.applyAction(
        ClassicHareegActionIds.playMeldWithJokerIdentityActionId(
          cardIds: selectedIds,
          jokerId: joker.id,
          identity: options.first,
        ),
      );

      expect(options.map((identity) => identity.label), ['7H', '7S']);
      expect(blocked.isSuccess, isFalse);
      expect(blocked.message, contains('Choose'));
      expect(played.isSuccess, isTrue);
      expect(
        controller.tableMeldsFor(PlayerSeat.south).single.cards[1].label,
        'J(7H)',
      );
    });

    test('opened players can replace represented table jokers', () {
      final joker = HareegCard.joker(deckIndex: 29, jokerIndex: 0);
      final replacement = _card(CardRank.seven, CardSuit.clubs, 30);
      final meldCards = [
        _card(CardRank.six, CardSuit.clubs, 29),
        joker,
        _card(CardRank.eight, CardSuit.clubs, 29),
      ];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [
              ...meldCards,
              replacement,
              ...defaults[PlayerSeat.south]!,
            ],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
        ),
      );
      controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(
          meldCards.map((card) => card.id),
        ),
      );

      final actionId = controller.jokerReplacementActionIdFor(
        PlayerSeat.south,
        [replacement.id],
      );
      final result = controller.applyAction(actionId!);

      expect(result.isSuccess, isTrue);
      expect(
        controller
            .tableMeldsFor(PlayerSeat.south)
            .single
            .cards
            .map((card) => card.label),
        ['6C', '7C', '8C'],
      );
      expect(
        controller.handFor(PlayerSeat.south).any((card) => card.isJoker),
        isTrue,
      );
    });

    test('selected cover cards can extend an existing meld', () {
      final meldCards = [
        _card(CardRank.five, CardSuit.clubs, 24),
        _card(CardRank.six, CardSuit.clubs, 24),
        _card(CardRank.seven, CardSuit.clubs, 24),
        _card(CardRank.eight, CardSuit.clubs, 24),
      ];
      final covers = [
        _card(CardRank.nine, CardSuit.clubs, 24),
        _card(CardRank.ten, CardSuit.clubs, 24),
      ];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [
              ...meldCards,
              ...covers,
              ...defaults[PlayerSeat.south]!,
            ],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
        ),
      );
      controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(
          meldCards.map((card) => card.id),
        ),
      );

      final coverAction = controller.coverActionIdFor(
        PlayerSeat.south,
        covers.map((card) => card.id).toList(),
      );
      expect(coverAction, isNotNull);

      final result = controller.applyAction(coverAction!);

      expect(result.isSuccess, isTrue);
      final tableMeld = controller.tableMeldsFor(PlayerSeat.south).single;
      expect(tableMeld.cards.map((card) => card.label), [
        '5C',
        '6C',
        '7C',
        '8C',
        '9C',
        '10C',
      ]);
      expect(
        controller.handFor(PlayerSeat.south).map((card) => card.id),
        isNot(containsAll(covers.map((card) => card.id))),
      );
    });

    test('an obvious joker cover receives a represented identity', () {
      final joker = HareegCard.joker(deckIndex: 34, jokerIndex: 0);
      final meldCards = [
        _card(CardRank.ace, CardSuit.clubs, 34),
        _card(CardRank.two, CardSuit.clubs, 34),
        _card(CardRank.three, CardSuit.clubs, 34),
      ];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [
              ...meldCards,
              joker,
              ...defaults[PlayerSeat.south]!,
            ],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
        ),
      );
      controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(
          meldCards.map((card) => card.id),
        ),
      );

      final coverAction = controller.coverActionIdFor(PlayerSeat.south, [
        joker.id,
      ]);
      final result = controller.applyAction(coverAction!);

      expect(result.isSuccess, isTrue);
      expect(
        controller
            .tableMeldsFor(PlayerSeat.south)
            .single
            .cards
            .map((card) => card.label),
        ['AC', '2C', '3C', 'J(4C)'],
      );
    });

    test(
      'table penalty cover discards use blocked-cover prefix and add +3',
      () {
        final meldCards = [
          _card(CardRank.five, CardSuit.clubs, 27),
          _card(CardRank.six, CardSuit.clubs, 27),
          _card(CardRank.seven, CardSuit.clubs, 27),
        ];
        final cover = _card(CardRank.eight, CardSuit.clubs, 27);
        final controller = ClassicHareegGameController.fromSnapshot(
          _snapshot(
            handsBuilder: (defaults) => {
              ...defaults,
              PlayerSeat.south: [
                ...meldCards,
                cover,
                ...defaults[PlayerSeat.south]!,
              ],
            },
            currentSeat: PlayerSeat.south,
            turnPhase: TurnPhase.action,
            openingState: _opened(PlayerSeat.south),
            setup: ClassicHareegSetup.defaults().copyWith(
              rulePreset: RulePreset.tablePenalties,
            ),
          ),
        );
        controller.applyAction(
          ClassicHareegActionIds.playMeldActionId(
            meldCards.map((card) => card.id),
          ),
        );

        final legal = controller.legalActionIdsFor(PlayerSeat.south);
        expect(
          legal,
          contains(
            '${ClassicHareegActionIds.discardBlockedCoverPrefix}${cover.id}',
          ),
        );
        final result = controller.applyAction(
          '${ClassicHareegActionIds.discardBlockedCoverPrefix}${cover.id}',
        );

        expect(result.isSuccess, isTrue);
        expect(controller.scores[PlayerSeat.south], 3);
        expect(controller.topDiscard?.id, cover.id);
      },
    );

    test('pending discard must be part of the played meld', () {
      final pending = _card(CardRank.eight, CardSuit.clubs, 21);
      final otherMeld = [
        _card(CardRank.seven, CardSuit.clubs, 22),
        _card(CardRank.seven, CardSuit.diamonds, 22),
        _card(CardRank.seven, CardSuit.hearts, 22),
      ];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [
              pending,
              ...otherMeld,
              ...defaults[PlayerSeat.south]!,
            ],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          pendingDiscard: pending,
        ),
      );

      final result = controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(
          otherMeld.map((card) => card.id),
        ),
      );

      expect(result.isSuccess, isFalse);
      expect(result.message, contains('picked up discard'));
      expect(controller.pendingDiscard?.id, pending.id);
      expect(controller.tableMeldsFor(PlayerSeat.south), isEmpty);
    });
  });

  group('ClassicHareegGameController CPU integration', () {
    test(
      'CPU strategy only produces legal actions across a full table cycle',
      () {
        final controller = _freshControllerInActionPhase();
        const strategy = ClassicHareegCpuStrategy();

        // Human discards a non-joker.
        final south = controller.handFor(PlayerSeat.south);
        controller.applyAction(
          '${ClassicHareegActionIds.discardPrefix}'
          '${south.firstWhere((c) => !c.isJoker).id}',
        );
        final stockAfterHumanDiscard = controller.stockCount;

        var safety = 0;
        while (controller.currentSeat != PlayerSeat.south && safety < 64) {
          final seat = controller.currentSeat;
          final legal = controller.legalActionIdsFor(seat);
          expect(
            legal,
            isNotEmpty,
            reason: 'CPU seat $seat must have at least one legal action.',
          );

          final intent = strategy.chooseMove(
            CpuTurnSnapshot(
              seat: seat,
              legalActionIds: legal,
              difficulty: controller.setup.cpuDifficulty,
            ),
          );

          expect(
            legal,
            contains(intent.actionId),
            reason: 'CPU strategy must pick from the legal action list.',
          );

          final result = controller.applyAction(intent.actionId);
          expect(
            result.isSuccess,
            isTrue,
            reason:
                'CPU action ${intent.actionId} should be applied. '
                '${result.message}',
          );
          safety += 1;
        }

        expect(controller.currentSeat, PlayerSeat.south);
        expect(controller.turnPhase, TurnPhase.draw);
        expect(controller.stockCount, stockAfterHumanDiscard - 3);
      },
    );
  });

  group('ClassicHareegGameController Fifty and mistake presets', () {
    test('wrong Fifty claims in table penalty mode add +3', () {
      final now = DateTime.utc(2026, 5, 19, 12);
      final discarded = _card(CardRank.nine, CardSuit.clubs, 31);
      final setup = ClassicHareegSetup.defaults().copyWith(
        rulePreset: RulePreset.tablePenalties,
      );
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          setup: setup,
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.east: [
              _card(CardRank.two, CardSuit.hearts, 31),
              _card(CardRank.four, CardSuit.diamonds, 31),
              _card(CardRank.king, CardSuit.spades, 31),
            ],
          },
          discardPile: [discarded],
          currentSeat: PlayerSeat.east,
          turnPhase: TurnPhase.draw,
          savedAt: now,
          fiftyWindowOpenedAt: now,
        ),
        now: () => now,
      );

      expect(
        controller.legalActionIdsFor(PlayerSeat.east),
        contains(ClassicHareegActionIds.claimFifty),
      );

      final result = controller.applyAction(ClassicHareegActionIds.claimFifty);

      expect(result.isSuccess, isTrue);
      expect(controller.scores[PlayerSeat.east], 3);
      expect(controller.isRoundOver, isFalse);
      expect(controller.currentSeat, PlayerSeat.east);
    });

    test('expired Fifty hides claim but keeps normal pickup available', () {
      var now = DateTime.utc(2026, 5, 19, 12);
      final discarded = _card(CardRank.nine, CardSuit.clubs, 32);
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.east: [
              _card(CardRank.seven, CardSuit.clubs, 32),
              _card(CardRank.eight, CardSuit.clubs, 32),
              _card(CardRank.two, CardSuit.hearts, 32),
            ],
          },
          discardPile: [discarded],
          currentSeat: PlayerSeat.east,
          turnPhase: TurnPhase.draw,
          savedAt: now,
          fiftyWindowOpenedAt: now,
        ),
        now: () => now,
      );

      expect(
        controller.legalActionIdsFor(PlayerSeat.east),
        contains(ClassicHareegActionIds.claimFifty),
      );

      now = now.add(const Duration(seconds: 4));
      final legal = controller.legalActionIdsFor(PlayerSeat.east);

      expect(legal, isNot(contains(ClassicHareegActionIds.claimFifty)));
      expect(legal, contains(ClassicHareegActionIds.takeDiscard));
    });

    test('restored expired Fifty window stays expired', () {
      final now = DateTime.utc(2026, 5, 19, 12);
      final discarded = _card(CardRank.nine, CardSuit.clubs, 45);
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.east: [
              _card(CardRank.seven, CardSuit.clubs, 45),
              _card(CardRank.eight, CardSuit.clubs, 45),
              _card(CardRank.two, CardSuit.hearts, 45),
            ],
          },
          discardPile: [discarded],
          currentSeat: PlayerSeat.east,
          turnPhase: TurnPhase.draw,
          savedAt: now,
          fiftyWindowOpenedAt: now.subtract(const Duration(seconds: 5)),
        ),
        now: () => now,
      );

      final legal = controller.legalActionIdsFor(PlayerSeat.east);

      expect(legal, isNot(contains(ClassicHareegActionIds.claimFifty)));
      expect(legal, contains(ClassicHareegActionIds.takeDiscard));
    });

    test('hard table mistakes add +17 and remove the player from round', () {
      final meldCards = [
        _card(CardRank.five, CardSuit.clubs, 33),
        _card(CardRank.six, CardSuit.clubs, 33),
        _card(CardRank.seven, CardSuit.clubs, 33),
      ];
      final cover = _card(CardRank.eight, CardSuit.clubs, 33);
      final setup = ClassicHareegSetup.defaults().copyWith(
        rulePreset: RulePreset.hardTable17,
      );
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          setup: setup,
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [
              ...meldCards,
              cover,
              ...defaults[PlayerSeat.south]!,
            ],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
        ),
      );
      controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(
          meldCards.map((card) => card.id),
        ),
      );

      final result = controller.applyAction(
        '${ClassicHareegActionIds.discardBlockedCoverPrefix}${cover.id}',
      );

      expect(result.isSuccess, isTrue);
      expect(controller.scores[PlayerSeat.south], 17);
      expect(controller.currentSeat, PlayerSeat.east);
      expect(controller.legalActionIdsFor(PlayerSeat.south), isEmpty);
      expect(controller.tableMeldsFor(PlayerSeat.south), hasLength(1));
    });
  });

  group('ClassicHareegGameController round end', () {
    test('placing every remaining card is blocked without a final discard', () {
      final meldCards = [
        _card(CardRank.five, CardSuit.clubs, 39),
        _card(CardRank.six, CardSuit.clubs, 39),
        _card(CardRank.seven, CardSuit.clubs, 39),
      ];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: meldCards,
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
        ),
      );

      final result = controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(
          meldCards.map((card) => card.id),
        ),
      );

      expect(result.isSuccess, isFalse);
      expect(result.message, contains('final discard'));
      expect(controller.isRoundOver, isFalse);
      expect(controller.cardCountFor(PlayerSeat.south), 3);
    });

    test('final discard after playing cards ends the round', () {
      final meldCards = [
        _card(CardRank.five, CardSuit.clubs, 40),
        _card(CardRank.six, CardSuit.clubs, 40),
        _card(CardRank.seven, CardSuit.clubs, 40),
      ];
      final finalDiscard = _card(CardRank.two, CardSuit.hearts, 40);
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [...meldCards, finalDiscard],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
        ),
      );

      final play = controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(
          meldCards.map((card) => card.id),
        ),
      );
      final discard = controller.applyAction(
        '${ClassicHareegActionIds.discardPrefix}${finalDiscard.id}',
      );

      expect(play.isSuccess, isTrue);
      expect(discard.isSuccess, isTrue);
      expect(controller.isRoundOver, isTrue);
      expect(controller.roundOutcome, RoundOutcomeType.normalFinish);
      expect(controller.roundResult?.winner, PlayerSeat.south);
      expect(controller.roundResult?.remainingCardCounts[PlayerSeat.south], 0);
      expect(controller.legalActionIdsFor(PlayerSeat.east), isEmpty);
    });

    test('perfect-hand final discard bypasses opening requirement', () {
      final meldCards = [
        _card(CardRank.five, CardSuit.clubs, 41),
        _card(CardRank.six, CardSuit.clubs, 41),
        _card(CardRank.seven, CardSuit.clubs, 41),
      ];
      final finalDiscard = _card(CardRank.two, CardSuit.hearts, 41);
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [...meldCards, finalDiscard],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
        ),
      );

      controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(
          meldCards.map((card) => card.id),
        ),
      );
      final result = controller.applyAction(
        '${ClassicHareegActionIds.discardPrefix}${finalDiscard.id}',
      );

      expect(result.isSuccess, isTrue);
      expect(controller.isRoundOver, isTrue);
      expect(controller.openingState.hasOpened(PlayerSeat.south), isFalse);
      expect(controller.roundResult?.winner, PlayerSeat.south);
    });

    test('multiple selected melds can satisfy opening together', () {
      final firstMeld = [
        _card(CardRank.ten, CardSuit.clubs, 42),
        _card(CardRank.ten, CardSuit.diamonds, 42),
        _card(CardRank.ten, CardSuit.hearts, 42),
      ];
      final secondMeld = [
        _card(CardRank.nine, CardSuit.clubs, 42),
        _card(CardRank.nine, CardSuit.diamonds, 42),
        _card(CardRank.nine, CardSuit.hearts, 42),
      ];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [
              ...firstMeld,
              ...secondMeld,
              ...defaults[PlayerSeat.south]!,
            ],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
        ),
      );

      final result = controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(
          [...firstMeld, ...secondMeld].map((card) => card.id),
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(controller.openingState.hasOpened(PlayerSeat.south), isTrue);
      expect(controller.tableMeldsFor(PlayerSeat.south), hasLength(2));
      expect(controller.openingState.currentRequirement, 57);
    });

    test('legal meld actions include larger and multi-meld opening plays', () {
      final clubRun = [
        _card(CardRank.seven, CardSuit.clubs, 46),
        _card(CardRank.eight, CardSuit.clubs, 46),
        _card(CardRank.nine, CardSuit.clubs, 46),
        _card(CardRank.ten, CardSuit.clubs, 46),
        _card(CardRank.jack, CardSuit.clubs, 46),
        _card(CardRank.queen, CardSuit.clubs, 46),
      ];
      final tenSet = [
        _card(CardRank.ten, CardSuit.clubs, 47),
        _card(CardRank.ten, CardSuit.diamonds, 47),
        _card(CardRank.ten, CardSuit.hearts, 47),
      ];
      final nineSet = [
        _card(CardRank.nine, CardSuit.clubs, 48),
        _card(CardRank.nine, CardSuit.diamonds, 48),
        _card(CardRank.nine, CardSuit.hearts, 48),
      ];
      final finalDiscard = _card(CardRank.two, CardSuit.spades, 46);
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [...clubRun, ...tenSet, ...nineSet, finalDiscard],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
        ),
      );

      final legal = controller.legalActionIdsFor(PlayerSeat.south);

      expect(
        legal,
        contains(
          ClassicHareegActionIds.playMeldActionId(
            clubRun.map((card) => card.id),
          ),
        ),
      );
      expect(
        legal,
        contains(
          ClassicHareegActionIds.playMeldActionId(
            [...tenSet, ...nineSet].map((card) => card.id),
          ),
        ),
      );
    });

    test('opening can be staged across separate meld plays', () {
      final pickedUpTen = _card(CardRank.ten, CardSuit.diamonds, 44);
      final tenSet = [
        _card(CardRank.ten, CardSuit.clubs, 44),
        _card(CardRank.ten, CardSuit.hearts, 44),
        pickedUpTen,
      ];
      final diamondRun = [
        _card(CardRank.four, CardSuit.diamonds, 44),
        _card(CardRank.five, CardSuit.diamonds, 44),
        _card(CardRank.six, CardSuit.diamonds, 44),
        _card(CardRank.seven, CardSuit.diamonds, 44),
        _card(CardRank.eight, CardSuit.diamonds, 44),
        _card(CardRank.nine, CardSuit.diamonds, 44),
      ];
      final finalDiscard = _card(CardRank.two, CardSuit.spades, 44);
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [...tenSet, ...diamondRun, finalDiscard],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          pendingDiscard: pickedUpTen,
        ),
      );

      final staged = controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(tenSet.map((card) => card.id)),
      );

      expect(staged.isSuccess, isTrue);
      expect(staged.message, contains('Opening 30/51'));
      expect(controller.pendingDiscard, isNull);
      expect(controller.openingState.hasOpened(PlayerSeat.south), isFalse);
      expect(controller.tableMeldsFor(PlayerSeat.south), hasLength(1));
      expect(
        controller
            .legalActionIdsFor(PlayerSeat.south)
            .where((id) => ClassicHareegActionIds.discardCardId(id) != null),
        isEmpty,
      );

      final opened = controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(
          diamondRun.map((card) => card.id),
        ),
      );

      expect(opened.isSuccess, isTrue);
      expect(opened.message, contains('Opened at 69'));
      expect(controller.openingState.hasOpened(PlayerSeat.south), isTrue);
      expect(controller.tableMeldsFor(PlayerSeat.south), hasLength(2));
      expect(
        controller
            .legalActionIdsFor(PlayerSeat.south)
            .any((id) => ClassicHareegActionIds.discardCardId(id) != null),
        isTrue,
      );
    });

    test('incomplete opening melds can be taken back', () {
      final clubRun = [
        _card(CardRank.ten, CardSuit.clubs, 49),
        _card(CardRank.jack, CardSuit.clubs, 49),
        _card(CardRank.queen, CardSuit.clubs, 49),
      ];
      final nineSet = [
        _card(CardRank.nine, CardSuit.clubs, 49),
        _card(CardRank.nine, CardSuit.diamonds, 49),
        _card(CardRank.nine, CardSuit.hearts, 49),
      ];
      final remainingCards = [
        _card(CardRank.two, CardSuit.spades, 49),
        _card(CardRank.three, CardSuit.spades, 49),
      ];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [...clubRun, ...nineSet, ...remainingCards],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: const OpeningState(
            baseRequirement: 51,
            currentRequirement: 60,
            benchmarkOwner: PlayerSeat.north,
            openedSeats: {PlayerSeat.north},
          ),
        ),
      );

      controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(clubRun.map((card) => card.id)),
      );
      final staged = controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(nineSet.map((card) => card.id)),
      );

      expect(staged.message, contains('Opening 57/60'));
      expect(
        controller.controlActionIdsFor(PlayerSeat.south),
        contains(ClassicHareegActionIds.returnOpeningMelds),
      );
      expect(
        controller
            .legalActionIdsFor(PlayerSeat.south)
            .where((id) => id.startsWith(ClassicHareegActionIds.discardPrefix)),
        isEmpty,
      );

      final returned = controller.applyAction(
        ClassicHareegActionIds.returnOpeningMelds,
      );

      expect(returned.isSuccess, isTrue);
      expect(controller.tableMeldsFor(PlayerSeat.south), isEmpty);
      expect(controller.cardCountFor(PlayerSeat.south), 8);
      expect(controller.pendingDiscard, isNull);
      expect(
        controller.controlActionIdsFor(PlayerSeat.south),
        isNot(contains(ClassicHareegActionIds.returnOpeningMelds)),
      );
      expect(
        controller
            .controlActionIdsFor(PlayerSeat.south)
            .where((id) => id.startsWith(ClassicHareegActionIds.discardPrefix)),
        isNotEmpty,
      );
    });

    test('taking back opening melds restores a consumed pending discard', () {
      final pickedUpTen = _card(CardRank.ten, CardSuit.clubs, 50);
      final clubRun = [
        pickedUpTen,
        _card(CardRank.jack, CardSuit.clubs, 50),
        _card(CardRank.queen, CardSuit.clubs, 50),
      ];
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [
              ...clubRun,
              _card(CardRank.two, CardSuit.spades, 50),
            ],
          },
          pendingDiscard: pickedUpTen,
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: const OpeningState(
            baseRequirement: 51,
            currentRequirement: 60,
            benchmarkOwner: PlayerSeat.north,
            openedSeats: {PlayerSeat.north},
          ),
        ),
      );

      controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(clubRun.map((card) => card.id)),
      );
      final returned = controller.applyAction(
        ClassicHareegActionIds.returnOpeningMelds,
      );

      expect(returned.isSuccess, isTrue);
      expect(controller.pendingDiscard?.id, pickedUpTen.id);
      expect(
        controller.controlActionIdsFor(PlayerSeat.south),
        contains(ClassicHareegActionIds.returnPendingDiscard),
      );
    });

    test('next round snapshot keeps scores and active seats', () {
      final meldCards = [
        _card(CardRank.five, CardSuit.clubs, 43),
        _card(CardRank.six, CardSuit.clubs, 43),
        _card(CardRank.seven, CardSuit.clubs, 43),
      ];
      final finalDiscard = _card(CardRank.two, CardSuit.hearts, 43);
      final controller = ClassicHareegGameController.fromSnapshot(
        _snapshot(
          handsBuilder: (defaults) => {
            ...defaults,
            PlayerSeat.south: [...meldCards, finalDiscard],
          },
          currentSeat: PlayerSeat.south,
          turnPhase: TurnPhase.action,
          openingState: _opened(PlayerSeat.south),
          scores: {
            PlayerSeat.south: 4,
            PlayerSeat.east: 5,
            PlayerSeat.north: 6,
            PlayerSeat.west: 7,
          },
          activeSeats: [PlayerSeat.south, PlayerSeat.east, PlayerSeat.north],
        ),
      );
      controller.applyAction(
        ClassicHareegActionIds.playMeldActionId(
          meldCards.map((card) => card.id),
        ),
      );
      controller.applyAction(
        '${ClassicHareegActionIds.discardPrefix}${finalDiscard.id}',
      );

      final next = controller.nextRoundSnapshot();

      expect(next, isNotNull);
      expect(next!.scores[PlayerSeat.south], 3);
      expect(next.activeSeats, [
        PlayerSeat.south,
        PlayerSeat.east,
        PlayerSeat.north,
      ]);
      expect(next.starter, PlayerSeat.south);
      expect(next.roundNumber, 2);
    });

    test('stock exhaustion in draw phase ends the round as a draw', () {
      // Build a snapshot where stock is empty and South is in draw phase
      // because West just discarded. Stock exhaustion + no finish logic
      // ends the round as a draw under the rules engine.
      final base = _freshSnapshot();
      final stockToHand = base.stock.toList();
      final exhausted = ClassicHareegMatchSnapshot(
        setup: base.setup,
        hands: {
          ...base.hands,
          PlayerSeat.south: [...base.hands[PlayerSeat.south]!, ...stockToHand],
        },
        stock: const [],
        discardPile: [
          // Place at least one card so we can identify previous-seat.
          // Use any non-joker from East's hand.
          base.hands[PlayerSeat.east]!.firstWhere((c) => !c.isJoker),
        ],
        starter: base.starter,
        currentSeat: PlayerSeat.south,
        turnPhase: TurnPhase.draw,
        savedAt: base.savedAt,
      );

      final controller = ClassicHareegGameController.fromSnapshot(exhausted);

      expect(controller.isRoundOver, isTrue);
      expect(controller.roundOutcome, RoundOutcomeType.draw);
      expect(controller.legalActionIdsFor(PlayerSeat.south), isEmpty);
    });
  });
}

ClassicHareegGameController _freshControllerInActionPhase() {
  return ClassicHareegGameController.fromRound(
    ClassicHareegRound.deal(setup: ClassicHareegSetup.defaults(), seed: 5),
  );
}

ClassicHareegMatchSnapshot _freshSnapshot() {
  final round = ClassicHareegRound.deal(
    setup: ClassicHareegSetup.defaults(),
    seed: 5,
  );
  return ClassicHareegMatchSnapshot(
    setup: round.setup,
    hands: round.hands,
    stock: round.stock,
    discardPile: round.discardPile,
    starter: round.starter,
    currentSeat: round.currentSeat,
    turnPhase: round.turnPhase,
    savedAt: DateTime.utc(2026, 5, 19),
  );
}

ClassicHareegMatchSnapshot _snapshot({
  Map<PlayerSeat, List<HareegCard>> Function(
    Map<PlayerSeat, List<HareegCard>> defaults,
  )?
  handsBuilder,
  PlayerSeat currentSeat = PlayerSeat.south,
  TurnPhase turnPhase = TurnPhase.action,
  HareegCard? pendingDiscard,
  OpeningState? openingState,
  Map<PlayerSeat, int>? scores,
  List<PlayerSeat>? activeSeats,
  ClassicHareegSetup? setup,
  List<HareegCard>? discardPile,
  List<HareegCard>? stock,
  DateTime? savedAt,
  DateTime? fiftyWindowOpenedAt,
}) {
  final effectiveSetup = setup ?? ClassicHareegSetup.defaults();
  final round = ClassicHareegRound.deal(setup: effectiveSetup, seed: 5);
  final defaults = <PlayerSeat, List<HareegCard>>{
    for (final entry in round.hands.entries)
      entry.key: List<HareegCard>.of(entry.value),
  };
  final hands = handsBuilder == null ? defaults : handsBuilder(defaults);
  return ClassicHareegMatchSnapshot(
    setup: effectiveSetup,
    hands: hands,
    stock: stock ?? round.stock,
    discardPile: discardPile ?? round.discardPile,
    starter: round.starter,
    currentSeat: currentSeat,
    turnPhase: turnPhase,
    pendingDiscard: pendingDiscard,
    openingState: openingState,
    scores: scores ?? const {},
    activeSeats:
        activeSeats ??
        const [
          PlayerSeat.south,
          PlayerSeat.east,
          PlayerSeat.north,
          PlayerSeat.west,
        ],
    fiftyWindowOpenedAt: fiftyWindowOpenedAt,
    savedAt: savedAt ?? DateTime.utc(2026, 5, 19),
  );
}

OpeningState _opened(PlayerSeat seat) {
  return ClassicHareegOpeningRules.applyOpening(
    state: OpeningState.initial(51),
    seat: seat,
    melds: [const PlacedMeld(cards: [], valueSnapshot: 51)],
  );
}

HareegCard _card(CardRank rank, CardSuit suit, int deckIndex) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);
}
