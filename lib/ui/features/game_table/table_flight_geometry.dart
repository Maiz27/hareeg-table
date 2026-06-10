import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../domain/classic_hareeg/models/player_seat.dart';
import 'animations/deal_choreography.dart';
import 'seat_meld_arrangement.dart';
import 'table_card_flight_planner.dart';

/// Shared seat-hand geometry used by every flight overlay (single-card
/// flight, opening-deal flight, multi-card meld fan). Each surface targets
/// the same hand strip layout, so resolving a slot's position lives in one
/// place. The geometry has no widget-state dependency — it's pure math on
/// the inputs.
Offset resolveSeatHandSlot(
  SeatHandFlightSlot slot,
  Size size,
  Size flightCardSize,
) {
  return switch (slot.seat) {
    PlayerSeat.south => _resolveSouthHandSlot(slot, size, flightCardSize),
    PlayerSeat.north => _resolveNorthHandSlot(slot, size, flightCardSize),
    PlayerSeat.west ||
    PlayerSeat.east => _resolveSideHandSlot(slot, size, flightCardSize),
  };
}

Offset _resolveSouthHandSlot(
  SeatHandFlightSlot slot,
  Size size,
  Size flightCardSize,
) {
  final compact = size.height <= 390 || size.width <= 700;
  final handCardSize = compact ? const Size(36, 50) : const Size(48, 68);
  final controlWidth = compact ? 60.0 : 72.0;
  final bottomHandHeight = handCardSize.height + (compact ? 12 : 18);
  final edgeInset = (size.width * 0.026)
      .clamp(compact ? 14.0 : 20.0, compact ? 30.0 : 52.0)
      .toDouble();
  final handRightInset = controlWidth + edgeInset + (compact ? 10.0 : 16.0);
  final handHorizontalInset = math.max(handRightInset, compact ? 70.0 : 96.0);
  final handBottom = compact ? 0.0 : 2.0;
  final handWidth = math.max(0.0, size.width - handHorizontalInset * 2);
  final count = math.max(1, slot.count);
  final index = slot.index.clamp(0, count - 1).toInt();
  final minGap = handCardSize.width * 0.42;
  final preferredGap = handCardSize.width * 0.78;
  final available = math.max(0.0, handWidth - 8);
  final fittedGap = count <= 1
      ? 0.0
      : ((available - handCardSize.width) / (count - 1))
            .clamp(minGap, preferredGap)
            .toDouble();
  final stripWidth = handCardSize.width + math.max(0, count - 1) * fittedGap;
  final canvasWidth = math.max(stripWidth, available);
  final start = math.max(0.0, (canvasWidth - stripWidth) / 2);
  final handTop = size.height - handBottom - bottomHandHeight;
  final centerX =
      handHorizontalInset + start + index * fittedGap + handCardSize.width / 2;
  final centerY = handTop + bottomHandHeight - 2 - handCardSize.height / 2;
  return centeredFlightOffset(centerX, centerY, flightCardSize);
}

Offset _resolveNorthHandSlot(
  SeatHandFlightSlot slot,
  Size size,
  Size flightCardSize,
) {
  final compact = size.height <= 390 || size.width <= 700;
  final cardSize = compact ? const Size(26, 36) : const Size(32, 44);
  final topInset = (size.height * 0.032)
      .clamp(compact ? 8.0 : 12.0, compact ? 16.0 : 28.0)
      .toDouble();
  final visibleCount = compact ? 9 : 12;
  final shown = math.min(math.max(1, slot.count), visibleCount);
  final index = slot.index.clamp(0, shown - 1).toInt();
  final gap = cardSize.width * 0.38;
  final stackWidth = cardSize.width + (shown - 1) * gap;
  final left = (size.width - stackWidth) / 2;
  final top = topInset + (compact ? 6.0 : 8.0);
  final centerX = left + index * gap + cardSize.width / 2;
  final centerY = top + cardSize.height / 2;
  return centeredFlightOffset(centerX, centerY, flightCardSize);
}

