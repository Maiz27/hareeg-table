import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/ui/features/replay/replay_hud_layout.dart';

ReplayLayoutDecision _resolve({
  Size screen = const Size(844, 390),
  EdgeInsets safeInsets = EdgeInsets.zero,
}) {
  return ReplayHudLayout.resolveFor(screen: screen, safeInsets: safeInsets);
}

/// The three sizes the owner approved for the short layout.
const _shortSizes = <Size>[Size(844, 390), Size(914, 411), Size(926, 428)];

Matcher _closeToRect(Rect expected) => predicate<Rect>(
  (actual) =>
      (actual.left - expected.left).abs() < 0.01 &&
      (actual.top - expected.top).abs() < 0.01 &&
      (actual.right - expected.right).abs() < 0.01 &&
      (actual.bottom - expected.bottom).abs() < 0.01,
  'within 0.01 of $expected',
);

void main() {
  group('the branch metric is taken before the app bar is removed', () {
    test('the docked body subtracts the app bar and the system insets', () {
      expect(
        ReplayHudLayout.dockedBodyHeight(
          screen: const Size(390, 844),
          safeInsets: const EdgeInsets.only(top: 24, bottom: 16),
        ),
        844 - 56 - 40,
      );
    });

    test('it never goes negative', () {
      expect(
        ReplayHudLayout.dockedBodyHeight(
          screen: const Size(320, 40),
          safeInsets: EdgeInsets.zero,
        ),
        0,
      );
    });

    test('914x411 measures 355, which is the figure the contract cites', () {
      // Deciding from the *rendered* body would be circular: choosing short
      // removes the app bar, the body grows, and the grown body can measure as
      // tall. This is the stable input that breaks the loop.
      final decision = _resolve(screen: const Size(914, 411));
      expect(decision.dockedBodyHeight, 355);
      expect(decision.mode, ReplayLayoutMode.short);
    });

    test('the metric does not change when the branch does', () {
      // A3: computing it either side of the selection yields the same value.
      for (final size in [..._shortSizes, const Size(390, 844)]) {
        final before = ReplayHudLayout.dockedBodyHeight(
          screen: size,
          safeInsets: EdgeInsets.zero,
        );
        final decision = _resolve(screen: size);
        expect(decision.dockedBodyHeight, before, reason: '$size');
      }
    });
  });

  group('tall bodies keep the docked arrangement', () {
    test('390x844 is docked because it is tall, not because it is narrow', () {
      final decision = _resolve(screen: const Size(390, 844));
      expect(decision.dockedBodyHeight, 788);
      expect(decision.mode, ReplayLayoutMode.docked);
      expect(decision.dockedReason, ReplayDockedReason.tallBody);
    });

    test('a body exactly at the threshold stays docked', () {
      final decision = _resolve(screen: const Size(844, 576));
      expect(decision.dockedBodyHeight, ReplayHudLayout.shortBodyThreshold);
      expect(decision.mode, ReplayLayoutMode.docked);
      expect(decision.dockedReason, ReplayDockedReason.tallBody);
    });
  });

  group('the owner-pinned portrait fallback', () {
    test('320x568 is docked because it is portrait', () {
      // Stated as an orientation test rather than a width literal, and it has
      // to be stated: the collision map alone would send this size short. The
      // vertical rails need 104 dp of width, and at 320 the compact table
      // leaves eight free slots on the left column and ten on the right.
      final decision = _resolve(screen: const Size(320, 568));
      expect(decision.dockedBodyHeight, 512);
      expect(decision.mode, ReplayLayoutMode.docked);
      expect(decision.dockedReason, ReplayDockedReason.portraitBody);

      // The pin is load-bearing, so prove the thing it is holding back.
      expect(decision.rails.isComplete, isTrue);
      expect(decision.rails.scrub, isNotNull);
    });

    test('a square body is portrait for this purpose', () {
      final decision = _resolve(screen: const Size(500, 500));
      expect(decision.dockedReason, ReplayDockedReason.portraitBody);
    });
  });

  group('the collision map seats the whole permanent inventory', () {
    test('nine affordances plus a separate scrub at every short size', () {
      for (final size in _shortSizes) {
        final rails = _resolve(screen: size).rails;
        expect(rails.leading, hasLength(4), reason: '$size');
        expect(rails.trailing, hasLength(5), reason: '$size');
        expect(rails.scrub, isNotNull, reason: '$size');
        expect(rails.permanent, hasLength(10), reason: '$size');
      }
    });

    test('every permanent rectangle is exactly 44 x 44', () {
      for (final size in _shortSizes) {
        for (final rect in _resolve(screen: size).rails.permanent) {
          expect(rect.width, ReplayHudLayout.minTapTarget, reason: '$size');
          expect(rect.height, ReplayHudLayout.minTapTarget, reason: '$size');
        }
      }
    });

    test('nothing permanent intersects protected rendered content', () {
      for (final size in _shortSizes) {
        final decision = _resolve(screen: size);
        for (final rect in decision.rails.permanent) {
          for (final content in decision.geometry.protectedRects) {
            expect(
              rect.overlaps(content),
              isFalse,
              reason: '$rect covers $content at $size',
            );
          }
        }
      }
    });

    test('no permanent rectangle overlaps another', () {
      for (final size in _shortSizes) {
        final rects = _resolve(screen: size).rails.permanent;
        for (var i = 0; i < rects.length; i++) {
          for (var j = i + 1; j < rects.length; j++) {
            expect(rects[i].overlaps(rects[j]), isFalse, reason: '$size');
          }
        }
      }
    });

    test('the rails are flush to the physical edges', () {
      for (final size in _shortSizes) {
        final decision = _resolve(screen: size);
        for (final rect in decision.rails.leading) {
          expect(rect.left, 0, reason: '$size');
        }
        for (final rect in [
          ...decision.rails.trailing,
          decision.rails.scrub!,
        ]) {
          expect(
            rect.right,
            decision.body.width,
            reason: '$size',
          );
        }
      }
    });
  });

  group('the exact true-maximum rectangles', () {
    // These are the corrected figures. The earlier table was measured with a
    // single east card, which centres a 44 dp union in the rail box; six cards
    // fill the box and the obstruction is 124 dp tall, so the lower controls
    // sit 40 dp further down than that table said.
    final expected = <Size, ({List<Rect> leading, List<Rect> trailing, Rect scrub})>{
      Size(844, 390): (
        leading: [
          Rect.fromLTWH(0, 0, 44, 44),
          Rect.fromLTWH(0, 44, 44, 44),
          Rect.fromLTWH(0, 88, 44, 44),
          // Appended by the branch control. The three above are the Sprint 05
          // rectangles unchanged, which is the point: the packer fills the top
          // of each free run first, so a fourth control takes the next free
          // cell rather than pushing anything already placed.
          Rect.fromLTWH(0, 256, 44, 44),
        ],
        trailing: [
          Rect.fromLTWH(800, 0, 44, 44),
          Rect.fromLTWH(800, 44, 44, 44),
          Rect.fromLTWH(800, 88, 44, 44),
          Rect.fromLTWH(800, 256, 44, 44),
          Rect.fromLTWH(800, 300, 44, 44),
        ],
        scrub: Rect.fromLTWH(800, 346, 44, 44),
      ),
      Size(914, 411): (
        leading: [
          Rect.fromLTWH(0, 0, 44, 44),
          Rect.fromLTWH(0, 44, 44, 44),
          Rect.fromLTWH(0, 88, 44, 44),
          Rect.fromLTWH(0, 267.5, 44, 44),
        ],
        trailing: [
          Rect.fromLTWH(870, 0, 44, 44),
          Rect.fromLTWH(870, 44, 44, 44),
          Rect.fromLTWH(870, 88, 44, 44),
          Rect.fromLTWH(870, 267.5, 44, 44),
          Rect.fromLTWH(870, 311.5, 44, 44),
        ],
        scrub: Rect.fromLTWH(870, 367, 44, 44),
      ),
      Size(926, 428): (
        leading: [
          Rect.fromLTWH(0, 0, 44, 44),
          Rect.fromLTWH(0, 44, 44, 44),
          Rect.fromLTWH(0, 88, 44, 44),
          Rect.fromLTWH(0, 276, 44, 44),
        ],
        trailing: [
          Rect.fromLTWH(882, 0, 44, 44),
          Rect.fromLTWH(882, 44, 44, 44),
          Rect.fromLTWH(882, 88, 44, 44),
          Rect.fromLTWH(882, 276, 44, 44),
          Rect.fromLTWH(882, 320, 44, 44),
        ],
        scrub: Rect.fromLTWH(882, 384, 44, 44),
      ),
    };

    for (final entry in expected.entries) {
      test('${entry.key} places every control where it was measured', () {
        final rails = _resolve(screen: entry.key).rails;
        for (var i = 0; i < entry.value.leading.length; i++) {
          expect(rails.leading[i], _closeToRect(entry.value.leading[i]));
        }
        for (var i = 0; i < entry.value.trailing.length; i++) {
          expect(rails.trailing[i], _closeToRect(entry.value.trailing[i]));
        }
        expect(rails.scrub, _closeToRect(entry.value.scrub));
      });
    }

    test('the third upper control ends exactly on the opponent-card boundary', () {
      // The evaluation note: at 844x390 the slot bottom and the card union top
      // are the same number. Touching is not overlapping, and the assertion
      // below is what makes any drift in either direction fail.
      final decision = _resolve(screen: const Size(844, 390));
      expect(decision.rails.trailing[2].bottom, 132);
      expect(decision.geometry.eastCards.top, 132);
      expect(decision.geometry.westCards.top, 132);
      expect(
        decision.rails.trailing[2].overlaps(decision.geometry.eastCards),
        isFalse,
      );
    });

    test('the Last-to-scrub separations are the owner-accepted figures', () {
      final separations = <Size, double>{
        Size(844, 390): 2,
        Size(914, 411): 11.5,
        Size(926, 428): 20,
      };
      for (final entry in separations.entries) {
        final rails = _resolve(screen: entry.key).rails;
        expect(
          rails.scrub!.top - rails.trailing.last.bottom,
          closeTo(entry.value, 0.01),
          reason: '${entry.key}',
        );
      }
    });
  });

  group('the west-side analysis popover', () {
    test('covers nothing but the west rail cards and the west meld lane', () {
      for (final size in _shortSizes) {
        final decision = _resolve(screen: size);
        final popover = decision.rails.popover!;
        for (final blocked in decision.geometry.popoverBlockers) {
          expect(
            popover.overlaps(blocked),
            isFalse,
            reason: '$popover covers $blocked at $size',
          );
        }
      }
    });

    test('it clears the physical-left rail rather than sitting on it', () {
      for (final size in _shortSizes) {
        final decision = _resolve(screen: size);
        for (final rect in decision.rails.leading) {
          expect(
            decision.rails.popover!.overlaps(rect),
            isFalse,
            reason: '$size',
          );
        }
      }
    });

    test('it honours the contracted 45% and 60% ceilings', () {
      for (final size in _shortSizes) {
        final decision = _resolve(screen: size);
        final popover = decision.rails.popover!;
        expect(popover.width, lessThanOrEqualTo(size.width * 0.45));
        expect(popover.height, lessThanOrEqualTo(size.height * 0.60));
      }
    });

    test('the measured rectangles', () {
      expect(
        _resolve(screen: const Size(844, 390)).rails.popover,
        _closeToRect(const Rect.fromLTRB(44, 0, 211, 234)),
      );
      expect(
        _resolve(screen: const Size(914, 411)).rails.popover,
        _closeToRect(const Rect.fromLTRB(44, 0, 228.5, 246.6)),
      );
      expect(
        _resolve(screen: const Size(926, 428)).rails.popover,
        _closeToRect(const Rect.fromLTRB(44, 0, 231.5, 256.8)),
      );
    });
  });

  group('safe insets are routed on the body the screen actually builds', () {
    test('a horizontal inset shifts the trailing rail and changes nothing else', () {
      for (final insets in const [
        EdgeInsets.only(left: 47),
        EdgeInsets.only(right: 47),
      ]) {
        final decision = _resolve(safeInsets: insets);
        expect(decision.mode, ReplayLayoutMode.short, reason: '$insets');
        expect(decision.body, const Size(797, 390), reason: '$insets');
        expect(decision.rails.trailing.first.right, 797, reason: '$insets');
        expect(
          decision.rails.trailing[3],
          _closeToRect(const Rect.fromLTWH(753, 256, 44, 44)),
          reason: '$insets',
        );
        expect(
          decision.rails.scrub,
          _closeToRect(const Rect.fromLTWH(753, 346, 44, 44)),
          reason: '$insets',
        );
      }
    });

    test('a 47 dp top inset drops the body into compact and refuses short', () {
      final decision = _resolve(safeInsets: const EdgeInsets.only(top: 47));
      expect(decision.body, const Size(844, 343));
      expect(decision.geometry.compact, isTrue);
      expect(decision.mode, ReplayLayoutMode.docked);
      expect(decision.dockedReason, ReplayDockedReason.railDoesNotFit);
    });

    test('even a 24 dp top inset costs the fourth leading slot', () {
      // The bottom edge is where flush placement is actually load-bearing:
      // 844x390 clears 134 dp below the opponent cards against 132 dp of
      // control, so 24 dp of it is the difference between a scrub target and
      // no scrub target.
      //
      // **The named reason moved, and the routing did not.** Before the branch
      // control this size failed as `noScrubSegment`: the eight permanent
      // affordances all seated and the scrub was what ran out of room. A
      // fourth leading slot needs the same 24 dp the scrub did, so now the
      // rail is what fails first and the reason says so. Re-derived from the
      // model rather than adjusted until green — and the outcome the owner
      // accepted, *docked*, is unchanged, which is the assertion that matters.
      final decision = _resolve(safeInsets: const EdgeInsets.only(top: 24));
      expect(decision.body, const Size(844, 366));
      expect(decision.geometry.compact, isFalse);
      expect(decision.rails.leading, hasLength(3));
      expect(decision.rails.trailing, hasLength(5));
      expect(decision.rails.isComplete, isFalse);
      expect(decision.rails.scrub, isNull);
      expect(decision.mode, ReplayLayoutMode.docked);
      expect(decision.dockedReason, ReplayDockedReason.railDoesNotFit);
    });

    test('the fourth control moves reasons, never the routing outcome', () {
      // Sprint 05's accepted safe-inset matrix, as *outcomes*. A fourth
      // leading slot competes for the same vertical room the scrub target
      // needed, so several cells now fail as `railDoesNotFit` where they used
      // to fail as `noScrubSegment` — a different sentence about the same
      // refusal. What the owner accepted was the arrangement each size
      // renders in, and that is what is frozen here.
      //
      // Recorded by resolving the whole matrix against `leadingRailCount = 3`
      // and again against 4: thirty cells, thirty identical outcomes. Stating
      // it as a table rather than a rule is deliberate — a rule derived from
      // the same model it is checking would agree with any drift.
      const short = ReplayLayoutMode.short;
      const docked = ReplayLayoutMode.docked;
      final accepted = <(EdgeInsets, Size), ReplayLayoutMode>{
        for (final size in _shortSizes) (EdgeInsets.zero, size): short,
        (const EdgeInsets.only(top: 24), const Size(844, 390)): docked,
        (const EdgeInsets.only(top: 24), const Size(914, 411)): docked,
        (const EdgeInsets.only(top: 24), const Size(926, 428)): short,
        (const EdgeInsets.only(top: 34), const Size(844, 390)): docked,
        (const EdgeInsets.only(top: 34), const Size(914, 411)): docked,
        (const EdgeInsets.only(top: 34), const Size(926, 428)): short,
        (const EdgeInsets.only(top: 44), const Size(844, 390)): docked,
        (const EdgeInsets.only(top: 44), const Size(914, 411)): docked,
        (const EdgeInsets.only(top: 44), const Size(926, 428)): docked,
        (const EdgeInsets.only(top: 47), const Size(844, 390)): docked,
        (const EdgeInsets.only(top: 47), const Size(914, 411)): docked,
        (const EdgeInsets.only(top: 47), const Size(926, 428)): docked,
        (const EdgeInsets.only(top: 59), const Size(844, 390)): docked,
        (const EdgeInsets.only(top: 59), const Size(914, 411)): docked,
        (const EdgeInsets.only(top: 59), const Size(926, 428)): docked,
        for (final size in _shortSizes)
          (const EdgeInsets.only(left: 47), size): short,
        for (final size in _shortSizes)
          (const EdgeInsets.only(right: 47), size): short,
        (const EdgeInsets.only(bottom: 24), const Size(844, 390)): docked,
        (const EdgeInsets.only(bottom: 24), const Size(914, 411)): docked,
        (const EdgeInsets.only(bottom: 24), const Size(926, 428)): short,
        (const EdgeInsets.only(bottom: 47), const Size(844, 390)): docked,
        (const EdgeInsets.only(bottom: 47), const Size(914, 411)): docked,
        (const EdgeInsets.only(bottom: 47), const Size(926, 428)): docked,
      };

      expect(accepted, hasLength(30));
      for (final entry in accepted.entries) {
        final (insets, size) = entry.key;
        expect(
          _resolve(screen: size, safeInsets: insets).mode,
          entry.value,
          reason: 'routing changed at $size under $insets',
        );
      }
    });

    test('an inset cannot flip the branch unnoticed', () {
      // A6, restated for the collision model: the same screen with and without
      // a system inset must be allowed to disagree, and the reason must say so.
      final clean = _resolve();
      final inset = _resolve(safeInsets: const EdgeInsets.only(top: 47));
      expect(clean.mode, isNot(inset.mode));
      expect(inset.dockedReason, isNotNull);
    });
  });
}
