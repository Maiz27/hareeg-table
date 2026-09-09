import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/core/cards/card_theme_registry.dart';
import 'package:hareeg_table/ui/features/game_table/table_mode.dart';
import 'package:hareeg_table/ui/features/replay/replay_hud_layout.dart';
import 'package:hareeg_table/ui/features/replay/widgets/review_table_playfield.dart';

import '../../../support/max_content_table_fixture.dart';

/// Guards the one thing that makes the projection legitimate.
///
/// [ReplayTableGeometry] is **duplicated deterministic math, not a shared
/// implementation function**. Routing and rail placement have to know where
/// every protected surface will land before the table is laid out, and the
/// contract pins `physical_table_playfield.dart` to the `showSouthControls`
/// change alone, so the geometry is restated rather than exported.
///
/// Duplication is only safe while it is guarded. Every case below renders the
/// real table on the maximum-content fixture and compares each projected
/// rectangle against the **actual** rendered `RenderBox`. If the table's math
/// ever moves, these fail — and they fail *before* any overlap or hit-test
/// claim can be built on a stale projection. Those claims always use rendered
/// rects, never this projection.
///
/// **Any change to the playfield's compact selection, inset clamps, rail
/// centring or lane arithmetic must update `ReplayTableGeometry` in the same
/// change, or this suite fails.**

Finder _byTypeName(String name) =>
    find.byWidgetPredicate((w) => w.runtimeType.toString() == name);

bool _isCardKey(Widget widget) {
  final key = widget.key;
  return key is ValueKey<String> && key.value.contains('-deck-');
}

/// Every rendered card rectangle under [region], in body-local coordinates.
List<Rect> _cardsIn(Element region, Offset origin) {
  final rects = <Rect>[];
  void walk(Element element) {
    if (_isCardKey(element.widget)) {
      final ro = element.renderObject;
      if (ro is RenderBox && ro.attached && ro.hasSize && !ro.size.isEmpty) {
        rects.add((ro.localToGlobal(Offset.zero) - origin) & ro.size);
      }
    }
    element.visitChildren(walk);
  }

  walk(region);
  return rects;
}

Rect _union(List<Rect> rects) => rects.reduce((a, b) => a.expandToInclude(b));

