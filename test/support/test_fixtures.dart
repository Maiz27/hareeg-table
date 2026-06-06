import 'package:hareeg_table/data/persistence/key_value_store.dart';
import 'package:hareeg_table/data/persistence/learning_progress_repository.dart';
import 'package:hareeg_table/data/persistence/match_repository.dart';
import 'package:hareeg_table/data/persistence/preferences_repository.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/domain/classic_hareeg/rules/opening_rules.dart';

/// In-memory [KeyValueStore] shared by the persistence repository tests.
class MemoryKeyValueStore implements KeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> loadString(String key) async => values[key];

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  Future<void> saveString(String key, String value) async {
    values[key] = value;
  }
}

/// In-memory preferences repository used by widget + integration tests.
class MemoryPreferencesRepository implements PreferencesRepository {
  GamePreferences preferences = GamePreferences.defaults();

  @override
  Future<GamePreferences> loadPreferences() async => preferences;

  @override
  Future<void> savePreferences(GamePreferences preferences) async {
    this.preferences = preferences;
  }
}

/// In-memory learning progress repository.
class MemoryLearningProgressRepository implements LearningProgressRepository {
  MemoryLearningProgressRepository({LearningProgress? progress})
    : progress = progress ?? LearningProgress.defaults();

  LearningProgress progress;

  @override
  Future<LearningProgress> loadProgress() async => progress;

  @override
  Future<void> saveProgress(LearningProgress progress) async {
    this.progress = progress;
  }
}

/// In-memory match repository.
class MemoryMatchRepository implements MatchRepository {
  MemoryMatchRepository({this.saved});

  ClassicHareegMatchSnapshot? saved;

  @override
  Future<void> abandonActiveMatch() async {
    saved = null;
  }

  @override
  Future<ClassicHareegMatchSnapshot?> loadActiveMatch() async => saved;

  @override
  Future<void> saveActiveMatch(ClassicHareegMatchSnapshot snapshot) async {
    saved = snapshot;
  }
}

/// Builds a reproducible snapshot for the south seat to drive through the UI.
ClassicHareegMatchSnapshot snapshotWithSouthHand(
  List<HareegCard> southHand, {
  ClassicHareegSetup? setup,
  PlayerSeat currentSeat = PlayerSeat.south,
  TurnPhase turnPhase = TurnPhase.action,
  OpeningState? openingState,
}) {
  final resolvedSetup = setup ?? ClassicHareegSetup.defaults();
  final base = ClassicHareegRound.deal(setup: resolvedSetup, seed: 7);
  return ClassicHareegMatchSnapshot(
    setup: resolvedSetup,
    hands: {
      ...base.hands,
      PlayerSeat.south: [...southHand, ...base.hands[PlayerSeat.south]!],
    },
    stock: base.stock,
    discardPile: base.discardPile,
    starter: base.starter,
    currentSeat: currentSeat,
    turnPhase: turnPhase,
    openingState: openingState,
    savedAt: DateTime.utc(2026, 5, 18),
  );
}

/// Builds an opened state for the named seat (used by tests that need the
/// player to already be opened).
OpeningState openedState(PlayerSeat seat) {
  final setup = ClassicHareegSetup.defaults();
  return ClassicHareegOpeningRules.applyOpening(
    state: OpeningState.initial(setup.openingRequirement),
    seat: seat,
    melds: [
      PlacedMeld(cards: const [], valueSnapshot: setup.openingRequirement),
    ],
  );
}
