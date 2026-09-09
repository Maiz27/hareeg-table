import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Which arrangement the replay screen renders.
enum ReplayLayoutMode {
  /// Table, transport and analysis stacked in permanent bands.
  docked,

  /// Full-bleed table with fixed 44 dp edge rails over it.
  short,
}

/// Why a body ended up docked.
///
/// Named rather than inferred: "there is nowhere to put the transport rail" and
/// "there is nowhere to put a scrub target" are different failures, and a test
/// that cannot tell them apart cannot prove the guard works for the stated
/// reason.
enum ReplayDockedReason {
  /// The body is tall enough for the docked bands.
  tallBody,

  /// The body is taller than it is wide. The edge rails are a landscape
  /// arrangement and the owner pinned portrait bodies to docked.
  portraitBody,

  /// The collision map cannot seat all nine permanent affordances.
  railDoesNotFit,

  /// The collision map seats the rails but leaves no scrub segment.
  noScrubSegment,
}

/// A closed vertical interval, in body-local coordinates.
@immutable
class _Span {
  const _Span(this.start, this.end);

  final double start;
  final double end;

  double get extent => end - start;
}

/// Body-local projection of [PhysicalTablePlayfield]'s protected geometry.
///
/// **This is duplicated deterministic math, not a shared implementation.** It
/// restates the playfield's layout arithmetic because the HUD has to know where
/// every protected surface will land *before* the table is laid out, and the
/// contract pins that file to the `showSouthControls` change alone.
///
/// Duplication is only safe because it is guarded: `replay_hand_span_parity_test`
/// compares every rectangle here against the actual rendered `RenderBox` at
/// every contracted size, in both languages, and around the compact boundaries.
/// If the table's math ever moves, that test fails before any overlap claim is
/// made on top of a stale projection.
///
/// Every opponent-card union is projected at the implementation's **maximum
/// visible card count**, never the current frame's. Two reasons, both
/// load-bearing: the HUD must be safe on the most crowded table the fixture can
/// produce, and a map that tracked the live count would make the rails jump
/// around as cards are played.
@immutable
class ReplayTableGeometry {
  const ReplayTableGeometry._({
    required this.body,
    required this.compact,
    required this.southHand,
    required this.stock,
    required this.discardHit,
    required this.northMeldLane,
    required this.westMeldLane,
    required this.eastMeldLane,
    required this.southMeldLane,
    required this.northCards,
    required this.westCards,
    required this.eastCards,
  });

