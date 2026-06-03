import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_strategy.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_game_controller.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_match_snapshot.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/classic_hareeg_setup.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/ui/features/game_table/table_cpu_turn_presenter.dart';

void main() {
  group('ClassicHareegTableCpuTurnPresenter', () {
    test(
      'visible run sequences flight, joker capture, and persistence',
      () async {
        final controller = _controllerForCpuDrawTurn();
        final events = <String>[];

        final result = await ClassicHareegTableCpuTurnPresenter(
          controller: controller,
          strategy: const _FirstLegalCpuStrategy(),
          actionLimit: 1,
          hooks: _hooks(
            events: events,
            persistAndMaybeFinish: () async {
              events.add('persist');
              return true;
            },
          ),
        ).runVisible();

        expect(result.didApplyAction, isTrue);
        expect(
          events,
          containsAllInOrder([
            'flight:${PlayerSeat.east.name}:${ClassicHareegActionIds.drawStock}',
            'capture:${ClassicHareegActionIds.drawStock}',
            'emit-jokers',
            'drop:${PlayerSeat.east.name}',
            'ensure-fifty',
            'persist',
          ]),
        );
      },
    );

    test('visible run stops when persistence declines continuation', () async {
      final controller = _controllerForCpuDrawTurn();
      final events = <String>[];

      final result = await ClassicHareegTableCpuTurnPresenter(
        controller: controller,
        strategy: const _FirstLegalCpuStrategy(),
        actionLimit: 4,
        hooks: _hooks(
          events: events,
          persistAndMaybeFinish: () async {
            events.add('persist');
            return false;
          },
          postActionDwell: (actionId) {
            events.add('dwell:$actionId');
            return Duration.zero;
          },
        ),
      ).runVisible();

      expect(result.didApplyAction, isTrue);
      expect(result.appliedActionCount, 1);
      expect(events.where((event) => event == 'persist'), hasLength(1));
      expect(events, isNot(contains(startsWith('dwell:'))));
    });

    test('fast forward stops when the runner makes no progress', () async {
      final controller = _controllerForHumanTurn();
      final events = <String>[];

      final didApply = await ClassicHareegTableCpuTurnPresenter(
        controller: controller,
        strategy: const _FirstLegalCpuStrategy(),
        hooks: _hooks(events: events),
      ).fastForwardUntilRoundOver(actionLimit: 4);

      expect(didApply, isFalse);
      expect(controller.isRoundOver, isFalse);
      expect(events, isEmpty);
    });
  });
}

ClassicHareegTableCpuTurnPresenterHooks _hooks({
  required List<String> events,
  Future<bool> Function()? persistAndMaybeFinish,
  Duration Function(String actionId)? postActionDwell,
}) {
  return ClassicHareegTableCpuTurnPresenterHooks(
    isMounted: () => true,
    hasRoundResultPresentation: () => false,
    log: (_) {},
    playFlightForCpuAction: (seat, actionId) async {
      events.add('flight:${seat.name}:$actionId');
    },
    capturePlacedJokersForAction: (actionId) {
      events.add('capture:$actionId');
    },
    emitJokerFeedback: () {
      events.add('emit-jokers');
    },
    clearPlacedJokerSnapshot: () {
      events.add('clear-jokers');
    },
    dropPendingSettledFor: (seat) {
      events.add('drop:${seat.name}');
    },
    ensureFiftyTicker: () {
      events.add('ensure-fifty');
    },
    persistAndMaybeFinish: persistAndMaybeFinish ?? () async => true,
    postActionDwell: postActionDwell ?? (_) => Duration.zero,
  );
}

ClassicHareegGameController _controllerForCpuDrawTurn() {
  final round = ClassicHareegRound.deal(
    setup: ClassicHareegSetup.defaults(),
    seed: 1,
  );
  return ClassicHareegGameController.fromSnapshot(
    ClassicHareegMatchSnapshot(
      setup: round.setup,
      hands: round.hands,
      stock: round.stock,
      discardPile: round.discardPile,
      starter: round.starter,
      currentSeat: PlayerSeat.east,
      turnPhase: TurnPhase.draw,
      savedAt: DateTime.utc(2026, 6, 2),
    ),
  );
}

ClassicHareegGameController _controllerForHumanTurn() {
  final round = ClassicHareegRound.deal(
    setup: ClassicHareegSetup.defaults(),
    seed: 2,
  );
  return ClassicHareegGameController.fromSnapshot(
    ClassicHareegMatchSnapshot(
      setup: round.setup,
      hands: round.hands,
      stock: round.stock,
      discardPile: round.discardPile,
      starter: round.starter,
      currentSeat: PlayerSeat.south,
      turnPhase: TurnPhase.draw,
      savedAt: DateTime.utc(2026, 6, 2),
    ),
  );
}

class _FirstLegalCpuStrategy implements CpuStrategy {
  const _FirstLegalCpuStrategy();

  @override
  CpuMoveIntent chooseMove(
    CpuTurnSnapshot snapshot, {
    CpuObservation? observation,
  }) {
    return CpuMoveIntent(actionId: snapshot.legalActionIds.first);
  }
}
