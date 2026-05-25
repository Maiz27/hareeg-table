import '../../../domain/classic_hareeg/models/classic_hareeg_setup.dart';
import '../../../domain/classic_hareeg/models/player_seat.dart';
import 'table_human_action_flow_planner.dart';
import 'table_human_action_start_planner.dart';
import 'table_turn_flow_planner.dart';

export 'table_human_action_flow_planner.dart';
export 'table_human_action_start_planner.dart';
export 'table_turn_flow_planner.dart';

/// Deep table-session flow module for Classic Hareeg.
///
/// The screen still performs rendering, animation, persistence IO, and
/// navigation. This module owns the pure decisions that sequence those steps:
/// input gating, frame/CPU follow-up actions, human action start/apply plans,
/// and Table-tier round fast-forward visibility.
abstract final class ClassicHareegTableSessionFlowPlanner {
  /// Whether human table input may start now.
  static bool canAcceptHumanInput({
    required bool isCpuRunning,
    required bool isOpeningDealRunning,
    required bool isHumanActionPending,
  }) {
    return !isCpuRunning && !isOpeningDealRunning && !isHumanActionPending;
  }

  /// Evaluates the first scheduled action for a post-frame turn-flow pass.
  static ClassicHareegTableTurnFlowPlan afterFrame({
    required bool isMounted,
    required bool hasOpeningDealToPlay,
    required bool isCpuRunning,
    required bool isOpeningDealRunning,
    required bool isRoundOver,
    required bool isHumanTurn,
  }) {
    return ClassicHareegTableTurnFlowPlanner.afterFrame(
      isMounted: isMounted,
      hasOpeningDealToPlay: hasOpeningDealToPlay,
      isCpuRunning: isCpuRunning,
      isOpeningDealRunning: isOpeningDealRunning,
      isRoundOver: isRoundOver,
      isHumanTurn: isHumanTurn,
    );
  }

  /// Evaluates the next action after opening-deal work has finished or skipped.
  static ClassicHareegTableTurnFlowPlan afterOpeningDeal({
    required bool isMounted,
    required bool isCpuRunning,
    required bool isOpeningDealRunning,
    required bool isRoundOver,
    required bool isHumanTurn,
  }) {
    return ClassicHareegTableTurnFlowPlanner.afterOpeningDeal(
      isMounted: isMounted,
      isCpuRunning: isCpuRunning,
      isOpeningDealRunning: isOpeningDealRunning,
      isRoundOver: isRoundOver,
      isHumanTurn: isHumanTurn,
    );
  }

  /// Evaluates the next action after a CPU turn runner pass.
  static ClassicHareegTableTurnFlowPlan afterCpuTurns({
    required bool isMounted,
    required bool didCpuPersistOrNavigate,
  }) {
    return ClassicHareegTableTurnFlowPlanner.afterCpuTurns(
      isMounted: isMounted,
      didCpuPersistOrNavigate: didCpuPersistOrNavigate,
    );
  }

  /// Evaluates whether a human action can start.
  static ClassicHareegHumanActionStartPlan startHumanAction({
    required String actionId,
    required bool playFlight,
    required bool isCpuRunning,
    required bool isOpeningDealRunning,
    required bool isHumanActionPending,
  }) {
    return ClassicHareegHumanActionStartPlanner.start(
      actionId: actionId,
      playFlight: playFlight,
      isCpuRunning: isCpuRunning,
      isOpeningDealRunning: isOpeningDealRunning,
      isHumanActionPending: isHumanActionPending,
    );
  }

  /// Evaluates whether a controller action may apply after pre-apply work.
  static ClassicHareegHumanActionApplyGate afterHumanPreApply({
    required bool isMounted,
    required bool plannedFlight,
    required bool flightPlayed,
  }) {
    return ClassicHareegHumanActionStartPlanner.afterPreApply(
      isMounted: isMounted,
      plannedFlight: plannedFlight,
      flightPlayed: flightPlayed,
    );
  }

  /// Evaluates table-side follow-up after a human action apply attempt.
  static ClassicHareegHumanActionFlowPlan afterHumanApply({
    required String actionId,
    required bool isSuccess,
    required String? message,
    required bool soundPlayedWithFlight,
    bool wasReverted = false,
  }) {
    return ClassicHareegHumanActionFlowPlanner.afterApply(
      actionId: actionId,
      isSuccess: isSuccess,
      message: message,
      soundPlayedWithFlight: soundPlayedWithFlight,
      wasReverted: wasReverted,
    );
  }

  /// Whether the Table-tier "skip to next round" action should be available.
  static bool canFastForwardRound({
    required TableStrictness strictness,
    required Set<PlayerSeat> removedSeats,
    required bool isRoundOver,
  }) {
    if (strictness != TableStrictness.table) {
      return false;
    }
    if (!removedSeats.contains(PlayerSeat.south)) {
      return false;
    }
    return !isRoundOver;
  }
}
