part of 'classic_hareeg_game_controller.dart';

/// Applies one decoded Classic Hareeg action through the controller.
///
/// The controller owns live mutable state. This module owns the route from
/// action id to validation strategy, keeping the public controller interface
/// small while concentrating action-application ordering in one implementation.
final class _ClassicHareegActionApplication {
  const _ClassicHareegActionApplication(this._controller);

  final ClassicHareegGameController _controller;

  ApplyActionResult apply(String actionId) {
    final result = _applyRouted(actionId);
    if (result.isSuccess && !result.wasReverted) {
      // Keep the active Fifty proof script (if any) in step with what was
      // just played, so the CPU surface serves the next proof action.
      _controller._onActionApplied(actionId);
    }
    return result;
  }

  ApplyActionResult _applyRouted(String actionId) {
    if (_controller._roundOutcome != null) {
      return const ApplyActionResult.failure('Round has ended.');
    }

    final action = ClassicHareegActionIds.describe(actionId);
    final route = ClassicHareegActionSurfacePlanner.applyRouteFor(action.kind);
    if (route == ClassicHareegActionApplyRoute.directValidation) {
      final result = _applyDirect(action);
      if (result != null) {
        return result;
      }
    }

    if (!_controller
        ._actionSurfacePlanFor(
          _controller._currentSeat,
          ClassicHareegActionSurfacePurpose.control,
        )
        .allows(actionId)) {
      return ApplyActionResult.failure(
        'Action "$actionId" is not legal right now.',
      );
    }

    if (route == ClassicHareegActionApplyRoute.controlSurface) {
      final result = _applyControl(action);
      if (result != null) {
        return result;
      }
    }

    return ApplyActionResult.failure('Unknown action "$actionId".');
  }

  ApplyActionResult? _applyDirect(ClassicHareegActionDescriptor action) {
    switch (action.kind) {
      case ClassicHareegActionKind.playMeldWithJoker:
        final jokerChoice = action.jokerMeldChoice!;
        return _controller._applyPlayMeld(
          jokerChoice.cardIds,
          jokerIdentities: {
            for (final assignment in jokerChoice.assignments)
              assignment.jokerId: assignment.identity,
          },
        );
      case ClassicHareegActionKind.playMeld:
        return _controller._applyPlayMeld(action.cardIds);
      case ClassicHareegActionKind.replaceJoker:
        return _controller._applyReplaceJoker(action.jokerReplacementTarget!);
      case ClassicHareegActionKind.placeCover:
        return _controller._applyPlaceCover(action.coverTarget!);
      case ClassicHareegActionKind.returnTablePlay:
        return _controller._applyReturnTablePlay(action.returnTablePlayTarget!);
      case ClassicHareegActionKind.drawStock:
      case ClassicHareegActionKind.takeDiscard:
      case ClassicHareegActionKind.usePendingDiscard:
      case ClassicHareegActionKind.returnPendingDiscard:
      case ClassicHareegActionKind.returnOpeningMelds:
      case ClassicHareegActionKind.claimFifty:
      case ClassicHareegActionKind.discard:
      case ClassicHareegActionKind.discardBlockedCover:
      case ClassicHareegActionKind.discardJoker:
      case ClassicHareegActionKind.unknown:
        return null;
    }
  }

  ApplyActionResult? _applyControl(ClassicHareegActionDescriptor action) {
    switch (action.kind) {
      case ClassicHareegActionKind.drawStock:
        return _controller._applyDrawStock();
      case ClassicHareegActionKind.takeDiscard:
        return _controller._applyTakePreviousDiscard();
      case ClassicHareegActionKind.usePendingDiscard:
        return _controller._applyUsePendingDiscard();
      case ClassicHareegActionKind.returnPendingDiscard:
        return _controller._applyReturnPendingDiscard();
      case ClassicHareegActionKind.returnOpeningMelds:
        return _controller._applyReturnOpeningMelds();
      case ClassicHareegActionKind.claimFifty:
        return _controller._applyClaimFifty();
      case ClassicHareegActionKind.discard:
      case ClassicHareegActionKind.discardBlockedCover:
      case ClassicHareegActionKind.discardJoker:
        return _controller._applyDiscard(action.cardId!);
      case ClassicHareegActionKind.playMeld:
      case ClassicHareegActionKind.playMeldWithJoker:
      case ClassicHareegActionKind.placeCover:
      case ClassicHareegActionKind.replaceJoker:
      case ClassicHareegActionKind.returnTablePlay:
      case ClassicHareegActionKind.unknown:
        return null;
    }
  }
}