  /// Projects the table for a playfield filling [body].
  factory ReplayTableGeometry.project(Size body) {
    final w = body.width;
    final h = body.height;
    final compact = h <= 360 || w <= 700;

    final tableCard = compact ? const Size(40, 56) : const Size(50, 70);
    final meldCard = compact ? const Size(32, 44) : const Size(38, 54);
    final sideMeldCard = compact ? const Size(28, 40) : const Size(34, 48);
    final handCard = compact ? const Size(36, 50) : const Size(48, 68);
    final opponentCard = compact ? const Size(26, 36) : const Size(32, 44);

    final sideRailWidth = compact ? 46.0 : 56.0;
    final controlWidth = compact ? 60.0 : 72.0;
    final bottomHandHeight = handCard.height + (compact ? 12 : 18);
    final edgeInset = (w * 0.026)
        .clamp(compact ? 14.0 : 20.0, compact ? 30.0 : 52.0)
        .toDouble();
    final topInset = (h * 0.032)
        .clamp(compact ? 8.0 : 12.0, compact ? 16.0 : 28.0)
        .toDouble();

    final stockBottom = compact ? 6.0 : 10.0;
    final stockReservedHeight = tableCard.height + (compact ? 32 : 42);
    final southMeldBottom = handCard.height + (compact ? 10.0 : 18.0);
    final southMeldHeight =
        meldCard.height * (compact ? 1.16 : 1.26) + (compact ? 12.0 : 16.0);

    final sideRailVisibleCount = compact ? 5 : 6;
    const sideRailGap = 16.0;
    final sideRailHeight =
        opponentCard.height + (sideRailVisibleCount - 1) * sideRailGap;
    final sideRailMinTop =
        topInset + opponentCard.height + (compact ? 8.0 : 12.0);
    final sideRailMaxTop =
        h -
        stockBottom -
        stockReservedHeight -
        sideRailHeight -
        (compact ? 8.0 : 12.0);
    final sideRailTop = ((h - sideRailHeight) * 0.5)
        .clamp(sideRailMinTop, math.max(sideRailMinTop, sideRailMaxTop))
        .toDouble();

    final sideMeldTop = topInset + (compact ? 2.0 : 4.0);
    final sideMeldBottomSafe = h - (compact ? 12.0 : 16.0);
    final sideMeldHeight = math.max(0.0, sideMeldBottomSafe - sideMeldTop);
    final sideMeldColumnWidth = sideMeldCard.height + (compact ? 8.0 : 10.0);
    final sideMeldColumnGap = compact ? 8.0 : 12.0;
    final sideMeldLanePadding = compact ? 8.0 : 12.0;
    final sideMeldWidth =
        sideMeldColumnWidth * 2 + sideMeldColumnGap + sideMeldLanePadding;
    final sideMeldGap = compact ? 6.0 : 10.0;
    final horizontalMeldInset = (w * 0.25)
        .clamp(compact ? 126.0 : 210.0, compact ? 180.0 : 390.0)
        .toDouble();

    final pileWidth = tableCard.width + (compact ? 34 : 44);
    final pileHeight = tableCard.height + (compact ? 30 : 40);
    final discardHitWidth = pileWidth + (compact ? 60 : 90);
    final discardHitHeight = pileHeight + (compact ? 50 : 70);

    final handRightInset = controlWidth + edgeInset + (compact ? 10.0 : 16.0);
    final handHorizontalInset = math.max(handRightInset, compact ? 70.0 : 96.0);

    // North rail: a full-width alignment box that centres a bounded cue frame.
    // Only the card surfaces are protected content (the alignment box is empty
    // space), so this projects the cards, never the box.
    final northVisible = compact ? 9 : 12;
    final northGap = opponentCard.width * 0.38;
    final northStackWidth = opponentCard.width + (northVisible - 1) * northGap;
    final northCueHeight = opponentCard.height + (compact ? 14.0 : 18.0);
    final northCardsTop = topInset + (northCueHeight - opponentCard.height) / 2;

    // Side rails: the cue frame is clamped to the rail box, and at the maximum
    // visible count the card stack fills it exactly.
    final sideCueWidth = math.min(
      opponentCard.width + (compact ? 14.0 : 18.0),
      sideRailWidth,
    );
    final sideStackHeight =
        opponentCard.height + (sideRailVisibleCount - 1) * sideRailGap;
    final sideCueHeight = math.min(
      sideStackHeight + (compact ? 18.0 : 24.0),
      sideRailHeight,
    );
    final sideCardsTop = sideRailTop + (sideCueHeight - sideStackHeight) / 2;
    final sideCardsInset = (sideCueWidth - opponentCard.width) / 2;

    return ReplayTableGeometry._(
      body: body,
      compact: compact,
      southHand: Rect.fromLTRB(
        handHorizontalInset,
        h - (compact ? 0.0 : 2.0) - bottomHandHeight,
        w - handHorizontalInset,
        h - (compact ? 0.0 : 2.0),
      ),
      stock: Rect.fromLTWH(
        compact ? 6.0 : 10.0,
        h - stockBottom - (tableCard.height + 10),
        tableCard.width + 12,
        tableCard.height + 10,
      ),
      discardHit: Rect.fromLTWH(
        (w - discardHitWidth) * 0.5,
        (h - discardHitHeight) * 0.5,
        discardHitWidth,
        discardHitHeight,
      ),
      northMeldLane: Rect.fromLTWH(
        horizontalMeldInset,
        topInset + opponentCard.height + (compact ? 18 : 24),
        w - horizontalMeldInset * 2,
        compact ? 58 : 70,
      ),
      westMeldLane: Rect.fromLTWH(
        edgeInset + sideRailWidth + sideMeldGap,
        sideMeldTop,
        sideMeldWidth,
        sideMeldHeight,
      ),
      eastMeldLane: Rect.fromLTWH(
        w - edgeInset - sideRailWidth - sideMeldGap - sideMeldWidth,
        sideMeldTop,
        sideMeldWidth,
        sideMeldHeight,
      ),
      southMeldLane: Rect.fromLTWH(
        horizontalMeldInset,
        h - southMeldBottom - southMeldHeight,
        w - horizontalMeldInset * 2,
        southMeldHeight,
      ),
      northCards: Rect.fromLTWH(
        (w - northStackWidth) / 2,
        northCardsTop,
        northStackWidth,
        opponentCard.height,
      ),
      westCards: Rect.fromLTWH(
        edgeInset + sideCardsInset,
        sideCardsTop,
        opponentCard.width,
        sideStackHeight,
      ),
      eastCards: Rect.fromLTWH(
        w - edgeInset - sideCueWidth + sideCardsInset,
        sideCardsTop,
        opponentCard.width,
        sideStackHeight,
      ),
    );
  }

