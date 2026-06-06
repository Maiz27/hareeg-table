import '../../../../domain/classic_hareeg/game/classic_hareeg_action.dart';
import '../../../../domain/classic_hareeg/game/classic_hareeg_table_play_planner.dart';
import '../../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../../domain/classic_hareeg/rules/cover_rules.dart';
import '../../game_table/table_interaction_planner.dart';
import 'practice_session.dart';

/// Filters the table's interaction surface down to the active practice step.
///
/// The live table computes its affordances (what lights up, what accepts a
/// drop, which meld suggestions appear) straight from the controller. In a
/// lesson the step narrows the legal surface to the move being taught, so
/// this wrapper hides every action id the step does not allow — off-script
/// moves never become tappable instead of failing on tap. Legality itself
/// still comes from the engine: the wrapper can only *remove* offers, never
/// add them.
class PracticeTableInteractionReader implements TableInteractionActionReader {
  /// Creates a step-gated view over [inner].
  const PracticeTableInteractionReader({
    required this.inner,
    required this.session,
  });

  /// Real controller-backed reader.
  final TableInteractionActionReader inner;

  /// Active lesson session supplying the step's allowed action ids.
  final PracticeSession session;

  // Membership checks go through [PracticeSession.offersActionId] — the same
  // step filter submit applies — never raw id equality against the enumerated
  // legal-id set: the inner reader's offers are already engine-legal, and the
  // enumeration both orders meld card ids differently than a selection and
  // deliberately skips legal-but-unadvertised plays (staged opening melds).
  String? _allowedOrNull(String? actionId) {
    if (actionId == null) {
      return null;
    }
    return session.offersActionId(actionId) ? actionId : null;
  }

  @override
  PlayerSeat get currentSeat => inner.currentSeat;

  @override
  HareegCard? get pendingDiscard => inner.pendingDiscard;

  @override
  List<String> controlActionIdsFor(PlayerSeat seat) {
    return [
      for (final id in inner.controlActionIdsFor(seat))
        if (session.offersActionId(id)) id,
    ];
  }

  @override
  String? selectedMeldActionIdFor(PlayerSeat seat, List<String> cardIds) {
    return _allowedOrNull(inner.selectedMeldActionIdFor(seat, cardIds));
  }

  @override
  List<CardIdentity> jokerRepresentationOptionsFor(
    PlayerSeat seat,
    List<String> cardIds,
  ) {
    // Identity options feed the picker copy, not an action offer; the chosen
    // action is still gated through [jokerMeldChoicesFor] and submit.
    return inner.jokerRepresentationOptionsFor(seat, cardIds);
  }

  @override
  List<JokerMeldActionChoice> jokerMeldChoicesFor(
    PlayerSeat seat,
    List<String> cardIds,
  ) {
    return [
      for (final choice in inner.jokerMeldChoicesFor(seat, cardIds))
        if (session.offersActionId(choice.actionId)) choice,
    ];
  }

  @override
  List<ClassicHareegMeldSuggestion> meldSuggestionsForSelection(
    PlayerSeat seat,
    List<String> selectedCardIds, {
    int limit = 5,
  }) {
    return [
      for (final suggestion in inner.meldSuggestionsForSelection(
        seat,
        selectedCardIds,
        limit: limit,
      ))
        if (session.offersActionId(suggestion.actionId)) suggestion,
    ];
  }

  @override
  String? coverActionIdFor(PlayerSeat seat, List<String> cardIds) {
    return _allowedOrNull(inner.coverActionIdFor(seat, cardIds));
  }

  @override
  String? coverActionIdForMeldTarget({
    required PlayerSeat seat,
    required List<String> cardIds,
    required PlayerSeat targetSeat,
    required int meldIndex,
    CoverPlacement? coverPlacement,
  }) {
    return _allowedOrNull(
      inner.coverActionIdForMeldTarget(
        seat: seat,
        cardIds: cardIds,
        targetSeat: targetSeat,
        meldIndex: meldIndex,
        coverPlacement: coverPlacement,
      ),
    );
  }

  @override
  String? jokerReplacementActionIdFor(PlayerSeat seat, List<String> cardIds) {
    return _allowedOrNull(inner.jokerReplacementActionIdFor(seat, cardIds));
  }

  @override
  String? jokerReplacementActionIdForMeldTarget({
    required PlayerSeat seat,
    required List<String> cardIds,
    required PlayerSeat targetSeat,
    required int meldIndex,
  }) {
    return _allowedOrNull(
      inner.jokerReplacementActionIdForMeldTarget(
        seat: seat,
        cardIds: cardIds,
        targetSeat: targetSeat,
        meldIndex: meldIndex,
      ),
    );
  }
}
