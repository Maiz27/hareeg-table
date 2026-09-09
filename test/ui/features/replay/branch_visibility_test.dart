import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/core/cards/card_view.dart';
import 'package:hareeg_table/ui/features/game_table/table_session_config.dart';
import 'package:hareeg_table/ui/features/game_table/views/game_table_screen.dart';
import 'package:hareeg_table/ui/features/game_table/widgets/opponent_seat_rails.dart';
import 'package:hareeg_table/ui/features/game_table/widgets/physical_table_playfield.dart';

import '../../../support/branch_sandbox_harness.dart';

/// Collapses the differences that are not identity.
///
/// Arabic card names carry optional diacritics and tatweel, and a leak that
/// differed from the canonical spelling only by a kashida would still name the
/// card out loud. Whitespace is collapsed for the same reason: a merged
/// semantics label joins its parts with newlines.
String _normalize(String value) => value
    .replaceAll(RegExp('[ً-ْـ]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Every string the rendered tree publishes to anyone.
///
/// Rendered text, tooltip messages, and every semantics `label`, `value`,
/// `hint` and `tooltip` in the whole tree — read off the semantics nodes
/// themselves rather than through a finder, because a finder can only answer
/// the question it was asked and this has to catch a name nobody predicted.
List<String> _publishedStrings(WidgetTester tester) {
  final out = <String>[];

  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    final data = text.data;
    if (data != null) out.add(data);
    final span = text.textSpan;
    if (span != null) out.add(span.toPlainText());
  }
  for (final tooltip in tester.widgetList<Tooltip>(find.byType(Tooltip))) {
    final message = tooltip.message;
    if (message != null) out.add(message);
  }
  for (final semantics in tester.widgetList<Semantics>(
    find.byType(Semantics),
  )) {
    final p = semantics.properties;
    for (final value in [p.label, p.value, p.hint, p.tooltip]) {
      if (value != null && value.isNotEmpty) out.add(value);
    }
  }

  // ignore: deprecated_member_use
  final root = tester.binding.pipelineOwner.semanticsOwner?.rootSemanticsNode;
  if (root != null) {
    void visit(SemanticsNode node) {
      final data = node.getSemanticsData();
      for (final value in [data.label, data.value, data.hint, data.tooltip]) {
        if (value.isNotEmpty) out.add(value);
      }
      node.visitChildren((child) {
        visit(child);
        return true;
      });
    }

    visit(root);
  }

  // Keys are a publication channel too: a ValueKey carrying a real card id
  // survives into the semantics tree and into any inspection tooling.
  for (final element in tester.allElements) {
    final key = element.widget.key;
    if (key is ValueKey<String>) out.add(key.value);
  }
  return out;
}

/// Every `(name, where)` pair in which a hidden identity appears **as a
/// substring** of something the tree published.
///
/// Substring, not equality. Round 2 reproduced the exact defect this closes: a
/// merged label reading "North holds Ace of Spades" is not *equal* to "Ace of
/// Spades", so an equality matcher passed while the card was being announced.
List<String> _leaks(Iterable<String> published, Iterable<String> hiddenNames) {
  final leaks = <String>[];
  final haystacks = published.map(_normalize).toList();
  for (final name in hiddenNames) {
    final needle = _normalize(name);
    if (needle.isEmpty) continue;
    for (final haystack in haystacks) {
      if (haystack.contains(needle)) {
        leaks.add('"$name" inside "$haystack"');
      }
    }
  }
  return leaks;
}

/// Visibility is rendering and only rendering.
///
/// Two claims, proven separately because they fail in different ways: a blind
/// sandbox must not leak an opponent identity through *any* channel, and a
/// study sandbox must not play differently for having revealed them.
void main() {
  PhysicalTablePlayfield playfield(WidgetTester tester) => tester
      .widget<PhysicalTablePlayfield>(find.byType(PhysicalTablePlayfield));

  /// Every card the opponents actually hold in the fixture.
  Set<HareegCard> opponentCards(WidgetTester tester) {
    final table = playfield(tester);
    // Read from what the table was handed, so this cannot drift from the
    // fixture. In blind mode it is empty by construction, so the caller
    // supplies the truth instead.
    return table.revealedHands.values.expand((h) => h).toSet();
  }

  group('the leak detector can actually detect a leak', () {
    testWidgets('a card name embedded in a sentence is found', (tester) async {
      // The positive control. Everything below asserts an absence, and an
      // absence proves nothing unless the instrument can register a presence.
      // The sentence is exactly the shape that defeated the round-2 matcher.
      const hidden = 'Ace of Spades';
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.ltr,
            child: Semantics(
              label: 'North holds Ace of Spades',
              child: const Text('the north seat is holding an Ace of Spades'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final semantics = tester.ensureSemantics();

      final published = _publishedStrings(tester);
      final found = _leaks(published, const [hidden]);
      expect(
        found,
        isNotEmpty,
        reason: 'the detector cannot see a name inside surrounding copy',
      );
      // Both channels, not just one: a detector that only read rendered text
      // would miss a merged semantics label, and vice versa.
      expect(found.any((f) => f.contains('North holds')), isTrue);
      expect(found.any((f) => f.contains('the north seat')), isTrue);

      // ...and it does not fire on a name that is genuinely absent.
      expect(_leaks(published, const ['Seven of Diamonds']), isEmpty);
      semantics.dispose();
    });
  });

  for (final strings in [AppStrings.english, AppStrings.arabic]) {
    group('a blind ${strings.languageCode} sandbox leaks nothing', () {
      testWidgets('paint, keys, semantics, tooltips and expansion stay silent', (
        tester,
      ) async {
        // The truth is taken from a study sandbox over the *same* frame, in
        // the *same* locale: that is what the opponents hold, stated by the
        // app itself rather than by a second copy of the fixture that could
        // drift out of step with it.
        await pumpBranchSandbox(
          tester,
          branchSandboxApp(
            frame: branchFrame(branchSnapshot()),
            visibility: BranchVisibility.study,
            coachEligible: false,
            strings: strings,
          ),
        );
        final hidden = opponentCards(tester);
        expect(hidden, isNotEmpty);
        expect(hidden.length, greaterThan(20));

        await pumpBranchSandbox(
          tester,
          branchSandboxApp(
            frame: branchFrame(branchSnapshot()),
            visibility: BranchVisibility.blind,
            coachEligible: false,
            strings: strings,
          ),
        );
        final semantics = tester.ensureSemantics();

        final southIds = playfield(tester).southCards.map((c) => c.id).toSet();
        final leakable = hidden.where((c) => !southIds.contains(c.id)).toList();
        expect(leakable, isNotEmpty, reason: 'nothing left to leak');

        // 1. Paint. No card view anywhere in the tree carries an opponent
        //    identity face up — and the ones that exist are backs.
        final views = tester.widgetList<HareegCardView>(
          find.byType(HareegCardView),
        );
        expect(views, isNotEmpty);
        for (final view in views) {
          if (view.faceDown) continue;
          for (final card in leakable) {
            expect(
              view.card.id,
              isNot(card.id),
              reason: 'an opponent card is painted face up',
            );
          }
        }

        // 2-4. Keys, semantics and tooltips, in one sweep over everything the
        //      tree publishes, matched as substrings.
        final southNames = {
          for (final card in playfield(tester).southCards)
            if (card.effectiveIdentity != null)
              strings.cardName(card.effectiveIdentity!),
        };
        final hiddenNames = {
          for (final card in leakable)
            if (card.effectiveIdentity != null)
              strings.cardName(card.effectiveIdentity!),
        }.where((name) => !southNames.contains(name)).toList()..sort();
        expect(
          hiddenNames,
          isNotEmpty,
          reason: 'every hidden identity is also in south\'s hand',
        );
        expect(hiddenNames.length, greaterThan(10));

        final published = _publishedStrings(tester);
        expect(
          published.length,
          greaterThan(20),
          reason: 'nothing was collected, so the sweep is vacuous',
        );
        final leaks = _leaks(published, hiddenNames);
        expect(leaks, isEmpty, reason: 'blind sandbox published: $leaks');

        // Card ids are an identity too, and they are what a key would carry.
        for (final card in leakable) {
          for (final value in published) {
            expect(
              value.contains(card.id),
              isFalse,
              reason: '"$value" carries opponent card id ${card.id}',
            );
          }
        }

        // 5. Expansion. Not "the handler is null" — that is an implementation
        //    detail. The forbidden interaction is actually attempted: tap each
        //    opponent rail where a study sandbox would open it, and nothing
        //    may open.
        final table = playfield(tester);
        expect(table.revealedHands, isEmpty);
        for (final seat in const [
          PlayerSeat.north,
          PlayerSeat.east,
          PlayerSeat.west,
        ]) {
          expect(table.revealedHands[seat], isNull, reason: seat.name);
          expect(
            find.bySemanticsLabel(strings.branchStudyHandExpand(seat)),
            findsNothing,
            reason: '${seat.name} publishes a study affordance while blind',
          );
        }

        for (final railKey in const [
          'west-opponent-rail',
          'east-opponent-rail',
        ]) {
          final rail = find.byKey(ValueKey(railKey));
          expect(rail, findsOneWidget);
          await tester.tap(rail, warnIfMissed: false);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('study-hand-cards')),
            findsNothing,
            reason: 'tapping $railKey opened a hidden hand',
          );
        }
        // North has no rail key, so drive it by position: the top-centre strip
        // is where its cards are, and tapping it must be just as inert.
        final northRail = tester.getRect(find.byType(OpponentHandRail));
        await tester.tapAt(northRail.center);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('study-hand-cards')), findsNothing);
        // And nothing about the board moved as a result of any of that.
        expect(playfield(tester).revealedHands, isEmpty);
        expect(playfield(tester).currentSeat, table.currentSeat);

        // One last sweep, after all that poking: an expansion that half-opened
        // would have published a name by now.
        expect(_leaks(_publishedStrings(tester), hiddenNames), isEmpty);
        semantics.dispose();
      });
    });
  }

  group('a study sandbox reveals hands and changes nothing else', () {
    testWidgets('every opponent hand renders face up and expands read-only', (
      tester,
    ) async {
      await pumpBranchSandbox(
        tester,
        branchSandboxApp(
          frame: branchFrame(branchSnapshot()),
          visibility: BranchVisibility.study,
          coachEligible: false,
        ),
      );

      final table = playfield(tester);
      // All three seats, not just the one rail the north hand uses: opponent
      // cards render at three sites, and revealing one of them would be a
      // study mode that quietly only half works.
      for (final seat in const [
        PlayerSeat.north,
        PlayerSeat.east,
        PlayerSeat.west,
      ]) {
        expect(table.revealedHands[seat], isNotEmpty, reason: seat.name);
      }

      final revealed = table.revealedHands[PlayerSeat.north]!;
      final painted = tester
          .widgetList<HareegCardView>(find.byType(HareegCardView))
          .where((v) => !v.faceDown)
          .map((v) => v.card.id)
          .toSet();
      expect(
        painted,
        containsAll(revealed.take(3).map((c) => c.id)),
        reason: 'the revealed hand is actually painted, not merely passed in',
      );

      // Expansion opens a read-only sheet and cannot make the seat playable.
      // Driven through the widget's own handler rather than a synthesised tap:
      // the rails are 44 dp strips under other chrome at this size, and a
      // missed tap would make this pass for the wrong reason.
      table.onExpandRevealedHand!(PlayerSeat.east);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('study-hand-cards')), findsOneWidget);
      final sheet = tester.widget<Wrap>(
        find.byKey(const ValueKey('study-hand-cards')),
      );
      expect(sheet.children, isNotEmpty);
      // Read-only: the sheet carries card views and no action affordance of
      // any kind, so there is no route by which viewing a hand acts on it.
      for (final child in sheet.children) {
        expect(child, isA<HareegCardView>());
      }
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('study-hand-cards')),
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('study-hand-cards')),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
      // And the seat is still not the one on turn.
      expect(playfield(tester).currentSeat, PlayerSeat.south);
    });

    testWidgets('blind and study apply the identical action stream', (
      tester,
    ) async {
      // B55, to the Planner's ruling: **one ordered successful-apply stream**,
      // carrying for every South and CPU action the actor and seat, the exact
      // action id, the apply result, the CPU tier and the sorted legal set
      // where applicable, and the **complete** resulting state — the snapshot
      // serialized whole, not a chosen handful of its fields.
      //
      // The stream is observed at the success boundary, from the same hook the
      // sandbox uses to learn it has diverged. The earlier recorder listened
      // inside `chooseMove`, which happens *before* success is known and could
      // never say which choices actually applied.
      //
      // The CPU policy is the shipping one. A scripted stand-in would make the
      // two runs agree by fiat and prove nothing about whether a revealed hand
      // can reach a decision.
      Future<List<TableAppliedAction>> run(BranchVisibility visibility) async {
        final applied = <TableAppliedAction>[];
        // Both runs share the seed, the injected clock and the South script,
        // so anything that differs is the visibility.
        await pumpBranchSandbox(
          tester,
          branchSandboxApp(
            frame: branchFrame(
              branchSnapshot(
                southHand: branchFinishingHand,
                openingState: branchOpened(PlayerSeat.south),
              ),
            ),
            visibility: visibility,
            coachEligible: false,
            clock: BranchTestClock(DateTime.utc(2027, 5, 5, 9)).call,
            onAppliedAction: applied.add,
          ),
        );

        for (final card in branchFinishingHand.take(3)) {
          final rect = tester.getRect(branchSouthCard(card));
          await tester.tapAt(Offset(rect.left + 6, rect.center.dy));
          await tester.pump();
        }
        await tester.pumpAndSettle();
        await tester.tap(find.text('Play meld'));
        await tester.pumpAndSettle();

        // The finishing discard crosses the round: south goes out, the round
        // is scored, and the sandbox deals the next one.
        await branchDiscard(tester, branchFinishingHand.last);
        await tester.pumpAndSettle(const Duration(seconds: 30));

        // Round two, where the CPUs finally get to move. South draws and
        // discards twice, so the stream carries several real CPU turns on the
        // far side of the boundary rather than a single one.
        for (var turn = 0; turn < 2; turn += 1) {
          await branchDrawStock(tester);
          await branchDiscard(tester, playfield(tester).southCards.first);
          await tester.pumpAndSettle(const Duration(seconds: 30));
        }
        return applied;
      }

      /// One event, flattened to a comparable line.
      String line(TableAppliedAction a) => [
        a.isHuman ? 'south' : 'cpu',
        'seat=${a.seat.name}',
        'action=${a.actionId}',
        'applied=${a.succeeded}',
        'tier=${a.cpuTier?.name ?? '-'}',
        'legal=${a.legalActionIds?.join('|') ?? '-'}',
        // Complete, not sampled: every field the snapshot serializes.
        'state=${jsonEncode(a.snapshot.toJson())}',
      ].join(' ');

      final blind = await run(BranchVisibility.blind);
      final study = await run(BranchVisibility.study);
      final blindLines = blind.map(line).toList();
      final studyLines = study.map(line).toList();

      // Anti-vacuity: the stream has to contain real South actions, real CPU
      // actions from every seat, and an explicit round crossing.
      expect(blind, isNotEmpty, reason: 'nothing applied at all');
      expect(
        blind.where((a) => a.isHuman).length,
        greaterThanOrEqualTo(5),
        reason: 'the South script did not apply',
      );
      final cpuEvents = blind.where((a) => !a.isHuman).toList();
      expect(
        cpuEvents.length,
        greaterThan(3),
        reason: 'too few CPU actions to span a round crossing',
      );
      expect(
        cpuEvents.map((a) => a.seat).toSet(),
        hasLength(3),
        reason: 'not every CPU seat acted',
      );
      for (final event in cpuEvents) {
        expect(event.cpuTier, isNotNull, reason: 'a CPU event has no tier');
        expect(
          event.legalActionIds,
          isNotNull,
          reason: 'a CPU event has no legal set',
        );
        expect(event.legalActionIds, isNotEmpty);
        // Sorted, which is what makes the two runs comparable at all: the
        // runner offers the set in whatever order it enumerated.
        final sorted = List<String>.of(event.legalActionIds!)..sort();
        expect(event.legalActionIds, sorted);
      }
      for (final event in blind.where((a) => a.isHuman)) {
        expect(event.cpuTier, isNull);
        expect(event.legalActionIds, isNull);
      }
      expect(
        blind.every((a) => a.succeeded),
        isTrue,
        reason: 'the stream is a successful-apply stream',
      );

      int crossingIndex(List<TableAppliedAction> events) {
        for (var i = 1; i < events.length; i += 1) {
          if (events[i].snapshot.roundNumber >
              events[i - 1].snapshot.roundNumber) {
            return i;
          }
        }
        return -1;
      }

      final blindCrossing = crossingIndex(blind);
      expect(
        blindCrossing,
        greaterThan(0),
        reason: 'the run never crossed a round',
      );
      expect(
        blind.length - blindCrossing,
        greaterThan(2),
        reason: 'the stream stops at the crossing instead of running past it',
      );
      expect(crossingIndex(study), blindCrossing);

      // The comparison itself.
      expect(studyLines, blindLines);

      // The mutation control. Changing one event's *resulting state* — not its
      // action id — must fail, which is what shows the complete state is being
      // compared rather than the ids alone.
      final tamperedState = List<String>.of(blindLines);
      final target = tamperedState[blindCrossing];
      tamperedState[blindCrossing] = target.replaceFirst(
        '"roundNumber":${blind[blindCrossing].snapshot.roundNumber}',
        '"roundNumber":${blind[blindCrossing].snapshot.roundNumber + 41}',
      );
      expect(
        tamperedState[blindCrossing],
        isNot(target),
        reason:
            'the state payload does not carry roundNumber, so the control '
            'below would pass for the wrong reason',
      );
      expect(
        () => expect(tamperedState, blindLines),
        throwsA(isA<TestFailure>()),
        reason: 'a changed resulting state does not fail the comparison',
      );

      // ...and so must changing one event's action id.
      final tamperedAction = List<String>.of(blindLines);
      tamperedAction[0] = tamperedAction[0].replaceFirst(
        'action=${blind.first.actionId}',
        'action=not-the-action-that-applied',
      );
      expect(
        () => expect(tamperedAction, blindLines),
        throwsA(isA<TestFailure>()),
        reason: 'a changed action id does not fail the comparison',
      );
    });
  });
}
