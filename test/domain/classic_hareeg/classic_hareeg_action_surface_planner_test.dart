import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action_surface_planner.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_draw_decision_planner.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_fifty_claim_planner.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';

const _seat = PlayerSeat.south;

void main() {
  group('ClassicHareegActionSurfacePlanner', () {
    test('inactive seats expose no actions and do not call facts', () {
      final facts = _facts();

      final plan = ClassicHareegActionSurfacePlanner.evaluate(
        purpose: ClassicHareegActionSurfacePurpose.full,
        seat: _seat,
        isRoundOver: false,
        isSeatTurn: false,
        isSeatActive: true,
        phase: TurnPhase.action,
        pendingDiscardId: null,
        facts: facts,
      );

      expect(plan.scenario, ClassicHareegActionSurfaceScenario.inactive);
      expect(plan.actionIds, isEmpty);
      expect(facts.calls, isEmpty);
    });

    test(
      'pending full surface exposes unrestricted table plays plus return',
      () {
        final facts = _facts(
          playMeldActionIds: ['play-any'],
          replaceJokerActionIds: ['replace-any'],
          coverActionIds: ['cover-any'],
        );

        final plan = _evaluate(
          ClassicHareegActionSurfacePurpose.full,
          pendingDiscardId: 'pending-card',
          facts: facts,
        );

        expect(
          plan.scenario,
          ClassicHareegActionSurfaceScenario.pendingDiscard,
        );
        expect(plan.reason, 'pending-full');
        expect(plan.actionIds, [
          'play-any',
          'replace-any',
          'cover-any',
          ClassicHareegActionIds.returnPendingDiscard,
        ]);
        // Relaxed taken-discard rule: searches are NOT constrained to the
        // pending card; any table play stays legal while it sits unused.
        expect(facts.calls, [
          'can-return-pending',
          'can-return',
          'play:-',
          'replace:-',
          'cover:-',
          'discard',
        ]);
      },
    );

    test('pending full surface omits return when it is not allowed', () {
      final facts = _facts(
        canReturnPendingDiscard: false,
        playMeldActionIds: ['play-any'],
      );

      final plan = _evaluate(
        ClassicHareegActionSurfacePurpose.full,
        pendingDiscardId: 'pending-card',
        facts: facts,
      );

      expect(plan.actionIds, ['play-any']);
    });

    test('pending control surface stays cheap', () {
      final facts = _facts(
        playMeldActionIds: ['play-any'],
        replaceJokerActionIds: ['replace-any'],
        coverActionIds: ['cover-any'],
      );

      final plan = _evaluate(
        ClassicHareegActionSurfacePurpose.control,
        pendingDiscardId: 'pending-card',
        facts: facts,
      );

      expect(plan.actionIds, [ClassicHareegActionIds.returnPendingDiscard]);
      expect(facts.calls, ['can-return-pending', 'can-return', 'discard']);
    });

    test('pending CPU surface stops at first usable pending action', () {
      final facts = _facts(
        firstPlayMeldActionId: 'play-pending',
        replaceJokerActionIds: ['replace-pending'],
        coverActionIds: ['cover-pending'],
      );

      final plan = _evaluate(
        ClassicHareegActionSurfacePurpose.cpu,
        pendingDiscardId: 'pending-card',
        facts: facts,
      );

      expect(plan.actionIds, ['play-pending']);
      expect(plan.reason, 'pending-meld');
      expect(facts.calls, ['can-return-pending', 'first-play:pending-card']);
    });

    test(
      'pending CPU surface falls back through replacement, cover, return',
      () {
        final replacementFacts = _facts(
          replaceJokerActionIds: ['replace-pending'],
          coverActionIds: ['cover-pending'],
        );
        final coverFacts = _facts(coverActionIds: ['cover-pending']);
        final returnFacts = _facts();

        final replacement = _evaluate(
          ClassicHareegActionSurfacePurpose.cpu,
          pendingDiscardId: 'pending-card',
          facts: replacementFacts,
        );
        final cover = _evaluate(
          ClassicHareegActionSurfacePurpose.cpu,
          pendingDiscardId: 'pending-card',
          facts: coverFacts,
        );
        final returned = _evaluate(
          ClassicHareegActionSurfacePurpose.cpu,
          pendingDiscardId: 'pending-card',
          facts: returnFacts,
        );

        expect(replacement.actionIds, ['replace-pending']);
        expect(replacement.reason, 'pending-replace');
        expect(cover.actionIds, ['cover-pending']);
        expect(cover.reason, 'pending-cover');
        expect(returned.actionIds, [
          ClassicHareegActionIds.returnPendingDiscard,
        ]);
        expect(returned.reason, 'pending-return');
      },
    );

    test(
      'action full surface includes table play, return, and discard actions',
      () {
        final facts = _facts(
          canReturnOpeningMelds: true,
          playMeldActionIds: ['play'],
          replaceJokerActionIds: ['replace'],
          coverActionIds: ['cover'],
          discardActionIds: ['discard'],
        );

        final plan = _evaluate(
          ClassicHareegActionSurfacePurpose.full,
          facts: facts,
        );

        expect(plan.scenario, ClassicHareegActionSurfaceScenario.actionTurn);
        expect(plan.actionIds, [
          ClassicHareegActionIds.returnOpeningMelds,
          'play',
          'replace',
          'cover',
          'discard',
        ]);
      },
    );

    test('action control surface excludes expensive table play searches', () {
      final facts = _facts(
        canReturnOpeningMelds: true,
        playMeldActionIds: ['play'],
        replaceJokerActionIds: ['replace'],
        coverActionIds: ['cover'],
        discardActionIds: ['discard'],
      );

      final plan = _evaluate(
        ClassicHareegActionSurfacePurpose.control,
        facts: facts,
      );

      expect(plan.actionIds, [
        ClassicHareegActionIds.returnOpeningMelds,
        'discard',
      ]);
      expect(facts.calls, ['can-return', 'discard']);
    });

    test('action CPU surface exposes one high-value action per category', () {
      final facts = _facts(
        firstPlayMeldActionId: 'play-first',
        replaceJokerActionIds: ['replace-a', 'replace-b'],
        coverActionIds: ['cover-a', 'cover-b'],
        discardActionIds: ['discard-a', 'discard-b'],
      );

      final plan = _evaluate(
        ClassicHareegActionSurfacePurpose.cpu,
        facts: facts,
      );

      expect(plan.actionIds, [
        'play-first',
        'replace-a',
        'cover-a',
        'discard-a',
        'discard-b',
      ]);
      expect(plan.reason, 'action');
    });

    test('draw phase delegates to the draw decision plan', () {
      final drawPlan = _drawPlan(['claim-fifty', 'draw-stock']);
      final facts = _facts(drawDecisionPlan: drawPlan);

      final plan = _evaluate(
        ClassicHareegActionSurfacePurpose.control,
        phase: TurnPhase.draw,
        facts: facts,
      );

      expect(plan.scenario, ClassicHareegActionSurfaceScenario.drawDecision);
      expect(plan.actionIds, ['claim-fifty', 'draw-stock']);
      expect(plan.drawDecisionPlan, same(drawPlan));
      expect(facts.calls, ['draw']);
    });

    test(
      'apply routes keep direct table validation distinct from controls',
      () {
        expect(
          ClassicHareegActionSurfacePlanner.applyRouteFor(
            ClassicHareegActionKind.playMeld,
          ),
          ClassicHareegActionApplyRoute.directValidation,
        );
        expect(
          ClassicHareegActionSurfacePlanner.applyRouteFor(
            ClassicHareegActionKind.discard,
          ),
          ClassicHareegActionApplyRoute.controlSurface,
        );
        expect(
          ClassicHareegActionSurfacePlanner.applyRouteFor(
            ClassicHareegActionKind.unknown,
          ),
          ClassicHareegActionApplyRoute.unknown,
        );
      },
    );
  });
}

