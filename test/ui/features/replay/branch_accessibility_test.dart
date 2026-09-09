import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/core/panels/lounge_panel.dart';
import 'package:hareeg_table/ui/features/game_table/table_session_config.dart';
import 'package:hareeg_table/ui/features/game_table/widgets/physical_table_playfield.dart';
import 'package:hareeg_table/ui/features/replay/widgets/branch_entry_sheet.dart';

import '../../../support/branch_sandbox_harness.dart';

/// B63, exhaustively: every interactive element the branch feature adds, at
/// every contracted size, in both languages.
///
/// Round 2 rejected the one-size subset this replaces. What is asserted for
/// each control, on the **rendered semantics node** rather than on a widget
/// rectangle:
///
///   * exactly one node carries the localized label — not two, so a merged
///     parent cannot make a second announcement;
///   * a `Tooltip` widget carries the same localized message, and it is
///     **excluded from semantics**: Flutter web renders a node's label and its
///     tooltip both as text, so a control publishing both announces its name
///     twice. Round 1 reproduced exactly that on the docked branch control.
///     The tooltip is a pointer affordance and is asserted on the widget;
///   * it is a button (or a switch, for the one control that is one);
///   * its enabled state is stated, not merely absent;
///   * it publishes a tap action;
///   * and its own rect is at least 44 dp on both axes.
///
/// The size sweep resizes the viewport with the surface already up, rather
/// than driving each surface again at each size. Driving a card drag at 320 dp
/// on a landscape table is not possible, but the panel that drag produced must
/// still survive that width — and relayout under a live surface is the harder
/// case, not the easier one.

/// Every contracted size, short and docked.
const _sizes = <(String, Size)>[
  ('844x390 short', Size(844, 390)),
  ('914x411 short', Size(914, 411)),
  ('926x428 short', Size(926, 428)),
  ('320x568 docked', Size(320, 568)),
  ('390x844 docked', Size(390, 844)),
];

const _minTarget = 44.0;

/// One control the branch feature adds.
typedef _Control = ({String label, String tooltip, bool isSwitch, int nodes});

_Control _button(String label, {String? tooltip, int nodes = 1}) =>
    (label: label, tooltip: tooltip ?? label, isSwitch: false, nodes: nodes);

/// The node's rectangle in **logical** root coordinates.
///
/// `SemanticsNode.rect` is in the node's own space and each ancestor's
/// transform maps one level up, so walking to the root gives a rect in the
/// tree's root space. That root space is **physical** pixels: the root node's
/// own transform carries the device pixel ratio, so an unscaled result is
/// twice the size on a 2.0 view and every 44 dp check would be half as strict
/// as it looks. Dividing by the ratio puts it back in dp.
///
/// Round 2 rejected reading `tester.getRect(finder)` here: that measures a
/// *widget*, and the contract is about what the accessibility tree publishes.
Rect _globalRect(SemanticsNode node, double devicePixelRatio) {
  var rect = node.rect;
  SemanticsNode? current = node;
  while (current != null) {
    final transform = current.transform;
    if (transform != null) {
      rect = MatrixUtils.transformRect(transform, rect);
    }
    current = current.parent;
  }
  return Rect.fromLTRB(
    rect.left / devicePixelRatio,
    rect.top / devicePixelRatio,
    rect.right / devicePixelRatio,
    rect.bottom / devicePixelRatio,
  );
}

