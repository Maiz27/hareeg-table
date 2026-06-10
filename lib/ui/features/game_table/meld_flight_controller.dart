import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../domain/classic_hareeg/game/classic_hareeg_action.dart';
import '../../../domain/classic_hareeg/game/classic_hareeg_table_play_planner.dart';
import '../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../domain/classic_hareeg/rules/opening_rules.dart' show PlacedMeld;
import 'table_card_flight_planner.dart';
import 'table_flight_anchors.dart';
import 'widgets/meld_flight_overlay.dart';

/// Lookup of a visible card in a seat's hand by id.
typedef MeldFlightHandLookup =
    HareegCard? Function(PlayerSeat seat, String cardId);

/// Lookup of the card counts of the melds already committed for a seat, in
/// placement order. Used to allocate landing-slot indices for the sets in
/// flight and to reproduce the lane's arrangement so each set flies to its
/// own resting slot rather than the lane centre.
typedef MeldFlightLaneCardCountsLookup = List<int> Function(PlayerSeat seat);

/// Sound callback fired once at the start of a meld play. The orchestrator
/// stays UI-agnostic about the audio layer.
typedef MeldFlightSoundCallback = void Function();

/// Owns the meld-animation lifecycle so the table screen doesn't have to.
///
/// Decomposes a `playMeld` action into one [MeldFlight] per [PlacedMeld]
/// using [ClassicHareegTablePlayPlanner.resolveTablePlay] — the same planner
/// the controller runs — so the per-set animation matches the controller's
/// commit. Each set flies sequentially with an inter-set beat between sets.
/// As each flight ends, the per-set [PlacedMeld] is published to
/// [pendingSettledMelds] so the table shows the landed meld during the
/// inter-set delay before the controller's atomic `applyAction` commits the
/// real melds. The screen calls [dropPendingSettledFor] once the controller
/// has taken over so the ghost layer doesn't double-render.
class MeldFlightController extends ChangeNotifier {
  /// Creates a meld flight controller.
  MeldFlightController({
    required MeldFlightHandLookup handLookup,
    required MeldFlightLaneCardCountsLookup existingMeldCardCounts,
    required bool Function() isMounted,
  }) : _handLookup = handLookup,
       _existingMeldCardCounts = existingMeldCardCounts,
       _isMounted = isMounted;

  final MeldFlightHandLookup _handLookup;
  final MeldFlightLaneCardCountsLookup _existingMeldCardCounts;
  final bool Function() _isMounted;

  final List<MeldFlight> _activeFlights = [];
  final Map<PlayerSeat, List<PlacedMeld>> _pendingSettledMelds = {};
  int _serial = 0;

  /// Flights currently animating, in z-order.
  List<MeldFlight> get activeFlights => List.unmodifiable(_activeFlights);

  /// UI-only "settled" melds for [seat]. Each per-set [PlacedMeld] lands here
  /// the moment its flight ends so the table shows the landed meld during
  /// the inter-set delay; cleared by the screen once `applyAction` commits.
  /// Returns `null` when no ghosts exist for the seat — lets the screen skip
  /// allocating a merged list in the common empty case.
  List<PlacedMeld>? pendingFor(PlayerSeat seat) => _pendingSettledMelds[seat];

  /// True if any seat currently has a settled-ghost meld.
  bool get hasPendingSettled => _pendingSettledMelds.isNotEmpty;

