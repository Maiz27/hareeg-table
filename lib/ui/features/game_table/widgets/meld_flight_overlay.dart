import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../core/cards/card_state.dart';
import '../../../core/cards/card_theme.dart';
import '../../../core/cards/card_view.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../table_card_flight_planner.dart';
import '../table_flight_geometry.dart';

/// In-flight multi-card meld: one fan of cards travelling from a seat's hand
/// strip to that seat's meld lane. Lifecycle is owned by
/// `MeldFlightController` and rendered by [MeldFlightOverlay].
class MeldFlight {
  /// Creates a meld flight.
  const MeldFlight({
    required this.serial,
    required this.seat,
    required this.cards,
    required this.begin,
    required this.end,
    required this.endMeldSlot,
    required this.duration,
  });

  /// Monotonic id used as the overlay's ValueKey so concurrent flights stay
  /// distinct across rebuilds.
  final int serial;

  /// Seat the flight belongs to.
  final PlayerSeat seat;

  /// Cards in the fan, in display order.
  final List<HareegCard> cards;

  /// Start anchor (typically the seat's hand strip).
  final Alignment begin;

  /// End anchor (typically the seat's meld lane).
  final Alignment end;

  /// Resolved landing slot used by the geometry resolver.
  final TableMeldFlightSlot endMeldSlot;

  /// Total flight duration.
  final Duration duration;
}

/// Renders the whole meld as a fanned group flying from the seat's hand to
/// the seat's meld lane. Each card sits at a horizontal offset and a small
/// rotation around the centre card so the fan reads as multiple distinct
/// cards rather than a stack. The whole group lerps along an arc and
/// settles with a tiny scale punch on landing.
class MeldFlightOverlay extends StatelessWidget {
  /// Creates a meld flight overlay.
  const MeldFlightOverlay({
    super.key,
    required this.flight,
    required this.theme,
  });

  /// Flight to render.
  final MeldFlight flight;

  /// Card theme used to paint each card face.
  final HareegCardTheme theme;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final compact = size.height <= 390 || size.width <= 700;
          final cardSize = compact ? const Size(44, 62) : const Size(58, 82);
          final begin = resolveFlightAnchor(
            flight.begin,
            size,
            cardSize,
          );
          final end = resolveFlightAnchor(
            flight.end,
            size,
            cardSize,
            meldSlot: flight.endMeldSlot,
          );
          // Distance-aware arc: bigger lift on cross-table flights, gentler
          // on near-by ones. Same shape as the opening-deal arc so the two
          // animations feel like one family.
          final dx = end.dx - begin.dx;
          final dy = end.dy - begin.dy;
          final distance = math.sqrt(dx * dx + dy * dy);
          final arcHeight = (distance * 0.16).clamp(28.0, 84.0).toDouble();
          final count = flight.cards.length;
          // Fan geometry: cards sit on a horizontal arc spanning the lane
          // width. Centre card carries no rotation; flanks tilt outward.
          final fanSpread = compact ? 26.0 : 34.0;
          final fanGap = count <= 1 ? 0.0 : fanSpread;
          final fanAngle = compact ? 0.08 : 0.10;
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: flight.duration,
            curve: Curves.easeOutCubic,
            builder: (context, value, _) {
              final v = value.clamp(0.0, 1.0).toDouble();
              final offset = Offset.lerp(begin, end, v)!;
              final lifted = math.sin(v * math.pi) * arcHeight;
              // Fan flattens as it lands: at v=0 the cards are fully fanned
              // out, at v=1 they collapse onto the landing slot.
              final fanScale = 1.0 - Curves.easeInCubic.transform(v);
              // Tiny scale punch in the last sliver so the landing reads.
              final double landingScale;
              if (v < 0.86) {
                landingScale = 1.0;
              } else if (v < 0.93) {
                landingScale = 1.0 + (v - 0.86) / 0.07 * 0.045;
              } else {
                landingScale = 1.045 - (v - 0.93) / 0.07 * 0.045;
              }
              // Fade out the very last frames so the materialised meld can
              // pop into place without a visible swap.
              final opacity = v < 0.92
                  ? 1.0
                  : (1 - (v - 0.92) / 0.08).clamp(0.0, 1.0).toDouble();
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: offset.dx,
                    top: offset.dy - lifted,
                    child: Transform.scale(
                      scale: landingScale,
                      child: Opacity(
                        opacity: opacity,
                        child: SizedBox(
                          width: cardSize.width,
                          height: cardSize.height,
                          // Centre the fan over the flight's anchor so the
                          // landing slot stays accurate. Each card is placed
                          // relative to that centre with a horizontal offset
                          // and rotation that taper to zero on landing.
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              for (var i = 0; i < count; i++)
                                _fanCard(
                                  card: flight.cards[i],
                                  cardSize: cardSize,
                                  index: i,
                                  count: count,
                                  fanGap: fanGap,
                                  fanAngle: fanAngle,
                                  fanScale: fanScale,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _fanCard({
    required HareegCard card,
    required Size cardSize,
    required int index,
    required int count,
    required double fanGap,
    required double fanAngle,
    required double fanScale,
  }) {
    // Center-based fan: middle card sits at offset 0 with no rotation; the
    // others spread symmetrically left/right.
    final mid = (count - 1) / 2.0;
    final position = index - mid;
    final dx = position * fanGap * fanScale;
    final angle = position * fanAngle * fanScale;
    return Transform.translate(
      offset: Offset(dx, 0),
      child: Transform.rotate(
        angle: angle,
        child: Material(
          color: Colors.transparent,
          elevation: 12,
          borderRadius: BorderRadius.circular(LoungeTokens.radiusCard),
          child: HareegCardView(
            theme: theme,
            card: card,
            size: cardSize,
            visualState: CardVisualState.selected,
          ),
        ),
      ),
    );
  }
}
