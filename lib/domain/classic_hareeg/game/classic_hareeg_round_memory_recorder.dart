import '../models/player_seat.dart';
import '../models/playing_card.dart';
import 'classic_hareeg_discard_history.dart';

/// Single write surface for the discard/pickup sync invariant.
///
/// Before this recorder existed, the controller mutated `DiscardHistory`
/// from four different call sites (regular discard, take-previous-discard,
/// return-pending-discard, hard-table forced-return). Each call had to
/// remember to record the right kind of event, leaving the invariant
/// "every discard-pile mutation produces exactly one history event"
/// distributed across the controller. Architecture review NEW #1
/// (2026-05-25) flagged the spread.
///
/// `RoundMemoryRecorder` owns the invariant in one place. Controllers call
/// the named methods on this object and never touch [DiscardHistory]
/// directly. Tests can substitute a recording fake by satisfying this
/// interface.
abstract interface class RoundMemoryRecorder {
  /// Records a discard by [seat] that just landed on the discard pile.
  void onDiscard(PlayerSeat seat, HareegCard card);

  /// Records that [seat] took the previous discard into a pending slot.
  void onTakePreviousDiscard(PlayerSeat seat, HareegCard card);

  /// Reverses the matching pickup when [seat] returns the pending discard.
  void onReturnPendingDiscard(PlayerSeat seat, HareegCard card);
}

/// Default [RoundMemoryRecorder] that writes through to a [DiscardHistory].
final class DiscardHistoryRoundMemoryRecorder implements RoundMemoryRecorder {
  /// Wraps a [DiscardHistory] with the canonical write surface.
  const DiscardHistoryRoundMemoryRecorder(this._history);

  final DiscardHistory _history;

  @override
  void onDiscard(PlayerSeat seat, HareegCard card) {
    _history.recordDiscard(seat, card);
  }

  @override
  void onTakePreviousDiscard(PlayerSeat seat, HareegCard card) {
    _history.recordPickup(seat, card);
  }

  @override
  void onReturnPendingDiscard(PlayerSeat seat, HareegCard card) {
    _history.retract(
      seat: seat,
      card: card,
      kind: DiscardEventKind.pickup,
    );
  }
}