  /// The box the table was projected for.
  final Size body;

  /// Whether the playfield renders its compact card sizes.
  final bool compact;

  /// Outer `SouthHandFan` rectangle — the reviewer's own seat.
  final Rect southHand;

  /// Stock pile.
  final Rect stock;

  /// The discard pile's forgiving hit rectangle.
  final Rect discardHit;

  /// North seat meld lane (content and drop lane).
  final Rect northMeldLane;

  /// West seat meld lane (content and drop lane).
  final Rect westMeldLane;

  /// East seat meld lane (content and drop lane).
  final Rect eastMeldLane;

  /// South seat meld lane (content and drop lane).
  final Rect southMeldLane;

  /// Union of the north seat's rendered face-down cards.
  final Rect northCards;

  /// Union of the west seat's rendered face-down cards.
  final Rect westCards;

  /// Union of the east seat's rendered face-down cards.
  final Rect eastCards;

  /// Everything a permanent HUD rectangle may never intersect.
  ///
  /// Opponent seats contribute their **rendered cards**, never the full-width
  /// alignment container: covering empty alignment space hides nothing, and
  /// treating the container as content would make every edge placement
  /// impossible. Meld lanes contribute their whole box, which is both the
  /// visible clip and the drop lane.
  List<Rect> get protectedRects => <Rect>[
    southHand,
    stock,
    discardHit,
    northMeldLane,
    westMeldLane,
    eastMeldLane,
    southMeldLane,
    northCards,
    westCards,
    eastCards,
  ];

  /// The two surfaces the owner allowed the west-side analysis popover to cover
  /// while it is open. Everything else in [protectedRects] stays inviolable.
  List<Rect> get popoverCoverable => <Rect>[westCards, westMeldLane];

  /// Protected content the popover must still avoid.
  ///
  /// Listed rather than filtered out of [protectedRects]: two seats can project
  /// to equal rectangles on a symmetric body, and a value-equality filter would
  /// then release one the owner never released.
  List<Rect> get popoverBlockers => <Rect>[
    southHand,
    stock,
    discardHit,
    northMeldLane,
    eastMeldLane,
    southMeldLane,
    northCards,
    eastCards,
  ];
}

/// Where every permanent HUD affordance goes, in body-local coordinates.
@immutable
class ReplayHudRails {
  /// Creates a rail placement.
  const ReplayHudRails({
    required this.leading,
    required this.trailing,
    required this.scrub,
    required this.scrubOverlay,
    required this.popover,
  });

  /// Physical-left column, top to bottom: Back, First, Analysis, Branch.
  final List<Rect> leading;

  /// Physical-right column, top to bottom: previous round, previous step, next
  /// step, then — after the measured gap the opponent cards occupy — next
  /// round, last.
  final List<Rect> trailing;

  /// The single collision-free scrub target, or null when none survives.
  final Rect? scrub;

  /// Where the expanded scrubber may open, or null when nowhere may.
  ///
  /// A29's overlay is grandfathered but its rectangle is not: while open it may
  /// cover the rendered South hand and nothing else. This is the bottom-
  /// anchored band inside the hand that clears the side meld lanes, the south
  /// meld lane, and every permanent control.
  final Rect? scrubOverlay;

  /// Bounded rectangle the expanded analysis popover is allowed to fill, or
  /// null when none survives.
  final Rect? popover;

