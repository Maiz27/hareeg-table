/// Seat positions around the default four-player Classic Hareeg table.
enum PlayerSeat {
  /// Human-facing lower seat in the default table layout.
  south,

  /// Next seat after south in anti-clockwise order.
  east,

  /// Seat opposite south.
  north,

  /// Final seat before returning to south in anti-clockwise order.
  west;

  /// Seat that acts after this seat in Classic Hareeg's anti-clockwise order.
  PlayerSeat get nextAntiClockwise {
    return switch (this) {
      PlayerSeat.south => PlayerSeat.east,
      PlayerSeat.east => PlayerSeat.north,
      PlayerSeat.north => PlayerSeat.west,
      PlayerSeat.west => PlayerSeat.south,
    };
  }

  /// Parses a saved seat name.
  static PlayerSeat? fromName(String? name) {
    if (name == null) {
      return null;
    }

    for (final seat in PlayerSeat.values) {
      if (seat.name == name) {
        return seat;
      }
    }

    return null;
  }
}