  /// Animates each meld in a `play-meld` action as its own face-up fan
  /// flying from [seat]'s hand to that meld's landing slot. A single action
  /// can produce multiple melds (e.g. a 7-card opening that drops two sets
  /// at once); they fly sequentially with [interSetDelay] between them.
  ///
  /// Returns `true` if at least one fan was animated.
  Future<bool> playMeld({
    required PlayerSeat seat,
    required String actionId,
    required Duration flightDuration,
    required Duration interSetDelay,
    MeldFlightSoundCallback? onSoundPlay,
  }) async {
    final descriptor = ClassicHareegActionIds.describe(actionId);
    final cardIds = descriptor.cardIds;
    if (cardIds.isEmpty) return false;
    final cards = <HareegCard>[];
    for (final id in cardIds) {
      final card = _handLookup(seat, id);
      if (card == null) continue;
      cards.add(card);
    }
    if (cards.isEmpty) return false;
    // Mirror the controller's split: feed the same cards (and joker
    // assignments, if any) into the planner so the UI's per-set animation
    // matches the per-meld decomposition the controller will commit.
    final jokerIdentities = <String, CardIdentity>{
      for (final assignment in descriptor.jokerMeldChoice?.assignments ??
          const <JokerMeldAssignment>[])
        assignment.jokerId: assignment.identity,
    };
    final resolved = ClassicHareegTablePlayPlanner.resolveTablePlay(
      cards,
      jokerIdentities: jokerIdentities.isEmpty ? null : jokerIdentities,
    );
    final placedMelds = resolved.result.isValid && resolved.melds.isNotEmpty
        ? resolved.melds
        : <PlacedMeld>[PlacedMeld.fromCards(cards)];
    final existingCounts = _existingMeldCardCounts(seat);
    final baseMeldIndex = existingCounts.length;
    onSoundPlay?.call();
    for (var i = 0; i < placedMelds.length; i += 1) {
      if (!_isMounted()) return false;
      final meld = placedMelds[i];
      _serial += 1;
      // Lane card counts as they will be once this set lands: the melds
      // already on the table plus every set flown so far (including this
      // one). Lets the flight geometry place the fan on this set's resting
      // slot instead of the lane centre.
      final laneCardCounts = [
        ...existingCounts,
        for (var j = 0; j <= i; j += 1) placedMelds[j].cards.length,
      ];
      final flight = MeldFlight(
        serial: _serial,
        seat: seat,
        cards: List.unmodifiable(meld.cards),
        // Begin at the seat's hand strip (back-of-cards row for opponents,
        // bottom hand strip for south) so each set visibly leaves the hand.
        begin: TableFlightAnchors.seatHandStrip(seat),
        end: TableFlightAnchors.seatLane(seat),
        endMeldSlot: TableMeldFlightSlot(
          seat: seat,
          index: baseMeldIndex + i,
          laneMeldCardCounts: laneCardCounts,
        ),
        duration: flightDuration,
      );
      _activeFlights.add(flight);
      notifyListeners();
      await Future<void>.delayed(flightDuration);
      if (!_isMounted()) return true;
      // Drop the flight overlay and immediately publish a UI-only "settled"
      // copy of this meld so the table shows it during the inter-set beat.
      // The controller's atomic applyAction (at the end of the action flow)
      // will later replace these ghosts with the real melds.
      _activeFlights.remove(flight);
      _pendingSettledMelds.putIfAbsent(seat, () => []).add(meld);
      notifyListeners();
      final isLast = i == placedMelds.length - 1;
      if (!isLast && interSetDelay > Duration.zero) {
        await Future<void>.delayed(interSetDelay);
      }
    }
    return true;
  }

  /// Drops the UI-only ghost melds for [seat]. Called after the controller's
  /// `applyAction` commits the real melds so the table doesn't double-render.
  /// Returns `true` if any ghosts were dropped.
  bool dropPendingSettledFor(PlayerSeat seat) {
    final removed = _pendingSettledMelds.remove(seat);
    if (removed == null) return false;
    notifyListeners();
    return true;
  }

  /// Resets all flight + ghost state. Used when the CPU loop ends, when an
  /// error path bails, or when a new round is loaded.
  void clear() {
    final hadAny =
        _activeFlights.isNotEmpty || _pendingSettledMelds.isNotEmpty;
    _activeFlights.clear();
    _pendingSettledMelds.clear();
    if (hadAny) {
      notifyListeners();
    }
  }
}