  /// Whether the full permanent inventory is seated.
  bool get isComplete =>
      leading.length == ReplayHudLayout.leadingRailCount &&
      trailing.length == ReplayHudLayout.trailingRailCount;

  /// Every permanent rectangle, in focus order.
  List<Rect> get permanent => <Rect>[...leading, ...trailing, ?scrub];
}

/// The outcome of the branch decision, with the measurements behind it.
@immutable
class ReplayLayoutDecision {
  /// Creates a decision.
  const ReplayLayoutDecision({
    required this.mode,
    required this.dockedReason,
    required this.dockedBodyHeight,
    required this.body,
    required this.geometry,
    required this.rails,
  });

  /// The arrangement to render.
  final ReplayLayoutMode mode;

  /// Why, when [mode] is [ReplayLayoutMode.docked]; null when short.
  final ReplayDockedReason? dockedReason;

  /// The height the docked layout would have had.
  final double dockedBodyHeight;

  /// The box the short table is laid out in.
  final Size body;

  /// The projected protected geometry both the routing and the HUD consume.
  final ReplayTableGeometry geometry;

  /// The placement the HUD renders at.
  final ReplayHudRails rails;

  /// Width available to the HUD.
  double get bodyWidth => body.width;
}

/// Pure geometry for the replay HUD.
///
/// Flutter-free apart from [Size], [Rect] and [EdgeInsets] (A48), so the branch
/// decision and the collision map are unit-tested directly instead of inferred
/// from a pumped tree.
class ReplayHudLayout {
  const ReplayHudLayout._();

  /// Bodies below this are candidates for the short layout.
  static const double shortBodyThreshold = 520;

  /// The touch-target floor. Never traded away, and now also the rail width:
  /// the rails are icon-only columns, so no localized label can widen them.
  static const double minTapTarget = 44;

  /// The docked layout's app bar. Material's `kToolbarHeight`, restated here so
  /// this file needs no widget import.
  static const double dockedAppBarHeight = 56;

  /// Permanent affordances in the physical-left column.
  ///
  /// Four since branch-and-play. The fourth is **appended** rather than
  /// inserted: [_slots] packs greedily downward from the top of each free run,
  /// so the three Sprint 05 rectangles are the same three rectangles and the
  /// new one takes the next free cell. That is the property
  /// `replay_hud_layout_test` asserts rather than assumes.
  static const int leadingRailCount = 4;

  /// Permanent affordances in the physical-right column.
  static const int trailingRailCount = 5;

  /// Ceiling on the expanded analysis popover, as a fraction of the body.
  static const double popoverMaxWidthFraction = 0.45;

  /// Ceiling on the expanded analysis popover, as a fraction of the body.
  static const double popoverMaxHeightFraction = 0.60;

  /// A29's ceiling on the transient expanded scrubber.
  static const double scrubOverlayMaxHeight = 64;

  /// Layout arithmetic is exact here — 88 + 44 lands on the opponent-card
  /// boundary at 844x390 — so the tolerance only absorbs float representation,
  /// never a real overlap.
  static const double _epsilon = 1e-9;

  /// The height the docked layout *would* have, whether or not it is chosen.
  ///
  /// This is the stable input the branch decision is taken on. Deciding from
  /// the rendered body would be circular: choosing short removes the app bar,
  /// which grows the body, which can then measure as tall.
  static double dockedBodyHeight({
    required Size screen,
    required EdgeInsets safeInsets,
  }) {
    final height = screen.height - dockedAppBarHeight - safeInsets.vertical;
    return height < 0 ? 0 : height;
  }

  /// The body the short layout gets: the screen minus the same insets
  /// `SafeArea` consumes, with no app bar. This is the exact box the full-bleed
  /// table is laid out in, so routing and layout cannot disagree about it.
  static Size shortBodySize({
    required Size screen,
    required EdgeInsets safeInsets,
  }) {
    return Size(
      math.max(0, screen.width - safeInsets.horizontal),
      math.max(0, screen.height - safeInsets.vertical),
    );
  }