ClassicHareegActionSurfacePlan _evaluate(
  ClassicHareegActionSurfacePurpose purpose, {
  TurnPhase phase = TurnPhase.action,
  String? pendingDiscardId,
  required _RecordingFacts facts,
}) {
  return ClassicHareegActionSurfacePlanner.evaluate(
    purpose: purpose,
    seat: _seat,
    isRoundOver: false,
    isSeatTurn: true,
    isSeatActive: true,
    phase: phase,
    pendingDiscardId: pendingDiscardId,
    facts: facts,
  );
}

_RecordingFacts _facts({
  bool canReturnOpeningMelds = false,
  bool canReturnPendingDiscard = true,
  List<String> playMeldActionIds = const [],
  String? firstPlayMeldActionId,
  List<String> replaceJokerActionIds = const [],
  List<String> coverActionIds = const [],
  List<String> discardActionIds = const [],
  ClassicHareegDrawDecisionPlan? drawDecisionPlan,
}) {
  return _RecordingFacts(
    canReturnOpeningMeldsResult: canReturnOpeningMelds,
    canReturnPendingDiscardResult: canReturnPendingDiscard,
    playMeldActionIdsResult: playMeldActionIds,
    firstPlayMeldActionIdResult: firstPlayMeldActionId,
    replaceJokerActionIdsResult: replaceJokerActionIds,
    coverActionIdsResult: coverActionIds,
    discardActionIdsResult: discardActionIds,
    drawDecisionPlanResult: drawDecisionPlan ?? _drawPlan(),
  );
}