/// Renders the passive table filling exactly [body] and returns the body-local
/// rect reader.
Future<({Offset origin, Rect Function(String) box})> _render(
  WidgetTester tester,
  Size body,
  AppStrings strings,
) async {
  tester.view.physicalSize = body;
  tester.view.devicePixelRatio = 1.0;

  final rootKey = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      home: AppStringsScope(
        strings: strings,
        child: Directionality(
          textDirection: strings.textDirection,
          child: Material(
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                key: rootKey,
                width: body.width,
                height: body.height,
                // showSouthControls:false is what replay renders, and it is the
                // case that matters: hiding the controls must not move the hand.
                child: ReviewTablePlayfield(
                  mode: TableMode.replayReview,
                  snapshot: maximumContentSnapshot(),
                  theme: CardThemeRegistry.byId(null),
                  fiftySecondsRemaining: null,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final root = rootKey.currentContext!.findRenderObject()! as RenderBox;
  final origin = root.localToGlobal(Offset.zero);
  return (
    origin: origin,
    box: (String typeName) {
      final finder = _byTypeName(typeName);
      expect(finder, findsWidgets, reason: 'no $typeName rendered at $body');
      return tester.getRect(finder.first).shift(-origin);
    },
  );
}

void _expectRect(Rect rendered, Rect projected, String what) {
  expect(rendered.left, closeTo(projected.left, 0.01), reason: '$what left');
  expect(rendered.top, closeTo(projected.top, 0.01), reason: '$what top');
  expect(rendered.right, closeTo(projected.right, 0.01), reason: '$what right');
  expect(
    rendered.bottom,
    closeTo(projected.bottom, 0.01),
    reason: '$what bottom',
  );
}

Future<void> _expectParity(
  WidgetTester tester,
  Size body,
  AppStrings strings,
) async {
  final rendered = await _render(tester, body, strings);
  final projected = ReplayTableGeometry.project(body);
  final label = '${body.width}x${body.height} ${strings.languageCode}';

  _expectRect(rendered.box('SouthHandFan'), projected.southHand, '$label hand');
  _expectRect(rendered.box('TableStockPile'), projected.stock, '$label stock');
  _expectRect(
    rendered.box('TableDiscardPile'),
    projected.discardHit,
    '$label discard',
  );

  // Meld lanes are matched by their keyed boxes, which are both the visible
  // clip and the drop lane. The cards inside them scroll and can extend past
  // the box; what a HUD pod must clear is the box.
  const lanes = <String, String>{
    'north-meld-lane': 'north',
    'west-meld-lane': 'west',
    'east-meld-lane': 'east',
  };
  for (final entry in lanes.entries) {
    final finder = find.byKey(ValueKey(entry.key));
    expect(finder, findsOneWidget, reason: '$label ${entry.value} lane');
    _expectRect(
      tester.getRect(finder).shift(-rendered.origin),
      switch (entry.value) {
        'north' => projected.northMeldLane,
        'west' => projected.westMeldLane,
        _ => projected.eastMeldLane,
      },
      '$label ${entry.value} meld lane',
    );
  }

  // The south lane has no key of its own; it is the fourth SeatMeldLane and the
  // only one anchored to the bottom, so it is located by that rather than by
  // index — an ordering change would otherwise silently compare the wrong lane.
  final southLane = _byTypeName('SeatMeldLane').evaluate().map((element) {
    final ro = element.renderObject! as RenderBox;
    return (ro.localToGlobal(Offset.zero) - rendered.origin) & ro.size;
  }).where((rect) => rect.left == projected.southMeldLane.left &&
      rect.top > projected.northMeldLane.top);
  expect(southLane, hasLength(1), reason: '$label south lane');
  _expectRect(southLane.first, projected.southMeldLane, '$label south lane');

  // Opponent seats contribute their rendered cards, never the full-width
  // alignment container. The fixture is at the visible cap, so the projection
  // and the rendered union must be identical rather than merely enclosing.
  const rails = <String, String>{
    'west-opponent-rail': 'west',
    'east-opponent-rail': 'east',
  };
  for (final entry in rails.entries) {
    final element = find.byKey(ValueKey(entry.key)).evaluate().single;
    final cards = _cardsIn(element, rendered.origin);
    expect(cards, isNotEmpty, reason: '$label ${entry.value} cards');
    _expectRect(
      _union(cards),
      entry.value == 'west' ? projected.westCards : projected.eastCards,
      '$label ${entry.value} cards',
    );
  }

  final northRail = _byTypeName('OpponentHandRail').evaluate().single;
  final northCards = _cardsIn(northRail, rendered.origin);
  expect(northCards, isNotEmpty, reason: '$label north cards');
  _expectRect(_union(northCards), projected.northCards, '$label north cards');
}

void main() {
  // Correction 02 §8 requires the stress fixture to prove its own population
  // before any geometry is trusted. This group is declared first on purpose:
  // it runs ahead of the parity and overlap assertions, so a fixture that
  // quietly thinned out fails here rather than letting a HUD placement pass
  // against a table with one east card on it — which is exactly how the
  // withdrawn lower rectangles came to be measured.
  group('A32 population oracle — the fixture is fully populated', () {
    test('the snapshot carries maximum content', () {
      final snapshot = maximumContentSnapshot();

      // Hand counts at or above the playfield's *visible* caps: 12 for the
      // north rail, 6 for each side rail. Above the cap the union stops
      // growing, so at-or-above is what "maximum" means here.
      expect(
        snapshot.hands[PlayerSeat.north]!.length,
        greaterThanOrEqualTo(12),
        reason: 'north hand below the 12-card visible cap',
      );
      for (final seat in const [PlayerSeat.east, PlayerSeat.west]) {
        expect(
          snapshot.hands[seat]!.length,
          greaterThanOrEqualTo(6),
          reason: '${seat.name} hand below the 6-card visible cap',
        );
      }
      expect(
        snapshot.hands[PlayerSeat.south]!.length,
        greaterThanOrEqualTo(13),
        reason: 'South hand is not a full hand',
      );

      // A full meld lane for every seat, not just the two the HUD sits near.
      for (final seat in PlayerSeat.values) {
        final melds = snapshot.tableMelds[seat] ?? const <PlacedMeld>[];
        expect(
          melds.length,
          greaterThanOrEqualTo(4),
          reason: '${seat.name} meld lane is not full',
        );
        expect(
          melds.every((meld) => meld.cards.length >= 3),
          isTrue,
          reason: '${seat.name} has a meld with too few cards',
        );
      }

      expect(
        snapshot.discardPile.length,
        greaterThanOrEqualTo(20),
        reason: 'discard pile is not deep',
      );
      expect(snapshot.stock, isNotEmpty, reason: 'stock is empty');
    });

    for (final body in const [Size(844, 390), Size(914, 411), Size(926, 428)]) {
      testWidgets('$body renders that content', (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // The rendered side of the oracle: counted on the tree the geometry
        // suites measure, not on the values handed to it.
        final rendered = await _render(tester, body, AppStrings.english);

        int cardsUnder(String key) => _cardsIn(
          find.byKey(ValueKey(key)).evaluate().single,
          rendered.origin,
        ).length;

        expect(
          _cardsIn(
            _byTypeName('OpponentHandRail').evaluate().single,
            rendered.origin,
          ).length,
          greaterThanOrEqualTo(12),
          reason: 'north rail rendered fewer than 12 cards at $body',
        );
        expect(
          cardsUnder('east-opponent-rail'),
          greaterThanOrEqualTo(6),
          reason: 'east rail rendered fewer than 6 cards at $body',
        );
        expect(
          cardsUnder('west-opponent-rail'),
          greaterThanOrEqualTo(6),
          reason: 'west rail rendered fewer than 6 cards at $body',
        );
        for (final lane in const [
          'north-meld-lane',
          'east-meld-lane',
          'west-meld-lane',
        ]) {
          expect(
            cardsUnder(lane),
            greaterThanOrEqualTo(3),
            reason: '$lane rendered no meld content at $body',
          );
        }
        expect(
          _cardsIn(
            _byTypeName('SouthHandFan').evaluate().single,
            rendered.origin,
          ).length,
          greaterThanOrEqualTo(13),
          reason: 'South hand rendered a thin hand at $body',
        );
        for (final name in const ['TableStockPile', 'TableDiscardPile']) {
          expect(
            _byTypeName(name),
            findsOneWidget,
            reason: '$name missing at $body',
          );
        }
      });
    }
  });

  group('the projection matches the rendered table at every short size', () {
    for (final body in const [
      Size(844, 390),
      Size(914, 411),
      Size(926, 428),
    ]) {
      for (final strings in [AppStrings.english, AppStrings.arabic]) {
        testWidgets('$body in ${strings.languageCode}', (tester) async {
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await _expectParity(tester, body, strings);
        });
      }
    }
  });

  group('the compact boundaries are where duplicated math drifts first', () {
    // compact = height <= 360 || width <= 700, and it switches every card size,
    // both inset clamps, the rail visible count and the minimum hand inset all
    // at once. Either side of both edges, and exactly on them.
    for (final body in const [
      Size(699, 500),
      Size(700, 500),
      Size(701, 500),
      Size(900, 359),
      Size(900, 360),
      Size(900, 361),
    ]) {
      for (final strings in [AppStrings.english, AppStrings.arabic]) {
        testWidgets('$body in ${strings.languageCode}', (tester) async {
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await _expectParity(tester, body, strings);
        });
      }
    }
  });

  group('safe-area insets change the body, and the projection follows', () {
    testWidgets('a notched landscape body still matches', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // The body the short layout actually gets is the screen minus the
      // insets, so that — not the screen — is what the projection is fed.
      const screen = Size(926, 428);
      const safeInsets = EdgeInsets.only(left: 47, right: 47);
      final body = ReplayHudLayout.shortBodySize(
        screen: screen,
        safeInsets: safeInsets,
      );

      expect(body.width, 926 - 94);
      expect(body.height, 428);
      await _expectParity(tester, body, AppStrings.english);
      await _expectParity(tester, body, AppStrings.arabic);
    });
  });

  group('what the parity buys the collision map', () {
    testWidgets('the map clears the rectangles that actually rendered', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const screen = Size(844, 390);
      final rendered = await _render(tester, screen, AppStrings.english);
      final decision = ReplayHudLayout.resolveFor(
        screen: screen,
        safeInsets: EdgeInsets.zero,
      );
      expect(decision.mode, ReplayLayoutMode.short);

      // The link between the guard and the rendered HUD: every permanent slot
      // the map cleared must also clear the real hand, stock and discard.
      for (final slot in decision.rails.permanent) {
        for (final name in const [
          'SouthHandFan',
          'TableStockPile',
          'TableDiscardPile',
        ]) {
          expect(
            slot.overlaps(rendered.box(name)),
            isFalse,
            reason: '$slot covers the rendered $name',
          );
        }
      }
    });
  });
}
