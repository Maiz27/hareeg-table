import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/data/persistence/preferences_repository.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/replay/replay_reconstruction.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/features/game_table/table_session_config.dart';
import 'package:hareeg_table/ui/features/game_table/views/game_table_screen.dart';
import 'package:hareeg_table/ui/features/game_table/widgets/physical_table_playfield.dart';
import 'package:hareeg_table/ui/features/game_table/widgets/table_center_area.dart';
import 'package:hareeg_table/ui/features/replay/views/branch_sandbox_host.dart';

/// Shared fixtures for the branch-sandbox widget tests.
///
/// The sandbox is driven from a **hand-built [ReplayFrame]** rather than from a
/// reconstructed match. That is deliberate: driving a full match to a chosen
/// position takes the better part of a minute and gives no control over the
/// hand, the seat on turn, the scores or the Fifty window — the four things
/// these tests are actually about. `ReplayFrame` is an ordinary value, so
/// building one directly states the position under test instead of hunting for
/// a seed that happens to produce it.
///
/// The one thing this cannot prove is that the real replay launch path reaches
/// the sandbox at all. That is covered separately, through `MatchReplayScreen`
/// over a real transcript, and is disclosed as such.

/// A physical card outside the dealt deck's index range.
HareegCard branchCard(CardRank rank, CardSuit suit) =>
    HareegCard.standard(rank: rank, suit: suit, deckIndex: 100);

/// South holds exactly one meld plus one final discard.
///
/// Playing the meld and discarding the last card finishes the round outright,
/// which is the only route to a genuine round crossing: nothing concludes a
/// round on load except human elimination.
List<HareegCard> get branchFinishingHand => [
  branchCard(CardRank.seven, CardSuit.clubs),
  branchCard(CardRank.eight, CardSuit.clubs),
  branchCard(CardRank.nine, CardSuit.clubs),
  branchCard(CardRank.two, CardSuit.spades),
];

/// An already-opened state, so south may finish without meeting the opening
/// requirement first.
OpeningState branchOpened(PlayerSeat seat) {
  return ClassicHareegOpeningRules.applyOpening(
    state: OpeningState.initial(51),
    seat: seat,
    melds: [const PlacedMeld(cards: [], valueSnapshot: 51)],
  );
}

/// Builds the match state a sandbox will branch from.
ClassicHareegMatchSnapshot branchSnapshot({
  List<HareegCard>? southHand,
  PlayerSeat currentSeat = PlayerSeat.south,
  TurnPhase turnPhase = TurnPhase.action,
  OpeningState? openingState,
  Map<PlayerSeat, int> scores = const {},
  List<PlayerSeat> removedSeats = const [],
  int roundNumber = 1,
  List<HareegCard> discardPile = const [],
  DateTime? fiftyWindowOpenedAt,
  PlayerSeat? fiftyWindowDiscarder,
  DateTime? savedAt,
}) {
  final setup = ClassicHareegSetup.defaults();
  final dealt = ClassicHareegRound.deal(setup: setup, seed: 3);
  return ClassicHareegMatchSnapshot(
    setup: setup,
    hands: southHand == null
        ? dealt.hands
        : {...dealt.hands, PlayerSeat.south: southHand},
    stock: dealt.stock,
    // A Fifty window only restores over a non-empty pile, so a test that
    // wants one has to put a card on it.
    discardPile: discardPile,
    starter: dealt.starter,
    currentSeat: currentSeat,
    turnPhase: turnPhase,
    openingState: openingState,
    scores: scores,
    activeSeats: const [
      PlayerSeat.south,
      PlayerSeat.east,
      PlayerSeat.north,
      PlayerSeat.west,
    ],
    removedSeats: removedSeats,
    roundNumber: roundNumber,
    // A window restores when the pile is non-empty and the seat is on draw,
    // so these two are what turn a plain resume into an open Fifty offer.
    fiftyWindowOpenedAt: fiftyWindowOpenedAt,
    fiftyWindowDiscarder: fiftyWindowDiscarder,
    savedAt: savedAt ?? DateTime.utc(2026, 6, 1),
  );
}

/// Wraps [snapshot] as the replay position a branch starts from.
ReplayFrame branchFrame(
  ClassicHareegMatchSnapshot snapshot, {
  int index = 3,
  ReplayFrameKind kind = ReplayFrameKind.actionApplied,
  DateTime? clock,
  PlayerSeat? matchWinner,
}) {
  return ReplayFrame(
    index: index,
    kind: kind,
    roundNumber: snapshot.roundNumber,
    snapshot: snapshot,
    clock: clock ?? snapshot.savedAt,
    matchWinner: matchWinner,
  );
}

/// A tickable clock, so a rebased Fifty window can be advanced rather than
/// slept through.
class BranchTestClock {
  BranchTestClock(this._now);

  DateTime _now;

  DateTime call() => _now;

  /// Moves the sandbox clock forward.
  void advance(Duration by) => _now = _now.add(by);
}

