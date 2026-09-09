import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/replay/match_replay_timeline.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

import '../scenario/classic_hareeg_scenario.dart';

/// A32's stress fixture: the most crowded table the implementation can render.
///
/// Every seat is at or above the playfield's **visible** card cap — twelve for
/// the north rail, six for each side rail — so every opponent-card union is at
/// its full extent rather than a centred subset. A fixture built by stepping a
/// natural match reaches none of those caps, and a HUD proven against it proves
/// nothing about the crowded table the owner's placement was measured on.
///
/// Shared rather than copied into each test on purpose: three private copies
/// would drift, and the first symptom would be an overlap suite quietly passing
/// against a table with one east card on it.
ClassicHareegMatchSnapshot maximumContentSnapshot() {
  var seq = 0;
  HareegCard next() {
    final i = seq++;
    return ScenarioCards.card(
      CardRank.values[i % CardRank.values.length],
      CardSuit.values[(i ~/ CardRank.values.length) % CardSuit.values.length],
      deckIndex: 1000 + i,
    );
  }

  List<HareegCard> cards(int n) => List.generate(n, (_) => next());

  // Value snapshots are inert here: nothing scores a rendering fixture, and
  // going through the validator would constrain the fixture to legal melds
  // when what it needs is a full lane.
  List<PlacedMeld> melds(int count) => List.generate(
    count,
    (_) => PlacedMeld(cards: List.unmodifiable(cards(4)), valueSnapshot: 30),
  );

  return ClassicHareegScenario.deal(
    seed: 7,
    southHand: cards(14),
    northHand: cards(16),
    eastHand: cards(10),
    westHand: cards(10),
    tableMelds: {
      PlayerSeat.south: melds(5),
      PlayerSeat.north: melds(5),
      PlayerSeat.east: melds(5),
      PlayerSeat.west: melds(5),
    },
    discardPile: cards(30),
    stock: cards(25),
    openingState: ScenarioCards.openedFor(PlayerSeat.south),
    currentSeat: PlayerSeat.south,
  ).controller.toSnapshot(savedAt: replayClockEpoch);
}
