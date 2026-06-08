import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/ui/features/learning/practice/practice_board_grammar.dart';
import 'package:hareeg_table/ui/features/learning/practice/practice_session.dart';

/// Standard non-joker physical card shorthand for practice tests.
HareegCard practiceCard(CardRank rank, CardSuit suit, {int deckIndex = 0}) {
  return HareegCard.standard(rank: rank, suit: suit, deckIndex: deckIndex);
}

/// Physical joker shorthand for practice tests.
HareegCard practiceJoker({int deckIndex = 0, int jokerIndex = 0}) {
  return HareegCard.joker(deckIndex: deckIndex, jokerIndex: jokerIndex);
}

/// Discard action id for [card].
String practiceDiscardId(HareegCard card) {
  return '${ClassicHareegActionIds.discardPrefix}${card.id}';
}

/// Play-meld action id for [cards].
String practiceMeldId(List<HareegCard> cards) {
  return ClassicHareegActionIds.playMeldActionId(cards.map((card) => card.id));
}

/// Table value for [seat] in [session].
int practiceTableValueFor(PracticeSession session, PlayerSeat seat) {
  return PracticeBoardGrammar.tableValueForController(session.controller, seat);
}

/// Table card count for [seat] in [session].
int practiceTableCardCountFor(PracticeSession session, PlayerSeat seat) {
  return PracticeBoardGrammar.tableCardCountForController(
    session.controller,
    seat,
  );
}

/// Expects a practice board audit to pass, showing all failures at once.
void expectPracticeBoardAudit(
  PracticeBoardAuditResult audit, {
  String? reason,
}) {
  expect(
    audit.failures,
    isEmpty,
    reason: [?reason, ...audit.failures].join('\n'),
  );
}

/// Audits [snapshot] with [PracticeBoardGrammar] and expects it to pass.
void expectPracticeBoardSnapshotAudit(
  ClassicHareegMatchSnapshot snapshot, {
  Set<PlayerSeat> handAndTableSeats = const {},
  Map<PlayerSeat, int> extraCardsInHand = const {},
  Map<PlayerSeat, int> expectedTableValues = const {},
  Set<PlayerSeat> fullHandSeats = const {},
  int? minimumDiscardPileSize,
  String? reason,
}) {
  expectPracticeBoardAudit(
    PracticeBoardGrammar.auditSnapshot(
      snapshot,
      PracticeBoardAuditSpec(
        handAndTableSeats: handAndTableSeats,
        extraCardsInHand: extraCardsInHand,
        expectedTableValues: expectedTableValues,
        fullHandSeats: fullHandSeats,
        minimumDiscardPileSize: minimumDiscardPileSize,
      ),
    ),
    reason: reason,
  );
}

/// Applies the lesson's scripted intro through the real controller.
///
/// Mirrors the table's scripted CPU presenter at the rules seam: every intro
/// action must be legal, and the final action must hand the turn to south.
void runPracticeIntro(PracticeSession session) {
  for (final actionId in session.script.introActionIds) {
    final result = session.controller.applyAction(actionId);
    expect(
      result.isSuccess,
      isTrue,
      reason: 'intro action $actionId must be legal: ${result.message}',
    );
  }
  expect(
    session.controller.currentSeat,
    PlayerSeat.south,
    reason: 'the intro must hand the turn to the player',
  );
}

/// Shared controllable clock for walking Fifty windows deterministically.
class PracticeTestClock {
  /// Current instant returned by [now].
  DateTime current = DateTime.utc(2026, 1, 1, 12);

  /// Current fake time.
  DateTime now() => current;

  /// Advances fake time.
  void advance(Duration delta) => current = current.add(delta);
}
