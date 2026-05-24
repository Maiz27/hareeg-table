import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/app/app_routes.dart';
import 'package:hareeg_table/app/hareeg_table_app.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';
import 'package:hareeg_table/ui/core/cards/showcase_card_fan.dart';

import '../../../support/test_fixtures.dart';

/// L2 regression for HT-28: the meld-suggestion chip rack must appear as the
/// human's meld-confirm surface for every strictness tier that BLOCKS illegal
/// moves (coaching + standard). Before HT-28 the rack was gated on
/// `strictness.showsMeldPicker` which was true only for `coaching`, so users
/// migrated from the legacy `tableAids: 'standard'` setting lost the rack
/// silently — the regression that brought the bug report in.
void main() {
  // Home screen runs a looping idle animation; pin it so pumpAndSettle does
  // not hang waiting on the loop.
  ShowcaseCardFan.disableLoopingMotionForTesting = true;

  group('Meld confirm flow', () {
    testWidgets(
      'standard tier surfaces the meld-suggestion chip for a valid selection '
      'and tapping it plays the meld',
      (tester) async {
        final diamondRun = [
          _card(CardRank.eight, CardSuit.diamonds, 80),
          _card(CardRank.nine, CardSuit.diamonds, 80),
          _card(CardRank.ten, CardSuit.diamonds, 80),
        ];
        final preferences = MemoryPreferencesRepository();
        final repository = await _openTable(
          tester,
          southHand: [
            ...diamondRun,
            _card(CardRank.two, CardSuit.clubs, 80),
          ],
          strictness: TableStrictness.standard,
          preferencesRepository: preferences,
        );

        await tester.tap(
          find.bySemanticsLabel('Eight of Diamonds').first,
          warnIfMissed: false,
        );
        await tester.tap(
          find.bySemanticsLabel('Nine of Diamonds').first,
          warnIfMissed: false,
        );
        await tester.tap(
          find.bySemanticsLabel('Ten of Diamonds').first,
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        final actionId = ClassicHareegActionIds.playMeldActionId(
          diamondRun.map((card) => card.id),
        );
        final chip = find.byKey(ValueKey('meld-suggestion-$actionId'));

        // (a) The chip rack — the live confirm surface — must render for a
        // valid 3-card selection in standard tier. Prior to the fix this
        // failed (rack gated on coaching-only).
        expect(chip, findsOneWidget);

        // (b) The bottom-right rail CTA is enabled in parallel and points at
        // the same play. We verify via its tooltip — the tooltip is only
        // attached when the CTA is tappable (see `_MeldCtaButton.isCta`).
        expect(find.byTooltip('Play selected meld'), findsOneWidget);

        // (c) Tapping the chip plays the meld: the south hand shrinks by 3
        // and the played run is recorded on the south meld lane. Read the
        // persisted snapshot — the persistence planner saves after every
        // applied action.
        await tester.tap(chip);
        await tester.pumpAndSettle();

        final saved = repository.saved;
        expect(saved, isNotNull);
        // South started with the diamond run plus a single discard card.
        // After the meld plays, only the discard card remains in hand.
        expect(saved!.hands[PlayerSeat.south]?.length, 1);
        final southMelds = saved.tableMelds[PlayerSeat.south] ?? const [];
        expect(southMelds, hasLength(1));
        expect(
          southMelds.single.cards.map((card) => card.id).toSet(),
          diamondRun.map((card) => card.id).toSet(),
        );
      },
    );
  });
}

Future<MemoryMatchRepository> _openTable(
  WidgetTester tester, {
  required List<HareegCard> southHand,
  TableStrictness strictness = TableStrictness.standard,
  MemoryPreferencesRepository? preferencesRepository,
}) async {
  final setup = ClassicHareegSetup.defaults().copyWith(
    tableStrictness: strictness,
  );
  final repository = MemoryMatchRepository(
    saved: _savedSnapshot(
      southHand: southHand,
      setup: setup,
      openingState: _opened(PlayerSeat.south, setup.openingRequirement),
    ),
  );
  await tester.pumpWidget(
    HareegTableApp(
      preferencesRepository:
          preferencesRepository ?? MemoryPreferencesRepository(),
      matchRepository: repository,
      initialRouteOverride: AppRoutes.home,
    ),
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Continue'));
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
  return repository;
}

ClassicHareegMatchSnapshot _savedSnapshot({
  required List<HareegCard> southHand,
  required ClassicHareegSetup setup,
  required OpeningState openingState,
}) {
  final dealt = ClassicHareegRound.deal(setup: setup, seed: 3);
  final hands = {...dealt.hands, PlayerSeat.south: southHand};
  return ClassicHareegMatchSnapshot(
    setup: setup,
    hands: hands,
    stock: dealt.stock,
    discardPile: dealt.discardPile,
    starter: dealt.starter,
    currentSeat: PlayerSeat.south,
    turnPhase: TurnPhase.action,
    openingState: openingState,
    activeSeats: const [
      PlayerSeat.south,
      PlayerSeat.east,
      PlayerSeat.north,
      PlayerSeat.west,
    ],
    roundNumber: 1,
    savedAt: DateTime.utc(2026, 5, 18),
  );
}

OpeningState _opened(PlayerSeat seat, int requirement) {
  return ClassicHareegOpeningRules.applyOpening(
    state: OpeningState.initial(requirement),
    seat: seat,
    melds: [PlacedMeld(cards: const [], valueSnapshot: requirement)],
  );
}

HareegCard _card(CardRank rank, CardSuit suit, int deckIndex) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);
}