  /// Free vertical runs inside the column `[left, left + width]`.
  static List<_Span> _freeSpans({
    required double left,
    required double width,
    required double height,
    required List<Rect> blockers,
  }) {
    final right = left + width;
    final spans = <_Span>[];
    for (final blocker in blockers) {
      if (blocker.right > left + _epsilon && blocker.left < right - _epsilon) {
        spans.add(_Span(blocker.top, blocker.bottom));
      }
    }
    if (spans.isEmpty) {
      return [_Span(0, height)];
    }
    spans.sort((a, b) => a.start.compareTo(b.start));

    final merged = <_Span>[];
    var start = spans.first.start;
    var end = spans.first.end;
    for (final span in spans.skip(1)) {
      if (span.start <= end + _epsilon) {
        end = math.max(end, span.end);
      } else {
        merged.add(_Span(start, end));
        start = span.start;
        end = span.end;
      }
    }
    merged.add(_Span(start, end));

    final free = <_Span>[];
    var cursor = 0.0;
    for (final span in merged) {
      if (span.start > cursor + _epsilon) {
        free.add(_Span(cursor, math.min(span.start, height)));
      }
      cursor = math.max(cursor, span.end);
      if (cursor >= height) break;
    }
    if (cursor < height - _epsilon) {
      free.add(_Span(cursor, height));
    }
    return free.where((span) => span.extent > _epsilon).toList(growable: false);
  }

  /// 44 x 44 slots packed downward from the top of each free run.
  static List<Rect> _slots({
    required double left,
    required double height,
    required List<Rect> blockers,
    required int take,
  }) {
    final slots = <Rect>[];
    for (final span in _freeSpans(
      left: left,
      width: minTapTarget,
      height: height,
      blockers: blockers,
    )) {
      var top = span.start;
      while (top + minTapTarget <= span.end + _epsilon && slots.length < take) {
        slots.add(Rect.fromLTWH(left, top, minTapTarget, minTapTarget));
        top += minTapTarget;
      }
      if (slots.length >= take) break;
    }
    return slots;
  }

  /// The bottom-most 44 x 44 segment still free in the column.
  static Rect? _bottomMostSlot({
    required double left,
    required double height,
    required List<Rect> blockers,
  }) {
    final free = _freeSpans(
      left: left,
      width: minTapTarget,
      height: height,
      blockers: blockers,
    );
    if (free.isEmpty) return null;
    final last = free.last;
    if (last.extent < minTapTarget - _epsilon) return null;
    return Rect.fromLTWH(
      left,
      last.end - minTapTarget,
      minTapTarget,
      minTapTarget,
    );
  }

  /// The largest rectangle anchored just inside the physical-left rail that
  /// covers nothing except the two surfaces the owner released.
  ///
  /// Derived from the measured blockers rather than chosen: the candidate right
  /// edges are the blockers' own left edges, so a table change moves the
  /// popover instead of silently letting it cover something new.
  static Rect? _popover(ReplayTableGeometry geometry) {
    final body = geometry.body;
    final left = minTapTarget;
    final maxWidth = body.width * popoverMaxWidthFraction;
    final maxHeight = body.height * popoverMaxHeightFraction;
    final blockers = geometry.popoverBlockers;

    final candidates = <double>{left + maxWidth};
    for (final blocker in blockers) {
      if (blocker.left > left + _epsilon &&
          blocker.left < left + maxWidth - _epsilon) {
        candidates.add(blocker.left);
      }
    }

    Rect? best;
    for (final right in candidates) {
      if (right - left < minTapTarget) continue;
      var bottom = math.min(body.height, maxHeight);
      for (final blocker in blockers) {
        if (blocker.right > left + _epsilon &&
            blocker.left < right - _epsilon) {
          bottom = math.min(bottom, blocker.top);
        }
      }
      if (bottom < minTapTarget) continue;
      final rect = Rect.fromLTRB(left, 0, right, bottom);
      if (best == null ||
          rect.width * rect.height > best.width * best.height + _epsilon) {
        best = rect;
      }
    }
    return best;
  }