/// Mounts a sandbox host over [frame].
Widget branchSandboxApp({
  required ReplayFrame frame,
  required BranchVisibility visibility,
  required bool coachEligible,
  ReplayFrame? nextFrame,
  ValueChanged<TableAppliedAction>? onAppliedAction,
  DateTime Function()? clock,
  GamePreferences? preferences,
  AppStrings strings = AppStrings.english,
  Key? hostKey,
}) {
  return AppStringsScope(
    strings: strings,
    child: Directionality(
      textDirection: strings.textDirection,
      child: MaterialApp(
        home: BranchSandboxHost(
          // A fresh key per call by default. Pumping a second sandbox into the
          // same test would otherwise reuse the first one's `State` — same
          // widget type, same position — and carry its session, divergence and
          // controller into a run that is supposed to start clean.
          key: hostKey ?? UniqueKey(),
          frame: frame,
          // Null by default: these hand-built frames are mid-round positions
          // with no recorded successor, which is exactly the shape a
          // synthetic fixture can state honestly. Round-boundary behaviour
          // needs a real recorded successor and is proven against the actual
          // seed-13 timeline instead, never here.
          nextFrame: nextFrame,
          onAppliedAction: onAppliedAction,
          visibility: visibility,
          coachEligible: coachEligible,
          preferences: preferences ?? GamePreferences.defaults(),
          clock: clock,
        ),
      ),
    ),
  );
}

/// Sizes the test view to a landscape table and settles the sandbox.
Future<void> pumpBranchSandbox(
  WidgetTester tester,
  Widget app, {
  Size size = const Size(1688, 780),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle(const Duration(seconds: 30));
}

/// The south-hand drag target for [card].
///
/// Keyed by card id rather than found by semantics label. In study mode the
/// opponents' hands are face up too, so a label finder's `.first` can land on
/// an opponent's copy of the same card — which is how a visibility test can
/// silently stop driving south at all.
Finder branchSouthCard(HareegCard card) =>
    find.byKey(ValueKey('south-hand-drag-${card.id}'));

/// Plays south's meld and discards the last card, finishing the round.
Future<void> branchFinishRound(WidgetTester tester) async {
  for (final card in branchFinishingHand.take(3)) {
    final rect = tester.getRect(branchSouthCard(card));
    await tester.tapAt(Offset(rect.left + 6, rect.center.dy));
    await tester.pump();
  }
  await tester.pumpAndSettle();
  await tester.tap(find.text('Play meld'));
  await tester.pumpAndSettle();
  await branchDiscard(tester, branchFinishingHand.last);
}

/// The sandbox table currently mounted.
PhysicalTablePlayfield branchPlayfield(WidgetTester tester) =>
    tester.widget<PhysicalTablePlayfield>(find.byType(PhysicalTablePlayfield));

/// Plays one south action through the affordances the table publishes, and
/// only where the table says they are legal — a real applied action rather
/// than a bypass of the rules. Returns false when a CPU owns the turn.
///
/// Whichever of draw, pickup or discard is legal depends on where the branch
/// point left the turn, so all three are tried in order. It never melds: an
/// unmelded south hand is what makes a round end in a penalty large enough to
/// decide a match.
Future<bool> branchPlayOneSouthAction(WidgetTester tester) async {
  final table = branchPlayfield(tester);
  if (!table.isHumanTurn) {
    return false;
  }
  if (table.canDrawStock) {
    table.onDrawStock();
  } else if (table.canTakeDiscard) {
    table.onTakeDiscard();
  } else {
    final playable = table.southCards.where(table.canDiscardCard).toList();
    expect(
      playable,
      isNotEmpty,
      reason:
          'south is on turn with no legal move, so the sandbox cannot be '
          'driven at all',
    );
    table.onDiscardCard(playable.first);
  }
  await tester.pumpAndSettle(const Duration(seconds: 90));
  return true;
}

/// Settles until south owns the turn again, so a turn-gated surface is checked
/// when it is meant to be showing rather than between CPU steps.
Future<void> branchSettleToSouthTurn(WidgetTester tester) async {
  for (var i = 0; i < 12 && !branchPlayfield(tester).isHumanTurn; i++) {
    await tester.pumpAndSettle(const Duration(seconds: 30));
  }
  expect(
    branchPlayfield(tester).isHumanTurn,
    isTrue,
    reason: 'the sandbox never handed the turn back to south',
  );
}

/// Draws from stock, when south's turn opens on the draw phase.
Future<void> branchDrawStock(WidgetTester tester) async {
  await tester.tap(find.byType(TableStockPile));
  await tester.pumpAndSettle(const Duration(seconds: 30));
}

/// Drags one south-hand card onto the discard pile.
Future<void> branchDiscard(WidgetTester tester, HareegCard card) async {
  final rect = tester.getRect(branchSouthCard(card));
  final grip = Offset(rect.left + 6, rect.center.dy);
  final target = tester.getCenter(
    find.byKey(const ValueKey('discard-pile-drop-target')),
  );
  await tester.dragFrom(grip, target - grip);
  await tester.pumpAndSettle(const Duration(seconds: 30));
}
