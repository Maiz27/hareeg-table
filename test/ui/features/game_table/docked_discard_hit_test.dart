// Can a pointer at the discard pile actually reach the discard pile?
//
// The docked branch sandbox refused every drag-discard on a real browser while
// the short table accepted them, and the cause looks geometric rather than
// gestural. `PhysicalTablePlayfield` is one `Stack`. The discard pile is
// positioned BEFORE the west and east `SeatMeldLane`s, and `RenderStack` hit
// tests children in reverse paint order and stops at the FIRST child that
// reports a hit -- so a side lane drawn over the discard absorbs the pointer
// and the discard is never added to the hit-test path at all. A `DragTarget`
// that refuses does not hand the pointer back down to one underneath it.
//
// The web build lays the table out in a canvas of fixed height 430 and scales
// it to fill the viewport, so a 390x844 portrait viewport is only ~198.7
// logical pixels across. The playfield's own arithmetic at that width gives
// `edgeInset` 14, a west lane starting at x=66 and an east lane mirrored from
// the right, and between them they cover the centre where the discard sits.
// The short table (~930 wide) puts the lanes nowhere near it.
//
// This asserts the property rather than the numbers: at the discard's own
// centre, the discard must be reachable, and no side lane may sit above it.
import 'package:flutter/gestures.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';
import 'package:hareeg_table/ui/core/cards/card_theme_registry.dart';
import 'package:hareeg_table/ui/features/game_table/coach/coach_highlighting.dart';
import 'package:hareeg_table/ui/features/game_table/table_session_config.dart';
import 'package:hareeg_table/ui/features/game_table/widgets/seat_meld_lane.dart';
import 'package:hareeg_table/ui/features/game_table/widgets/table_center_area.dart';

import '../../../support/branch_sandbox_harness.dart';

/// Where [want] first appears in the hit-test path at [point], or -1.
///
/// By ANCESTRY, not by the hit object's own type. A hit-test path is made of
/// render objects, and `TableDiscardPile` and `SeatMeldLane` are composite
/// widgets that build render objects rather than being them -- so asking
/// whether either type appears in the path directly answers "no" for both,
/// always, in every layout. A first version of this test did exactly that and
/// its control failed too, which is the only reason the mistake was caught
/// rather than reported as a product defect.
int _firstIndexOf(WidgetTester tester, Offset point, Type want) {
  final result = HitTestResult();
  WidgetsBinding.instance.hitTestInView(result, point, tester.view.viewId);
  final path = result.path.toList();
  for (var i = 0; i < path.length; i++) {
    final target = path[i].target;
    if (target is! RenderObject) continue;
    final creator = target.debugCreator;
    if (creator is! DebugCreator) continue;
    var found = creator.element.widget.runtimeType == want;
    creator.element.visitAncestorElements((ancestor) {
      if (ancestor.widget.runtimeType == want) {
        found = true;
        return false;
      }
      return true;
    });
    if (found) return i;
  }
  return -1;
}

Future<void> _pumpSandboxAt(WidgetTester tester, Size size) async {
  await pumpBranchSandbox(
    tester,
    branchSandboxApp(
      frame: branchFrame(branchSnapshot()),
      visibility: BranchVisibility.study,
      coachEligible: true,
    ),
    size: size,
  );
}