  /// The band the expanded scrubber may occupy.
  ///
  /// Derived from the hand it is allowed to cover rather than from the body:
  /// it is bottom-anchored to the rendered South hand, clipped horizontally to
  /// the gap between the two side meld lanes, and started below the south meld
  /// lane. Returns null when no such band exists, which routes the size docked
  /// rather than widening the exception — the alternative would be covering
  /// stock, melds or a permanent control, and that is an owner decision.
  static Rect? _scrubOverlay(ReplayTableGeometry geometry, List<Rect> rails) {
    final hand = geometry.southHand;
    final left = math.max(hand.left, geometry.westMeldLane.right);
    final right = math.min(hand.right, geometry.eastMeldLane.left);
    final bottom = hand.bottom;
    final top = math.max(
      math.max(hand.top, geometry.southMeldLane.bottom),
      bottom - scrubOverlayMaxHeight,
    );
    if (right - left < minTapTarget || bottom - top < minTapTarget) {
      return null;
    }

    final rect = Rect.fromLTRB(left, top, right, bottom);
    // Everything the ruling forbids, checked rather than reasoned about: the
    // derivation above only subtracts the meld lanes, so the rest has to be
    // proven clear or the band is refused.
    final forbidden = <Rect>[
      geometry.stock,
      geometry.discardHit,
      geometry.northMeldLane,
      geometry.westMeldLane,
      geometry.eastMeldLane,
      geometry.southMeldLane,
      geometry.northCards,
      geometry.westCards,
      geometry.eastCards,
      ...rails,
    ];
    for (final blocked in forbidden) {
      if (rect.overlaps(blocked)) return null;
    }
    return rect;
  }

  /// Seats the permanent inventory in the two edge columns.
  static ReplayHudRails placeRails(ReplayTableGeometry geometry) {
    final body = geometry.body;
    final blockers = geometry.protectedRects;

    final leading = _slots(
      left: 0,
      height: body.height,
      blockers: blockers,
      take: leadingRailCount,
    );
    final trailing = _slots(
      left: body.width - minTapTarget,
      height: body.height,
      blockers: blockers,
      take: trailingRailCount,
    );

    // The scrub segment subtracts the permanent controls as well as the
    // protected content: an eligible segment cannot sit under a button.
    final scrub = trailing.length < trailingRailCount
        ? null
        : _bottomMostSlot(
            left: body.width - minTapTarget,
            height: body.height,
            blockers: [...blockers, ...trailing],
          );

    final popover = _popover(geometry);

    return ReplayHudRails(
      leading: leading,
      trailing: trailing,
      scrub: scrub,
      scrubOverlay: _scrubOverlay(geometry, [
        ...leading,
        ...trailing,
        ?scrub,
        ?popover,
      ]),
      popover: popover,
    );
  }

  /// Classifies a viewport and places the HUD in one pass.
  ///
  /// The screen resolves **once** through here and hands the resulting
  /// [ReplayLayoutDecision] to both the branch and the rendered HUD. Nothing
  /// recomputes after branching, so the collision map and the rails cannot
  /// disagree about where anything is.
  static ReplayLayoutDecision resolveFor({
    required Size screen,
    required EdgeInsets safeInsets,
  }) {
    final body = shortBodySize(screen: screen, safeInsets: safeInsets);
    final geometry = ReplayTableGeometry.project(body);
    final rails = placeRails(geometry);
    final docked = dockedBodyHeight(screen: screen, safeInsets: safeInsets);

    ReplayLayoutMode mode;
    ReplayDockedReason? reason;

    if (docked >= shortBodyThreshold) {
      mode = ReplayLayoutMode.docked;
      reason = ReplayDockedReason.tallBody;
    } else if (body.width <= body.height) {
      // The rails are a landscape arrangement, and the owner pinned portrait
      // bodies to the repaired docked layout. Stated as an orientation test
      // rather than a width literal, which the O1 ruling prohibits.
      mode = ReplayLayoutMode.docked;
      reason = ReplayDockedReason.portraitBody;
    } else if (!rails.isComplete) {
      mode = ReplayLayoutMode.docked;
      reason = ReplayDockedReason.railDoesNotFit;
    } else if (rails.scrub == null ||
        rails.scrubOverlay == null ||
        rails.popover == null) {
      mode = ReplayLayoutMode.docked;
      reason = ReplayDockedReason.noScrubSegment;
    } else {
      mode = ReplayLayoutMode.short;
      reason = null;
    }

    return ReplayLayoutDecision(
      mode: mode,
      dockedReason: reason,
      dockedBodyHeight: docked,
      body: body,
      geometry: geometry,
      rails: rails,
    );
  }
}