Offset _resolveSideHandSlot(
  SeatHandFlightSlot slot,
  Size size,
  Size flightCardSize,
) {
  final compact = size.height <= 390 || size.width <= 700;
  final cardSize = compact ? const Size(26, 36) : const Size(32, 44);
  final sideRailWidth = compact ? 46.0 : 56.0;
  final edgeInset = (size.width * 0.026)
      .clamp(compact ? 14.0 : 20.0, compact ? 30.0 : 52.0)
      .toDouble();
  final topInset = (size.height * 0.032)
      .clamp(compact ? 8.0 : 12.0, compact ? 16.0 : 28.0)
      .toDouble();
  final sideRailVisibleCount = compact ? 5 : 6;
  final sideRailHeight = cardSize.height + (sideRailVisibleCount - 1) * 14.0;
  final sideRailTop = topInset + cardSize.height + 12;
  final visibleCount = compact ? 8 : 11;
  final shown = math.min(math.max(1, slot.count), visibleCount);
  final index = slot.index.clamp(0, shown - 1).toInt();
  final gap = 16.0;
  final stackHeight = cardSize.height + (shown - 1) * gap;
  final top = sideRailTop + (sideRailHeight - stackHeight) / 2;
  final left = switch (slot.seat) {
    PlayerSeat.west => edgeInset,
    PlayerSeat.east =>
      size.width - edgeInset - sideRailWidth + sideRailWidth - cardSize.width,
    PlayerSeat.north || PlayerSeat.south => 0.0,
  };
  final centerX = left + cardSize.width / 2;
  final centerY = top + index * gap + cardSize.height / 2;
  return centeredFlightOffset(centerX, centerY, flightCardSize);
}

/// Resolves the landing point of a table-meld slot for flight overlays.
///
/// When [slot] carries `laneMeldCardCounts`, the landing point is the centre
/// of that meld's resting slot — computed by the shared [SeatMeldArrangement]
/// the lane itself renders from, so the fan lands exactly where the meld will
/// rest. Without counts it falls back to the lane centre (the legacy anchor).
///
/// NOTE: the lane rect maths below mirrors `PhysicalTablePlayfield` — keep the
/// two in sync (the side-lane width in particular).
Offset resolveTableMeldSlot(
  TableMeldFlightSlot slot,
  Size size,
  Size flightCardSize,
) {
  // Must match PhysicalTablePlayfield's `compact` (tableHeight <= 360) so the
  // meld-slot maths uses the same card sizes/insets the lane renders with;
  // otherwise heights in (360, 390] land the flight off-slot.
  final compact = size.height <= 360 || size.width <= 700;
  final handCardSize = compact ? const Size(36, 50) : const Size(48, 68);
  final opponentCardSize = compact ? const Size(26, 36) : const Size(32, 44);
  final meldCardSize = compact ? const Size(32, 44) : const Size(38, 54);
  final sideMeldCardSize = compact ? const Size(28, 40) : const Size(34, 48);
  final sideRailWidth = compact ? 46.0 : 56.0;
  final edgeInset = (size.width * 0.026)
      .clamp(compact ? 14.0 : 20.0, compact ? 30.0 : 52.0)
      .toDouble();
  final topInset = (size.height * 0.032)
      .clamp(compact ? 8.0 : 12.0, compact ? 16.0 : 28.0)
      .toDouble();
  // South lane geometry, matching the playfield's bottom-anchored meld lane
  // (height includes the expand headroom that sits above the resting cards).
  final southMeldBottom = handCardSize.height + (compact ? 10.0 : 18.0);
  final meldExpandedScale = compact ? 1.16 : 1.26;
  final southMeldHeight =
      meldCardSize.height * meldExpandedScale + (compact ? 12.0 : 16.0);
  final northMeldHeight = compact ? 58.0 : 70.0;
  final northMeldTop =
      topInset + opponentCardSize.height + (compact ? 18.0 : 24.0);
  final sideMeldTop = topInset + (compact ? 2.0 : 4.0);
  final sideMeldBottomSafe = size.height - (compact ? 12.0 : 16.0);
  final sideMeldHeight = math.max(0.0, sideMeldBottomSafe - sideMeldTop);
  final sideMeldColumnWidth =
      sideMeldCardSize.height + (compact ? 8.0 : 10.0);
  final sideMeldColumnGap = compact ? 8.0 : 12.0;
  final sideMeldLanePadding = compact ? 8.0 : 12.0;
  final sideMeldWidth =
      sideMeldColumnWidth * 2 + sideMeldColumnGap + sideMeldLanePadding;
  final sideMeldGap = compact ? 6.0 : 10.0;
  final sideOuter = edgeInset + sideRailWidth + sideMeldGap;
  final horizontalMeldInset = (size.width * 0.25)
      .clamp(compact ? 126.0 : 210.0, compact ? 180.0 : 390.0)
      .toDouble();
  final flatLaneWidth = math.max(0.0, size.width - horizontalMeldInset * 2);

  // Lane rect (outer, before the lane's own padding/border inset).
  final laneRect = switch (slot.seat) {
    PlayerSeat.south => Rect.fromLTWH(
      horizontalMeldInset,
      size.height - southMeldBottom - southMeldHeight,
      flatLaneWidth,
      southMeldHeight,
    ),
    PlayerSeat.north => Rect.fromLTWH(
      horizontalMeldInset,
      northMeldTop,
      flatLaneWidth,
      northMeldHeight,
    ),
    PlayerSeat.west => Rect.fromLTWH(
      sideOuter,
      sideMeldTop,
      sideMeldWidth,
      sideMeldHeight,
    ),
    PlayerSeat.east => Rect.fromLTWH(
      size.width - sideOuter - sideMeldWidth,
      sideMeldTop,
      sideMeldWidth,
      sideMeldHeight,
    ),
  };

  final center = _meldSlotCenter(
    slot: slot,
    laneRect: laneRect,
    compact: compact,
    cardSize: switch (slot.seat) {
      PlayerSeat.south || PlayerSeat.north => meldCardSize,
      PlayerSeat.east || PlayerSeat.west => sideMeldCardSize,
    },
  );

  final laneInset = switch (slot.seat) {
    PlayerSeat.south || PlayerSeat.north => horizontalMeldInset,
    PlayerSeat.east || PlayerSeat.west => 0.0,
  };
  // Normalise the clamp range — when the viewport is narrower than the
  // configured insets plus a card width (tiny test viewports, foldable
  // splits), `minX` can exceed `maxX` and `clamp` throws. Falling back
  // to the viewport centre keeps the flight visible without asserting.
  var minX = laneInset + flightCardSize.width * 0.5;
  var maxX = size.width - laneInset - flightCardSize.width * 0.5;
  if (minX > maxX) {
    minX = maxX = size.width * 0.5;
  }
  final clampedCenterX = center.dx.clamp(minX, maxX);
  return centeredFlightOffset(
    clampedCenterX.toDouble(),
    center.dy,
    flightCardSize,
  );
}