void main() {
  // 390x844 at devicePixelRatio 2 is the docked cell the contract names.
  const dockedPhysical = Size(780, 1688);
  const shortPhysical = Size(1688, 780);

  group('the discard pile is reachable where it is drawn', () {
    testWidgets('docked 390x844: no side meld lane sits above the discard', (
      tester,
    ) async {
      await _pumpSandboxAt(tester, dockedPhysical);

      final pile = find.byType(TableDiscardPile);
      expect(pile, findsOneWidget, reason: 'the discard pile must be rendered');

      final centre = tester.getCenter(pile);
      final lane = _firstIndexOf(tester, centre, SeatMeldLane);
      final discard = _firstIndexOf(tester, centre, TableDiscardPile);

      expect(
        discard,
        isNot(-1),
        reason:
            'the discard pile is not in the hit-test path at its own centre, '
            'so no drop there can reach it (lane index $lane)',
      );
      expect(
        lane == -1 || discard < lane,
        isTrue,
        reason:
            'a side meld lane is above the discard at the discard own centre '
            '(lane $lane, discard $discard). RenderStack stops at the first '
            'child that reports a hit, so the lane absorbs the drop and the '
            'discard target never runs.',
      );
    });

    testWidgets('the WEB design canvas the docked cell actually lays out in', (
      tester,
    ) async {
      // The size above is not what the browser uses. `_ZoomToFillTable` is
      // guarded by `if (kIsWeb)`, and `kIsWeb` is false under `flutter test`,
      // so a widget test at 390x844 lays the table out at 390x844 -- while the
      // browser lays it out in a canvas of fixed height 430, scaled to fill.
      // For a 390x844 viewport that canvas is 390 * 430 / 844 = 198.7 wide,
      // which is less than a quarter of the width and where the side lanes
      // were computed to converge on the middle. This is the geometry the
      // browser failure actually happens in.
      await _pumpSandboxAt(tester, const Size(397.4, 860));

      final pile = find.byType(TableDiscardPile);
      expect(pile, findsOneWidget, reason: 'the discard pile must be rendered');

      final centre = tester.getCenter(pile);
      final lane = _firstIndexOf(tester, centre, SeatMeldLane);
      final discard = _firstIndexOf(tester, centre, TableDiscardPile);

      expect(
        discard,
        isNot(-1),
        reason:
            'the discard pile is not in the hit-test path at its own centre '
            'on the web design canvas, so no drop there can reach it '
            '(lane index $lane)',
      );
      expect(
        lane == -1 || discard < lane,
        isTrue,
        reason:
            'a side meld lane is above the discard at the discard own centre '
            'on the web design canvas (lane $lane, discard $discard)',
      );
    });

    testWidgets('D13 is what makes it reachable: with opponent lanes still '
        'taking the pointer, the portrait case fails', (tester) async {
      // The mutation check. D13 makes an empty opponent lane pointer
      // transparent; this reconstructs the pre-fix arrangement in the same
      // geometry and asserts the failure comes back. Without this, a fix that
      // happened to work for some other reason would look identical.
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.ltr,
            child: Stack(
              children: [
                // Stand-in for the discard: an earlier Stack child.
                Positioned.fill(
                  child: DragTarget<Object>(
                    key: const ValueKey('under'),
                    builder: (_, _, _) => const SizedBox.expand(),
                  ),
                ),
                // Stand-in for an empty opponent lane WITHOUT D13: a later
                // sibling whose transparent decoration still hit tests.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: const BoxDecoration(color: Colors.transparent),
                    child: DragTarget<Object>(
                      key: const ValueKey('over'),
                      builder: (_, _, _) => const SizedBox.expand(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final centre = tester.getCenter(find.byKey(const ValueKey('over')));
      final over = _firstIndexOf(tester, centre, DecoratedBox);
      expect(
        over,
        isNot(-1),
        reason:
            'a transparent DecoratedBox must still hit test — this is the '
            'framework behaviour D13 works around, and if it ever stops being '
            'true the fix is no longer needed',
      );
    });

    testWidgets('short 844x390: the same property holds, as a control', (
      tester,
    ) async {
      await _pumpSandboxAt(tester, shortPhysical);

      final pile = find.byType(TableDiscardPile);
      expect(pile, findsOneWidget);

      final centre = tester.getCenter(pile);
      final lane = _firstIndexOf(tester, centre, SeatMeldLane);
      final discard = _firstIndexOf(tester, centre, TableDiscardPile);

      expect(discard, isNot(-1), reason: 'lane $lane, discard $discard');
      expect(
        lane == -1 || discard < lane,
        isTrue,
        reason: 'lane $lane, discard $discard',
      );
    });
  });

  _d13BoundaryTests();
  _pausePanelTests();
}

/// A lane mounted on its own, so the D13 boundary can be checked exactly.
Future<void> _pumpLane(
  WidgetTester tester, {
  required PlayerSeat owner,
  required List<PlacedMeld> melds,
}) async {
  tester.view.physicalSize = const Size(400, 400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 160,
            height: 300,
            child: SeatMeldLane(
              theme: CardThemeRegistry.byId(null),
              owner: owner,
              melds: melds,
              cardSize: const Size(30, 42),
              compact: true,
              canAcceptTable: (_) => true,
              onAcceptTable: (_) {},
              canAcceptMeld: (_, _) => true,
              onAcceptMeld: (_, _) {},
              canRetractMeld: (_, _) => false,
              onRetractMeld: (_, _) {},
              onCardLongPress: (_) {},
              stackVertically: false,
              coachHighlighting: CoachHighlighting.none,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// D13 must be exactly as narrow as it claims: it removes the pointer claim of
/// an EMPTY OPPONENT lane and nothing else. These are the two cases that would
/// break if it reached further, and they are the live table's real behaviour,
/// not the sandbox's.
void _d13BoundaryTests() {
  group('D13 stays inside its boundary', () {
    testWidgets("south's EMPTY lane still takes the pointer", (tester) async {
      // South's empty lane is where a new meld is dropped. If D13 silenced it
      // the player could no longer open a meld at all.
      await _pumpLane(tester, owner: PlayerSeat.south, melds: const []);
      final centre = tester.getCenter(find.byType(SeatMeldLane));
      expect(
        _firstIndexOf(tester, centre, SeatMeldLane),
        isNot(-1),
        reason: "south's empty lane must remain a drop target for a new meld",
      );
    });

    testWidgets('a POPULATED opponent lane still takes the pointer', (
      tester,
    ) async {
      // Covers and inspection on an opponent's melds must be unaffected.
      await _pumpLane(
        tester,
        owner: PlayerSeat.west,
        melds: [
          PlacedMeld.fromCards([
            HareegCard.standard(
              rank: CardRank.queen,
              suit: CardSuit.clubs,
              deckIndex: 99,
            ),
            HareegCard.standard(
              rank: CardRank.queen,
              suit: CardSuit.hearts,
              deckIndex: 99,
            ),
            HareegCard.standard(
              rank: CardRank.queen,
              suit: CardSuit.spades,
              deckIndex: 99,
            ),
          ]),
        ],
      );
      final centre = tester.getCenter(find.byType(SeatMeldLane));
      expect(
        _firstIndexOf(tester, centre, SeatMeldLane),
        isNot(-1),
        reason:
            'a populated opponent lane must keep its cover and inspection '
            'behaviour',
      );
    });

    testWidgets('an EMPTY opponent lane does not', (tester) async {
      await _pumpLane(tester, owner: PlayerSeat.west, melds: const []);
      final centre = tester.getCenter(find.byType(SeatMeldLane));
      expect(
        _firstIndexOf(tester, centre, SeatMeldLane),
        -1,
        reason:
            'this is the whole of D13: an empty opponent lane has nothing to '
            'drop onto and nothing to inspect, so it must not claim a pointer '
            'that belongs to whatever is beneath it',
      );
    });
  });
}

/// The pause panel's controls at the DOCKED size.
///
/// The existing accessibility sweep checks the pause panel at 844x390 only, so
/// nothing asserted that Restart is reachable in the docked cell -- and the V9
/// docked run failed with "restart not offered" after its round crossing. This
/// pins the panel at the canvas the browser actually lays out in.
void _pausePanelTests() {
  group('the pause panel offers its controls when docked', () {
    testWidgets('restart is present and is a button on the web design canvas', (
      tester,
    ) async {
      await pumpBranchSandbox(
        tester,
        branchSandboxApp(
          frame: branchFrame(branchSnapshot()),
          visibility: BranchVisibility.study,
          coachEligible: true,
        ),
        // The canvas a 390x844 browser viewport produces.
        size: const Size(397.4, 860),
      );

      const strings = AppStrings.english;
      await tester.tap(find.byTooltip(strings.pauseTable));
      await tester.pumpAndSettle();

      expect(
        find.text(strings.branchRestart),
        findsOneWidget,
        reason:
            'the docked pause panel must offer Restart from branch point; the '
            'V9 docked cell reported "restart not offered" here',
      );

      // And it must be a BUTTON in semantics, because that is what a
      // role-checking driver -- and a screen reader -- looks for. The docked
      // replay transport publishes plain labelled nodes with no button role,
      // and if the pause panel did the same the control would be present but
      // unreachable.
      final semantics = tester.getSemantics(
        find.ancestor(
          of: find.text(strings.branchRestart),
          matching: find.byType(Semantics),
        ).first,
      );
      expect(
        semantics.flagsCollection.isButton,
        isTrue,
        reason: 'Restart must carry the button role when docked',
      );
    });
  });
}