ClassicHareegDrawDecisionPlan _drawPlan([List<String> actionIds = const []]) {
  return ClassicHareegDrawDecisionPlan(
    scenario: ClassicHareegDrawDecisionScenario.stockDrawOnly,
    actionIds: actionIds,
    fiftyClaimPlan: const ClassicHareegFiftyClaimPlan(
      scenario: ClassicHareegFiftyClaimScenario.noWindow,
      shouldAdvertise: false,
      canApply: false,
      message: 'No Fifty.',
    ),
    stockIsEmpty: false,
    canTakePreviousDiscard: false,
    pickupWouldFinish: false,
    shouldEndRoundAsDraw: false,
    canDrawStock: false,
    canTakeDiscard: false,
  );
}

class _RecordingFacts implements ClassicHareegActionSurfaceFacts {
  _RecordingFacts({
    required this.canReturnOpeningMeldsResult,
    required this.canReturnPendingDiscardResult,
    required this.playMeldActionIdsResult,
    required this.firstPlayMeldActionIdResult,
    required this.replaceJokerActionIdsResult,
    required this.coverActionIdsResult,
    required this.discardActionIdsResult,
    required this.drawDecisionPlanResult,
  });

  final bool canReturnOpeningMeldsResult;
  final bool canReturnPendingDiscardResult;
  final List<String> playMeldActionIdsResult;
  final String? firstPlayMeldActionIdResult;
  final List<String> replaceJokerActionIdsResult;
  final List<String> coverActionIdsResult;
  final List<String> discardActionIdsResult;
  final ClassicHareegDrawDecisionPlan drawDecisionPlanResult;
  final List<String> calls = [];

  @override
  List<String> playMeldActionIds(PlayerSeat seat, {String? mustUseCardId}) {
    calls.add('play:${mustUseCardId ?? '-'}');
    return playMeldActionIdsResult;
  }

  @override
  String? firstPlayMeldActionId(PlayerSeat seat, {String? mustUseCardId}) {
    calls.add('first-play:${mustUseCardId ?? '-'}');
    return firstPlayMeldActionIdResult;
  }

  @override
  List<String> replaceJokerActionIds(PlayerSeat seat, {String? mustUseCardId}) {
    calls.add('replace:${mustUseCardId ?? '-'}');
    return replaceJokerActionIdsResult;
  }

  @override
  List<String> coverActionIds(PlayerSeat seat, {String? mustUseCardId}) {
    calls.add('cover:${mustUseCardId ?? '-'}');
    return coverActionIdsResult;
  }

  @override
  List<String> discardActionIds(PlayerSeat seat) {
    calls.add('discard');
    return discardActionIdsResult;
  }

  @override
  bool canReturnOpeningMelds(PlayerSeat seat) {
    calls.add('can-return');
    return canReturnOpeningMeldsResult;
  }

  @override
  bool canReturnPendingDiscard(PlayerSeat seat) {
    calls.add('can-return-pending');
    return canReturnPendingDiscardResult;
  }

  @override
  ClassicHareegDrawDecisionPlan drawDecisionPlan(PlayerSeat seat) {
    calls.add('draw');
    return drawDecisionPlanResult;
  }
}
