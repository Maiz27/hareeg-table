import 'package:flutter/material.dart';

import '../../../../domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import '../../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../../domain/classic_hareeg/replay/review_observation.dart';
import '../../../core/cards/card_theme.dart';
import '../../game_table/table_mode.dart';
import '../../game_table/widgets/physical_table_playfield.dart';

/// Every interactive hook the table exposes, all switched off.
///
/// One value rather than forty inline `(_) {}` closures at the call site: a new
/// affordance added to the table shows up here as a compile error, which is
/// what stops review quietly becoming playable one parameter at a time.
class PassiveTableInteraction {
  /// Creates the disabled bundle.
  const PassiveTableInteraction();

  /// Prefix for the debug-only pointer-delivery trace.
  ///
  /// The trace is emitted at the table boundary rather than from these hooks.
  /// An action hook cannot observe delivery here: review passes
  /// `canTakeDiscard: false`, so `TableDiscardPile` builds its detector with
  /// `onTap: null` and no hook can fire even when the pointer arrives exactly
  /// where it should. A disabled callback staying silent is not evidence that
  /// the pointer failed to arrive.
  static const String traceTag = 'replay-passive-table';

  /// Ignores a tapped card.
  void onCard(HareegCard card) {}

  /// Ignores a hand reorder.
  void onReorder(HareegCard card, int targetIndex) {}

  /// Refuses any card-level affordance.
  bool cardNever(HareegCard card) => false;

  /// Refuses any meld drop.
  bool meldDropNever(HareegCard card, TableMeldDropTarget target) => false;

  /// Refuses any meld retraction.
  bool meldRetractNever(PlayerSeat owner, int meldIndex) => false;

  /// Ignores a meld drop.
  void onMeldDrop(HareegCard card, TableMeldDropTarget target) {}

  /// Ignores a meld retraction.
  void onMeldRetract(PlayerSeat owner, int meldIndex) {}

  /// Ignores a control press.
  void onControl() {}

  /// Ignores a meld suggestion.
  void onSuggestion(String actionId) {}
}

/// The real table, rendered from a reconstructed position, with nothing live.
///
/// This is deliberately the same [PhysicalTablePlayfield] a live match uses,
/// not a review-shaped imitation of it: the whole point of reviewing on the
/// real table is that the player recognises what they are looking at.
///
/// Passivity is not hard-coded here. It is read from [mode]'s capabilities, so
/// the mode table is the single place that decides what a review surface may
/// do — and a mode that would allow input is refused outright rather than
/// quietly rendered as if it were passive.
class ReviewTablePlayfield extends StatelessWidget {
  /// Creates a passive table for [snapshot].
  ReviewTablePlayfield({
    required this.mode,
    required this.snapshot,
    required this.theme,
    required this.fiftySecondsRemaining,
    super.key,
  }) {
    final capabilities = mode.capabilities;
    if (capabilities.acceptsHumanInput || capabilities.runsCpuTurns) {
      throw ArgumentError.value(
        mode,
        'mode',
        'A review table must be a mode that accepts no input and runs no CPU '
            'turns.',
      );
    }
  }

  /// The table mode this surface is running as.
  final TableMode mode;

  /// Reconstructed position to render.
  final ClassicHareegMatchSnapshot snapshot;

  /// Active card theme.
  final HareegCardTheme theme;

  /// Seconds left on an open Fifty window, or null.
  final int? fiftySecondsRemaining;

  static const _passive = PassiveTableInteraction();

  /// Records that a pointer entered the table's hit-test path, in debug builds
  /// only.
  ///
  /// This proves delivery and nothing else. It enables no action: every `can…`
  /// predicate stays false, every hook stays a no-op, and [Listener] has no
  /// gesture recognizer, so it observes the pointer without competing for it or
  /// blocking anything beneath. In a release build the assert and everything
  /// inside it are gone.
  static void _traceDelivery(PointerDownEvent event) {
    assert(() {
      debugPrint('${PassiveTableInteraction.traceTag}: pointerDown');
      return true;
    }());
  }

  @override
  Widget build(BuildContext context) {
    final south = snapshot.hands[reviewPerspectiveSeat] ?? const <HareegCard>[];

    return Listener(
      // Translucent, never opaque: the listener adds itself to the hit path so
      // a pointer anywhere over the table is recorded, and returns false so it
      // absorbs nothing and hides nothing below it.
      behavior: HitTestBehavior.translucent,
      onPointerDown: _traceDelivery,
      child: _playfield(south),
    );
  }

  Widget _playfield(List<HareegCard> south) {
    return PhysicalTablePlayfield(
      // The meld and opening-requirement chip describe a decision the
      // reviewer cannot make. On a passive table it is not just inert, it
      // invites an action that will never happen.
      showSouthControls: false,
      theme: theme,
      stockCount: snapshot.stock.length,
      discardPile: snapshot.discardPile,
      topDiscard: snapshot.discardPile.isEmpty
          ? null
          : snapshot.discardPile.last,
      pendingDiscard: snapshot.pendingDiscard,
      cardCounts: {
        for (final seat in PlayerSeat.values)
          seat: (snapshot.hands[seat] ?? const []).length,
      },
      tableMelds: snapshot.tableMelds,
      southCards: south,
      selectedIds: const {},
      onCardTap: _passive.onCard,
      onCardLongPress: _passive.onCard,
      onReorderHand: _passive.onReorder,
      canDiscardCard: _passive.cardNever,
      canPlayCardOnTable: _passive.cardNever,
      canPlaceMeldOnTable: _passive.cardNever,
      canPlayCardOnMeld: _passive.meldDropNever,
      canRetractMeld: _passive.meldRetractNever,
      onDiscardCard: _passive.onCard,
      onPlayCardOnTable: _passive.onCard,
      onPlayCardOnMeld: _passive.onMeldDrop,
      onRetractMeld: _passive.onMeldRetract,
      canDrawStock: false,
      canTakeDiscard: false,
      canReturnDiscard: false,
      canClaimFifty: false,
      canReturnOpeningMelds: false,
      onDrawStock: _passive.onControl,
      onTakeDiscard: _passive.onControl,
      onReturnDiscard: _passive.onControl,
      onClaimFifty: _passive.onControl,
      onReturnOpeningMelds: _passive.onControl,
      fiftySecondsRemaining: fiftySecondsRemaining,
      fiftyTotalSeconds: snapshot.setup.fiftyTimerSeconds,
      fiftyPulse: false,
      meldRequirement: snapshot.openingState?.currentRequirement ?? 0,
      meldSelectionValue: 0,
      meldSelectionValid: false,
      meldSelectionHasOpened:
          snapshot.openingState?.hasOpened(reviewPerspectiveSeat) ?? false,
      onPlaySelectedMeld: null,
      meldSuggestions: const [],
      showMeldSuggestions: false,
      onMeldSuggestion: _passive.onSuggestion,
      // The player is never "on turn" here, and nothing is thinking: review is
      // a still image of a decision that already happened.
      isHumanTurn: mode.capabilities.acceptsHumanInput,
      isCpuRunning: mode.capabilities.runsCpuTurns,
      currentSeat: snapshot.currentSeat,
      activeSeats: snapshot.activeSeats.toSet(),
    );
  }
}
