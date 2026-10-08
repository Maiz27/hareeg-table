part of 'classic_hareeg_game_controller.dart';

/// Diagnostic event recording for the [MatchRecorder] seam.
extension _Diagnostics on ClassicHareegGameController {
  /// Emits the notable diagnostic events for one applied action.
  ///
  /// Only meaningful transitions are logged — illegal actions, penalty reverts,
  /// scoring changes, Fifty window/claim transitions, round finishes, and
  /// notable CPU decisions — so the capped log stays focused on the context
  /// around a reported problem rather than every routine draw and discard
  /// (those live in the full transcript instead).
  void _recordDiagnostics({
    required MatchRecorder recorder,
    required String actionId,
    required PlayerSeat seat,
    required TurnPhase phase,
    required int round,
    required ApplyActionResult result,
    required Map<PlayerSeat, int> scoresBefore,
    required bool wasRoundOver,
    required PlayerSeat? claimantBefore,
    required Set<PlayerSeat> removedBefore,
  }) {
    final log = recorder.diagnostics;
    final descriptor = ClassicHareegActionIds.describe(actionId);
    final isCpu = seat != PlayerSeat.south;

    if (!result.isSuccess) {
      log.record(
        category: MatchDiagnosticCategory.rules,
        type: 'invalidAction',
        roundNumber: round,
        seat: seat,
        phase: phase,
        data: {
          'actionId': actionId,
          'kind': descriptor.kind.name,
          'message': result.message,
        },
      );
      return;
    }

    if (result.wasReverted) {
      log.record(
        category: MatchDiagnosticCategory.rules,
        type: 'penaltyReverted',
        roundNumber: round,
        seat: seat,
        phase: phase,
        data: {
          'actionId': actionId,
          'kind': descriptor.kind.name,
          if (result.revertedCardId != null)
            'revertedCardId': result.revertedCardId,
          'message': result.message,
        },
      );
    }

    final scoresAfter = scores;
    if (!_scoresEqual(scoresBefore, scoresAfter)) {
      log.record(
        category: MatchDiagnosticCategory.scoring,
        type: 'scoresChanged',
        roundNumber: round,
        seat: seat,
        phase: phase,
        data: {
          'before': {
            for (final entry in scoresBefore.entries)
              entry.key.name: entry.value,
          },
          'after': {
            for (final entry in scoresAfter.entries)
              entry.key.name: entry.value,
          },
        },
      );
    }

    final newlyRemoved = _removedSeats.difference(removedBefore);
    if (newlyRemoved.isNotEmpty) {
      log.record(
        category: MatchDiagnosticCategory.rules,
        type: 'seatRemoved',
        roundNumber: round,
        seat: seat,
        phase: phase,
        data: {
          'removed': [for (final s in newlyRemoved) s.name],
        },
      );
    }

    final claimantAfter = fiftyClaimant;
    if (claimantBefore != claimantAfter) {
      log.record(
        category: MatchDiagnosticCategory.fifty,
        type: claimantAfter != null ? 'fiftyWindowOpened' : 'fiftyWindowClosed',
        roundNumber: round,
        seat: seat,
        phase: phase,
        data: {if (claimantAfter != null) 'claimant': claimantAfter.name},
      );
    }

    if (descriptor.kind == ClassicHareegActionKind.claimFifty) {
      log.record(
        category: MatchDiagnosticCategory.fifty,
        type: 'fiftyClaimed',
        roundNumber: round,
        seat: seat,
        phase: phase,
      );
    }

    final roundJustEnded = !wasRoundOver && isRoundOver;
    if (roundJustEnded) {
      final outcome = _roundResult;
      log.record(
        category: MatchDiagnosticCategory.finish,
        type: 'roundEnded',
        roundNumber: round,
        seat: seat,
        phase: phase,
        data: {
          if (roundOutcome != null) 'outcome': roundOutcome!.name,
          if (outcome?.winner != null) 'winner': outcome!.winner!.name,
        },
      );
    }

    if (isCpu &&
        (descriptor.kind == ClassicHareegActionKind.claimFifty ||
            roundJustEnded)) {
      log.record(
        category: MatchDiagnosticCategory.ai,
        type: 'cpuDecision',
        roundNumber: round,
        seat: seat,
        phase: phase,
        data: {
          'actionId': actionId,
          'kind': descriptor.kind.name,
          'difficulty': setup.cpuDifficulty.name,
        },
      );
    }
  }

  static bool _scoresEqual(Map<PlayerSeat, int> a, Map<PlayerSeat, int> b) {
    for (final seat in PlayerSeat.values) {
      if ((a[seat] ?? 0) != (b[seat] ?? 0)) {
        return false;
      }
    }
    return true;
  }
}

void _debugRulesLog(String message) {
  assert(() {
    developer.log(message, name: 'hareeg.rules');
    return true;
  }());
}

String _debugActionSummary(Iterable<String> actionIds) {
  final ids = actionIds.toList(growable: false);
  if (ids.isEmpty) {
    return '[]';
  }
  const maxShown = 5;
  final shown = ids.take(maxShown).join(', ');
  if (ids.length <= maxShown) {
    return '[$shown]';
  }
  return '[$shown, +${ids.length - maxShown} more]';
}
