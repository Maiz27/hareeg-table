import '../../../domain/classic_hareeg/game/classic_hareeg_action.dart';
import '../../../domain/classic_hareeg/models/player_seat.dart';
import '../../core/audio/table_audio.dart';
import '../../core/haptics/table_haptics.dart';

/// Card source used by a table action flight.
enum TableActionFlightSource {
  /// A face-down stock card.
  stockBack,

  /// The visible top discard.
  topDiscard,

  /// The pending discard currently in the acting hand.
  pendingDiscard,

  /// A card currently in the acting hand.
  handCard,
}

/// Destination used by a table action flight.
enum TableActionFlightDestination {
  /// The acting seat's hand.
  seatHand,

  /// The discard pile.
  discardPile,

  /// A table meld lane.
  tableMeld,
}

/// Declarative card-flight request for a table action.
class TableActionFlightPlan {
  /// Creates a table action flight plan.
  const TableActionFlightPlan({
    required this.source,
    required this.destination,
    required this.seat,
    this.cardId,
    this.targetSeat,
    this.targetMeldIndex = 0,
    this.allowFaceDownFallback = false,
  });

  /// Where the visible card comes from.
  final TableActionFlightSource source;

  /// Where the visible card goes.
  final TableActionFlightDestination destination;

  /// Seat performing the action.
  final PlayerSeat seat;

  /// Physical card id when [source] is [TableActionFlightSource.handCard].
  final String? cardId;

  /// Meld owner when [destination] is [TableActionFlightDestination.tableMeld].
  final PlayerSeat? targetSeat;

  /// Meld index when [destination] is [TableActionFlightDestination.tableMeld].
  final int targetMeldIndex;

  /// Whether a hidden card back may be shown if [cardId] is not visible.
  final bool allowFaceDownFallback;
}

/// Presentation result for one Classic Hareeg action.
class TableActionPresentationPlan {
  /// Creates a table action presentation plan.
  const TableActionPresentationPlan({
    required this.sound,
    required this.haptic,
    required this.flight,
  });

  /// Sound cue to play, if any.
  final TableSoundEvent? sound;

  /// Haptic cue to fire, if any.
  final TableHapticEvent? haptic;

  /// Card flight to animate, if any.
  final TableActionFlightPlan? flight;
}

/// Resolves Classic Hareeg actions into table presentation cues.
abstract final class ClassicHareegActionPresentationPlanner {
  /// Presentation cues for a successful human action.
  static TableActionPresentationPlan forHumanAction(String actionId) {
    final action = ClassicHareegActionIds.describe(actionId);
    return TableActionPresentationPlan(
      sound: _soundFor(action),
      haptic: _humanHapticFor(action),
      flight: _humanFlightFor(action),
    );
  }

  /// Presentation cues for a CPU action.
  static TableActionPresentationPlan forCpuAction({
    required PlayerSeat seat,
    required String actionId,
  }) {
    final action = ClassicHareegActionIds.describe(actionId);
    return TableActionPresentationPlan(
      sound: _soundFor(action),
      haptic: null,
      flight: _cpuFlightFor(seat, action),
    );
  }

