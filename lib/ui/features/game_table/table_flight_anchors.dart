import 'package:flutter/widgets.dart';

import '../../../domain/classic_hareeg/models/player_seat.dart';

/// Canonical seat-to-table alignment anchors used by every flight overlay.
///
/// The geometry was originally inlined in `game_table_screen.dart`; lifting
/// it here keeps the single-card flight, the opening-deal flight, and the
/// meld flight reading from one model so the overlays can't drift apart.
abstract final class TableFlightAnchors {
  /// Stock pile centre.
  static const Alignment stock = Alignment(-0.86, 0.56);

  /// Discard pile centre.
  static const Alignment discard = Alignment(0, 0);

  /// South hand strip centre. Lifted enough off the bottom so the flight
  /// doesn't clip the hand cards.
  static const Alignment southHand = Alignment(0, 0.82);

  /// Seat meld-lane anchor. Used as the landing zone for cards that fly to
  /// the seat's table side.
  static Alignment seatLane(PlayerSeat seat) {
    return switch (seat) {
      PlayerSeat.south => const Alignment(0, 0.48),
      PlayerSeat.north => const Alignment(0, -0.48),
      PlayerSeat.east => const Alignment(0.68, 0),
      PlayerSeat.west => const Alignment(-0.68, 0),
    };
  }

  /// Seat hand anchor used for single-card flights. South returns the
  /// dedicated hand-strip alignment; remote seats fall back to the seat lane.
  static Alignment seatHand(PlayerSeat seat) {
    return seat == PlayerSeat.south ? southHand : seatLane(seat);
  }

  /// Alignment of the seat's hand strip (back-of-cards row for opponents,
  /// bottom hand strip for south). Differs from [seatHand] for non-south
  /// seats: that helper falls back to the seat's meld-lane anchor, which
  /// would collapse a meld flight's travel distance to zero. Use this anchor
  /// for "cards leaving the hand" animations so the fan actually emerges
  /// from the seat's edge.
  static Alignment seatHandStrip(PlayerSeat seat) {
    return switch (seat) {
      PlayerSeat.south => southHand,
      PlayerSeat.north => const Alignment(0, -0.92),
      PlayerSeat.east => const Alignment(0.92, 0),
      PlayerSeat.west => const Alignment(-0.92, 0),
    };
  }
}