List<SemanticsNode> _allNodes(WidgetTester tester) {
  final out = <SemanticsNode>[];
  // ignore: deprecated_member_use
  final root = tester.binding.pipelineOwner.semanticsOwner?.rootSemanticsNode;
  if (root == null) return out;
  void visit(SemanticsNode node) {
    // A merged descendant reports the merged data too, so counting it would
    // see one control as two. The node that owns the merge is the one the
    // platform publishes.
    if (!node.isMergedIntoParent) out.add(node);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(root);
  return out;
}

String _tidy(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

/// One published interaction: the semantics action, and the name it is
/// published under.
typedef ActionPair = ({String action, String label});

/// Every interaction the panel at [of] publishes, as ordered action/label
/// pairs.
///
/// Round 3's inventory collected descendant `Text` values into a **set**, and
/// the round-3 cold review broke it with the exact round-2 regression: an
/// icon-only `Close` contributes no `Text` at all, so a third actionable
/// control was invisible, and two controls sharing a label collapsed into one
/// entry. Neither failure mode survives here:
///
///   * enumeration is over the **semantics nodes the panel's own subtree
///     owns**, so a control with no text is still counted under whatever name
///     it publishes — and a control that publishes no name at all is counted
///     as `(unnamed)`, which is itself a failure rather than an omission;
///   * the result is a **list**, not a set, so two controls sharing a label
///     are two entries;
///   * each entry names the action, so "exactly two actions" is asserted
///     against what a screen reader can actually invoke, not against text.
///
/// Scope is the widget subtree rather than a rectangle: at 320 dp the panel
/// and the table behind it overlap, so a rect-based scope cannot tell them
/// apart.
List<ActionPair> panelActionPairs(WidgetTester tester, {required Finder of}) {
  const interactions = <SemanticsAction, String>{
    SemanticsAction.tap: 'tap',
    SemanticsAction.longPress: 'longPress',
    SemanticsAction.increase: 'increase',
    SemanticsAction.decrease: 'decrease',
  };
  final owned = <int, SemanticsNode>{};
  for (final element
      in find
          .descendant(of: of, matching: find.byWidgetPredicate((_) => true))
          .evaluate()) {
    final node = element.renderObject?.debugSemantics;
    if (node != null) owned[node.id] = node;
  }
  final pairs = <ActionPair>[];
  for (final node in owned.values) {
    // A node merged into an ancestor is not one the platform publishes: the
    // ancestor that owns the merge is. Counting both would report the header's
    // single close button as two controls — and, worse, one of them as
    // unnamed, which would make the mutation below fail for the wrong reason.
    if (node.isMergedIntoParent) continue;
    final data = node.getSemanticsData();
    final published = interactions.entries
        .where((entry) => data.hasAction(entry.key))
        .map((entry) => entry.value)
        .toList();
    if (published.isEmpty) continue;
    final named = _tidy(data.label).isNotEmpty
        ? _tidy(data.label)
        : _tidy(data.tooltip).isNotEmpty
        ? '${_tidy(data.tooltip)} (tooltip only)'
        : '(unnamed)';
    for (final action in published) {
      pairs.add((action: action, label: named));
    }
  }
  pairs.sort((a, b) {
    final byLabel = a.label.compareTo(b.label);
    return byLabel != 0 ? byLabel : a.action.compareTo(b.action);
  });
  return pairs;
}

void main() {
  Future<void> resize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2.0;
    await tester.pumpAndSettle();
  }

  void assertNode(
    WidgetTester tester,
    SemanticsNode node,
    _Control control, {
    required String wanted,
    required String where,
  }) {
    final data = node.getSemanticsData();

    expect(
      _tidy(data.tooltip),
      isEmpty,
      reason:
          '$where: "$wanted" publishes its name as a tooltip as well as a '
          'label, which web reads out twice',
    );
    if (control.isSwitch) {
      expect(
        data.flagsCollection.isToggled,
        isNot(ui.Tristate.none),
        reason: '$where: "$wanted" publishes no toggled state',
      );
    } else {
      expect(
        data.flagsCollection.isButton,
        isTrue,
        reason: '$where: "$wanted" is not a button',
      );
    }
    expect(
      data.flagsCollection.isEnabled,
      ui.Tristate.isTrue,
      reason: '$where: "$wanted" does not state that it is enabled',
    );
    expect(
      data.hasAction(SemanticsAction.tap),
      isTrue,
      reason: '$where: "$wanted" publishes no tap action',
    );

    final rect = _globalRect(node, tester.view.devicePixelRatio);
    expect(
      rect.width,
      greaterThanOrEqualTo(_minTarget),
      reason: '$where: "$wanted" is ${rect.width} dp wide',
    );
    expect(
      rect.height,
      greaterThanOrEqualTo(_minTarget),
      reason: '$where: "$wanted" is ${rect.height} dp tall',
    );
  }

  /// Asserts a real, localized `Tooltip` widget exists for [control].
  void assertTooltip(
    WidgetTester tester,
    _Control control, {
    required String where,
  }) {
    final messages = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .map((t) => _tidy(t.message ?? ''))
        .toSet();
    expect(
      messages,
      contains(_tidy(control.tooltip)),
      reason: '$where: no Tooltip carries "${control.tooltip}"',
    );
  }

  /// Asserts the whole contracted metadata set for one control.
  void assertControl(
    WidgetTester tester,
    _Control control, {
    required String where,
  }) {
    final wanted = _tidy(control.label);
    final matches = _allNodes(
      tester,
    ).where((node) => _tidy(node.getSemanticsData().label) == wanted).toList();
    expect(
      matches,
      hasLength(control.nodes),
      reason:
          '$where: expected ${control.nodes} node(s) labelled "$wanted", '
          'found ${matches.length}',
    );
    // Every match, not the first: where a name legitimately appears twice both
    // of them are controls a screen reader will reach.
    for (final node in matches) {
      assertNode(tester, node, control, wanted: wanted, where: where);
    }
    assertTooltip(tester, control, where: where);
  }

  /// Sweeps [controls] across every contracted size with the surface up.
  ///
  /// Each control is scrolled into view before it is measured. A semantics
  /// rect is clipped by its ancestors, so a control sitting below the fold of
  /// a scrollable panel reports the sliver of itself that happens to be
  /// visible — which is a fact about the scroll offset, not about the target.
  /// The panels this covers are all scrollable by design at 390 dp.
  Future<void> sweep(
    WidgetTester tester,
    List<_Control> controls, {
    required String where,
  }) async {
    expect(controls, isNotEmpty, reason: '$where: nothing to check');
    for (final (name, size) in _sizes) {
      await resize(tester, size);
      for (final control in controls) {
        final finder = find.bySemanticsLabel(control.label);
        if (finder.evaluate().length == 1) {
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
        }
        assertControl(tester, control, where: '$where @ $name');
      }
    }
  }

  for (final strings in [AppStrings.english, AppStrings.arabic]) {
    final locale = strings.languageCode;

    group('branch accessibility inventory, $locale', () {
      testWidgets('the entry chooser names and sizes every control', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(844, 390) * 2;
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          AppStringsScope(
            strings: strings,
            child: Directionality(
              textDirection: strings.textDirection,
              child: MaterialApp(
                home: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showBranchEntrySheet(context),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        final semantics = tester.ensureSemantics();
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        await sweep(tester, [
          _button(strings.close),
          _button(
            '${strings.branchEntryBlind}. ${strings.branchEntryBlindNote}',
          ),
          _button(
            '${strings.branchEntryStudy}. ${strings.branchEntryStudyNote}',
          ),
          _button(strings.branchEntryCancel),
        ], where: 'entry chooser');
        semantics.dispose();
      });

      testWidgets(
        'the sandbox surface names and sizes every control',
        (tester) async {
          await pumpBranchSandbox(
            tester,
            branchSandboxApp(
              frame: branchFrame(
                branchSnapshot(
                  southHand: branchFinishingHand,
                  openingState: branchOpened(PlayerSeat.south),
                  scores: const {
                    PlayerSeat.south: 0,
                    PlayerSeat.east: 30,
                    PlayerSeat.north: 30,
                    PlayerSeat.west: 30,
                  },
                  roundNumber: 3,
                ),
              ),
              visibility: BranchVisibility.study,
              coachEligible: true,
              strings: strings,
            ),
            size: const Size(844, 390) * 2,
          );
          final semantics = tester.ensureSemantics();

          // 1. The chrome the sandbox publishes, plus the three study rails.
          await sweep(tester, [
            _button(strings.branchExitSandbox),
            for (final seat in const [
              PlayerSeat.north,
              PlayerSeat.east,
              PlayerSeat.west,
            ])
              _button(strings.branchStudyHandExpand(seat)),
          ], where: 'sandbox chrome');

          // 2. The study hand sheet, opened through the table's own handler.
          await resize(tester, const Size(844, 390));
          tester
              .widget<PhysicalTablePlayfield>(
                find.byType(PhysicalTablePlayfield),
              )
              .onExpandRevealedHand!(PlayerSeat.east);
          await tester.pumpAndSettle();
          await sweep(tester, [
            _button(strings.branchStudyHandClose),
          ], where: 'study hand sheet');
          await tester.tap(find.byTooltip(strings.branchStudyHandClose));
          await tester.pumpAndSettle();

          // 3. The pause panel, including the coach toggle an eligible sandbox
          //    offers.
          await resize(tester, const Size(844, 390));
          await tester.tap(find.byTooltip(strings.pauseTable));
          await tester.pumpAndSettle();
          await sweep(tester, [
            _button(strings.close),
            (
              label: strings.branchCoachToggle,
              tooltip: strings.branchCoachToggle,
              isSwitch: true,
              nodes: 1,
            ),
            _button(strings.branchRestart),
            _button(strings.branchResume),
            // Two: the pause panel's action, and the sandbox chrome's exit
            // control still in the tree behind the overlay. Both are checked.
            _button(strings.branchExitSandbox, nodes: 2),
          ], where: 'pause panel');
          await tester.tap(find.text(strings.branchResume));
          await tester.pumpAndSettle();

          // 4. The exit confirmation, which only exists once the sandbox has
          //    actually diverged, so it is reached by playing rather than by
          //    calling the dialog directly.
          await resize(tester, const Size(844, 390));
          for (final card in branchFinishingHand.take(3)) {
            final rect = tester.getRect(branchSouthCard(card));
            await tester.tapAt(Offset(rect.left + 6, rect.center.dy));
            await tester.pump();
          }
          await tester.pumpAndSettle();
          await tester.tap(find.text(strings.playMeld));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('branch-exit')));
          await tester.pumpAndSettle();
          expect(find.text(strings.branchExitTitle), findsOneWidget);
          await sweep(tester, [
            _button(strings.close),
            _button(strings.branchExitCancel),
            _button(strings.branchExitConfirm),
          ], where: 'exit confirmation');
          await tester.tap(find.text(strings.branchExitCancel));
          await tester.pumpAndSettle();

          // 5. The completion panel, reached by actually finishing: every
          //    opponent is one penalty from elimination, so south's finish ends
          //    the sandbox.
          await resize(tester, const Size(844, 390));
          await branchDiscard(tester, branchFinishingHand.last);
          await tester.pumpAndSettle(const Duration(seconds: 30));
          expect(
            find.text(strings.branchCompletionTitle),
            findsOneWidget,
            reason:
                'the sandbox did not complete, so nothing below is measured',
          );
          await sweep(tester, [
            _button(strings.branchReturnToReplay),
            _button(strings.branchRestart),
          ], where: 'completion panel');

          // B51's exhaustive inventory, at every size: the completion panel
          // publishes exactly two invocable actions and no third one.
          // Enumerated as action/label pairs over the semantics the panel's
          // own subtree owns — see `panelActionPairs`, and the two mutation
          // controls below that prove it rejects an icon-only third action and
          // a duplicated one.
          final expected =
              <ActionPair>[
                (action: 'tap', label: _tidy(strings.branchReturnToReplay)),
                (action: 'tap', label: _tidy(strings.branchRestart)),
              ]..sort(
                (a, b) => a.label.compareTo(b.label) != 0
                    ? a.label.compareTo(b.label)
                    : a.action.compareTo(b.action),
              );
          for (final (name, size) in _sizes) {
            await resize(tester, size);
            final pairs = panelActionPairs(
              tester,
              of: find.byType(LoungePanel),
            );
            expect(
              pairs,
              expected,
              reason:
                  'completion panel @ $name publishes ${pairs.length} '
                  'action(s): $pairs',
            );
          }
          semantics.dispose();
        },
        timeout: const Timeout(Duration(minutes: 6)),
      );
    });
  }

  testWidgets('the inventory would notice a control that lost its name', (
    tester,
  ) async {
    // The control on the control. Every assertion above is a positive match
    // against a rendered node; this shows the same helper fails when the node
    // it is looking for is not there, rather than passing over an empty tree.
    await pumpBranchSandbox(
      tester,
      branchSandboxApp(
        frame: branchFrame(branchSnapshot()),
        visibility: BranchVisibility.blind,
        coachEligible: false,
      ),
    );
    final semantics = tester.ensureSemantics();
    expect(
      () => assertControl(
        tester,
        _button('a control that does not exist'),
        where: 'control',
      ),
      throwsA(isA<TestFailure>()),
    );
    // ...and a real one still passes, so the failure above is about the name
    // and not about the helper being broken.
    assertControl(
      tester,
      _button(AppStrings.english.branchExitSandbox),
      where: 'control',
    );
    semantics.dispose();
  });

  // ---- B51's two mutation controls -------------------------------------
  //
  // The completion inventory above is a *negative* claim — "and no third
  // action" — so it is worth exactly as much as its ability to fail. These
  // mount the shared `LoungePanel` component the completion panel is built
  // from, with the production two-action shape and then with each forbidden
  // shape, and run the same `panelActionPairs` enumerator over all three.
  //
  // The first mutation is the exact regression the round-3 cold review used:
  // an enabled, icon-only header `Close` alongside Return and Restart. The
  // superseded label-set algorithm passed it, because an icon contributes no
  // `Text`.

  Future<void> pumpPanel(
    WidgetTester tester, {
    required bool withThirdClose,
    LoungePanelAction? extra,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoungePanel(
            highContrast: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LoungePanelHeader(
                  icon: Icons.flag,
                  title: 'Sandbox finished',
                  subtitle: 'Sandbox',
                  onClose: withThirdClose ? () {} : null,
                  closeTooltip: withThirdClose ? 'Close' : null,
                ),
                LoungePanelActions(
                  primary: LoungePanelAction(
                    icon: Icons.arrow_back,
                    label: 'Return to replay',
                    onTap: () {},
                    tone: LoungePanelActionTone.primary,
                  ),
                  secondary: LoungePanelAction(
                    icon: Icons.restart_alt,
                    label: 'Restart from branch point',
                    onTap: () {},
                    tone: LoungePanelActionTone.neutral,
                  ),
                  tertiary: extra,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const twoActions = <ActionPair>[
    (action: 'tap', label: 'Restart from branch point'),
    (action: 'tap', label: 'Return to replay'),
  ];

  testWidgets('the completion inventory accepts exactly the shipped shape', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpPanel(tester, withThirdClose: false);
    expect(
      panelActionPairs(tester, of: find.byType(LoungePanel)),
      twoActions,
      reason:
          'the production two-action panel must pass, or the two mutations '
          'below would fail for a reason that has nothing to do with them',
    );
    semantics.dispose();
  });

  testWidgets('MUTATION: an icon-only third Close fails the inventory', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpPanel(tester, withThirdClose: true);

    // It really is a third, enabled, invocable control, and it really does
    // contribute no text.
    expect(find.byType(IconButton), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNotNull,
    );

    final pairs = panelActionPairs(tester, of: find.byType(LoungePanel));
    expect(
      pairs,
      isNot(twoActions),
      reason:
          'the icon-only third Close is invisible to the inventory — this is '
          'exactly the regression the cold review reproduced',
    );
    expect(pairs, hasLength(3));
    expect(pairs.map((p) => p.label), contains('Close'));
    semantics.dispose();
  });

  testWidgets('MUTATION: a duplicated action fails the inventory', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpPanel(
      tester,
      withThirdClose: false,
      // The same name, twice. A set-of-labels inventory collapses these into
      // one entry and reports two actions where a player is offered three.
      extra: LoungePanelAction(
        icon: Icons.arrow_back,
        label: 'Return to replay',
        onTap: () {},
        tone: LoungePanelActionTone.neutral,
      ),
    );

    final pairs = panelActionPairs(tester, of: find.byType(LoungePanel));
    expect(
      pairs,
      isNot(twoActions),
      reason: 'a duplicated action collapsed into one entry',
    );
    expect(pairs, hasLength(3));
    expect(
      pairs.where((p) => p.label == 'Return to replay'),
      hasLength(2),
      reason: 'both duplicates must be counted, not deduplicated',
    );
    semantics.dispose();
  });
}