/// Resolves the global centre of a meld slot inside [laneRect]. Uses the
/// shared arrangement when the slot carries lane card counts; otherwise
/// returns the lane centre.
Offset _meldSlotCenter({
  required TableMeldFlightSlot slot,
  required Rect laneRect,
  required bool compact,
  required Size cardSize,
}) {
  final counts = slot.laneMeldCardCounts;
  if (counts.isEmpty) {
    return laneRect.center;
  }
  // The lane insets its content by its padding + 1px border.
  final inset = compact ? 4.0 : 6.0;
  final innerLane = Size(
    math.max(0.0, laneRect.width - inset * 2),
    math.max(0.0, laneRect.height - inset * 2),
  );
  final sideFacing = slot.seat == PlayerSeat.east || slot.seat == PlayerSeat.west;
  final footprints = [
    for (final count in counts)
      SeatMeldArrangement.footprint(
        cardSize: cardSize,
        cardCount: count,
        compact: compact,
        sideFacing: sideFacing,
      ),
  ];
  final layout = sideFacing
      ? SeatMeldArrangement.side(
          laneSize: innerLane,
          footprints: footprints,
          meldGap: compact ? 8.0 : 12.0,
          columnGap: compact ? 8.0 : 12.0,
          growFromRailRight: slot.seat == PlayerSeat.east,
        )
      : SeatMeldArrangement.flat(
          laneSize: innerLane,
          footprints: footprints,
          meldGap: compact ? 7.0 : 10.0,
          rowGap: compact ? 8.0 : 12.0,
          anchorBottom: slot.seat == PlayerSeat.south,
        );
  final localCenter = layout.centerOf(slot.index, innerLane);
  return Offset(
    laneRect.left + inset + localCenter.dx,
    laneRect.top + inset + localCenter.dy,
  );
}

/// Centers a `cardSize` rect on `(centerX, centerY)` and returns its
/// top-left offset.
Offset centeredFlightOffset(double centerX, double centerY, Size cardSize) {
  return Offset(centerX - cardSize.width / 2, centerY - cardSize.height / 2);
}

/// Resolves a flight anchor into a pixel offset. Accepts either a hand slot,
/// a meld slot, or a plain [Alignment]; only one of the slots is honoured at
/// a time.
Offset resolveFlightAnchor(
  Alignment alignment,
  Size size,
  Size cardSize, {
  SeatHandFlightSlot? handSlot,
  TableMeldFlightSlot? meldSlot,
}) {
  if (handSlot != null) {
    return resolveSeatHandSlot(handSlot, size, cardSize);
  }
  if (meldSlot != null) {
    return resolveTableMeldSlot(meldSlot, size, cardSize);
  }
  return Offset(
    ((alignment.x + 1) / 2 * size.width) - cardSize.width / 2,
    ((alignment.y + 1) / 2 * size.height) - cardSize.height / 2,
  );
}