  static TableActionFlightPlan? _humanFlightFor(
    ClassicHareegActionDescriptor action,
  ) {
    const seat = PlayerSeat.south;
    return switch (action.kind) {
      ClassicHareegActionKind.drawStock => const TableActionFlightPlan(
        source: TableActionFlightSource.stockBack,
        destination: TableActionFlightDestination.seatHand,
        seat: seat,
      ),
      ClassicHareegActionKind.takeDiscard => const TableActionFlightPlan(
        source: TableActionFlightSource.topDiscard,
        destination: TableActionFlightDestination.seatHand,
        seat: seat,
      ),
      ClassicHareegActionKind.returnPendingDiscard =>
        const TableActionFlightPlan(
          source: TableActionFlightSource.pendingDiscard,
          destination: TableActionFlightDestination.discardPile,
          seat: seat,
        ),
      ClassicHareegActionKind.discard ||
      ClassicHareegActionKind.discardBlockedCover ||
      ClassicHareegActionKind.discardJoker => TableActionFlightPlan(
        source: TableActionFlightSource.handCard,
        destination: TableActionFlightDestination.discardPile,
        seat: seat,
        cardId: action.cardId,
      ),
      ClassicHareegActionKind.placeCover
          when action.coverTarget != null &&
              action.coverTarget!.cardIds.isNotEmpty =>
        TableActionFlightPlan(
          source: TableActionFlightSource.handCard,
          destination: TableActionFlightDestination.tableMeld,
          seat: seat,
          cardId: action.coverTarget!.cardIds.first,
          targetSeat: action.coverTarget!.targetSeat,
          targetMeldIndex: action.coverTarget!.meldIndex,
        ),
      ClassicHareegActionKind.replaceJoker
          when action.jokerReplacementTarget != null =>
        TableActionFlightPlan(
          source: TableActionFlightSource.handCard,
          destination: TableActionFlightDestination.tableMeld,
          seat: seat,
          cardId: action.jokerReplacementTarget!.cardId,
          targetSeat: action.jokerReplacementTarget!.targetSeat,
          targetMeldIndex: action.jokerReplacementTarget!.meldIndex,
        ),
      ClassicHareegActionKind.playMeld ||
      ClassicHareegActionKind.playMeldWithJoker
          when action.cardIds.isNotEmpty =>
        TableActionFlightPlan(
          source: TableActionFlightSource.handCard,
          destination: TableActionFlightDestination.tableMeld,
          seat: seat,
          cardId: action.cardIds.first,
          targetSeat: seat,
        ),
      _ => null,
    };
  }

  static TableActionFlightPlan? _cpuFlightFor(
    PlayerSeat seat,
    ClassicHareegActionDescriptor action,
  ) {
    return switch (action.kind) {
      ClassicHareegActionKind.drawStock => TableActionFlightPlan(
        source: TableActionFlightSource.stockBack,
        destination: TableActionFlightDestination.seatHand,
        seat: seat,
      ),
      ClassicHareegActionKind.takeDiscard => TableActionFlightPlan(
        source: TableActionFlightSource.topDiscard,
        destination: TableActionFlightDestination.seatHand,
        seat: seat,
      ),
      ClassicHareegActionKind.returnPendingDiscard => TableActionFlightPlan(
        source: TableActionFlightSource.pendingDiscard,
        destination: TableActionFlightDestination.discardPile,
        seat: seat,
      ),
      ClassicHareegActionKind.discard ||
      ClassicHareegActionKind.discardBlockedCover ||
      ClassicHareegActionKind.discardJoker => TableActionFlightPlan(
        source: TableActionFlightSource.handCard,
        destination: TableActionFlightDestination.discardPile,
        seat: seat,
        cardId: action.cardId,
        allowFaceDownFallback: true,
      ),
      _ => null,
    };
  }

  static TableHapticEvent _humanHapticFor(
    ClassicHareegActionDescriptor action,
  ) {
    return switch (action.kind) {
      ClassicHareegActionKind.drawStock => TableHapticEvent.drawCard,
      ClassicHareegActionKind.returnPendingDiscard =>
        TableHapticEvent.pendingReturn,
      ClassicHareegActionKind.claimFifty => TableHapticEvent.fiftyClaim,
      _ => TableHapticEvent.buttonTap,
    };
  }

  static TableSoundEvent? _soundFor(ClassicHareegActionDescriptor action) {
    return switch (action.kind) {
      ClassicHareegActionKind.drawStock => TableSoundEvent.drawStock,
      ClassicHareegActionKind.takeDiscard => TableSoundEvent.takeDiscard,
      ClassicHareegActionKind.returnPendingDiscard ||
      ClassicHareegActionKind.returnOpeningMelds ||
      ClassicHareegActionKind.returnTablePlay => TableSoundEvent.cardReturn,
      ClassicHareegActionKind.claimFifty => TableSoundEvent.fiftyClaim,
      ClassicHareegActionKind.playMeld ||
      ClassicHareegActionKind.playMeldWithJoker ||
      ClassicHareegActionKind.placeCover ||
      ClassicHareegActionKind.replaceJoker => TableSoundEvent.meldPlace,
      ClassicHareegActionKind.discard ||
      ClassicHareegActionKind.discardBlockedCover ||
      ClassicHareegActionKind.discardJoker => TableSoundEvent.discardCard,
      ClassicHareegActionKind.usePendingDiscard ||
      ClassicHareegActionKind.unknown => null,
    };
  }
}
