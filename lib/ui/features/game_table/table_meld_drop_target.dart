import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../domain/classic_hareeg/rules/cover_rules.dart';

/// Typed target for a dropped card landing on a specific table meld.
@immutable
class TableMeldDropTarget {
  /// Creates a table-meld drop target.
  const TableMeldDropTarget({
    required this.owner,
    required this.meldIndex,
    this.coverPlacement,
  });

  /// Seat that owns the target meld.
  final PlayerSeat owner;

  /// Index of the target meld in the owner's table meld lane.
  final int meldIndex;

  /// Preferred cover edge when the pointer is over one end of a sequence.
  final CoverPlacement? coverPlacement;

  /// Whether the pointer is currently asking for an edge cover.
  bool get targetsCoverEdge =>
      coverPlacement == CoverPlacement.lowEnd ||
      coverPlacement == CoverPlacement.highEnd;
}

/// Converts table-meld pointer geometry into typed drop targets.
abstract final class TableMeldDropTargetPlanner {
  /// Builds a drop target for the current local pointer position.
  static TableMeldDropTarget targetForLocalPosition({
    required PlayerSeat owner,
    required int meldIndex,
    required int cardCount,
    required Offset localPosition,
    required Size bounds,
    required bool vertical,
    required int quarterTurns,
  }) {
    return TableMeldDropTarget(
      owner: owner,
      meldIndex: meldIndex,
      coverPlacement: coverPlacementForLocalPosition(
        cardCount: cardCount,
        localPosition: localPosition,
        bounds: bounds,
        vertical: vertical,
        quarterTurns: quarterTurns,
      ),
    );
  }

  /// Resolves which cover edge, if any, the pointer is asking for.
  static CoverPlacement? coverPlacementForLocalPosition({
    required int cardCount,
    required Offset localPosition,
    required Size bounds,
    required bool vertical,
    required int quarterTurns,
  }) {
    if (cardCount < 3) {
      return null;
    }
    final sideFacing = quarterTurns % 2 != 0;
    final position = vertical || sideFacing
        ? localPosition.dy
        : localPosition.dx;
    final extent = vertical || sideFacing ? bounds.height : bounds.width;
    if (extent <= 0) {
      return null;
    }
    final fraction = (position / extent).clamp(0.0, 1.0);
    if (fraction <= 0.38) {
      return CoverPlacement.lowEnd;
    }
    if (fraction >= 0.62) {
      return CoverPlacement.highEnd;
    }
    return null;
  }
}
