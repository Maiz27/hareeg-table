import '../../../../cpu/classic_hareeg/coaching/coaching_insight.dart';

/// One frame's coach selection: the actionable PRIMARY hint plus an optional
/// once-per-round STAGE note shown alongside it.
class CoachSelection {
  /// Creates a coach selection.
  const CoachSelection({this.primary, this.stageNote});

  /// The actionable guidance for this exact decision (draw / take / open /
  /// meld / cover / discard / win). Never a stage banner — the coach must
  /// always tell the player what to DO next; posture teaching may only ride
  /// along, never replace it (the playtest "stuck on a banner, no idea how to
  /// progress" bug).
  final CoachingInsight? primary;

  /// A stage banner riding under the primary hint, or null. Shown at most
  /// once per round per lesson, for the turn it first appears in.
  final CoachingInsight? stageNote;
}

/// Cross-turn surfacing policy for coaching insights — the anti-spam layer.
///
/// The advisor is pure and re-emits every applicable insight on every call;
/// this flow decides what the table actually shows. The PRIMARY slot always
/// carries the top actionable insight. STAGE banners
/// ([CoachingInsightCategory.isStageBanner]) never occupy the primary slot:
/// they surface as a secondary note, holding for the turn they first appear
/// in. Without the dedup, a banner whose condition holds all round (thin
/// stock, score pressure) would repeat every turn — the fixation failure the
/// overhaul removes.
///
/// "Once per round" is DELIBERATELY per teaching, not per category: the
/// [_stageKey] qualifier re-alerts when the message materially changes — a
/// different opponent close to finishing, a fresh benchmark raise, a new bait
/// card on the pile — while an unchanged condition stays taught (test-pinned
/// in coach_insight_flow_test.dart).
///
/// One instance lives in the table screen's state for the lifetime of a match
/// (replaced on rematch — keys embed the round number, which restarts).
class CoachInsightFlow {
  /// Creates an insight flow with no banner history.
  CoachInsightFlow();

  final Set<String> _seen = {};
  String? _activeKey;
  String? _activeTurnKey;

  /// Picks what to present from priority-sorted [insights]. Call only when
  /// the coach is actually allowed to display — selection marks stage banners
  /// as consumed.
  ///
  /// [turnKey] identifies the current turn (any value that changes when the
  /// turn passes); a stage note keeps its slot while it stays the top
  /// eligible banner within one turn, then is retired for the round.
  CoachSelection select({
    required List<CoachingInsight> insights,
    required int roundNumber,
    required String turnKey,
  }) {
    CoachingInsight? primary;
    for (final insight in insights) {
      if (!insight.category.isStageBanner) {
        primary = insight;
        break;
      }
    }

    CoachingInsight? stageNote;
    for (final insight in insights) {
      if (!insight.category.isStageBanner) {
        continue;
      }
      final key = _stageKey(insight, roundNumber);
      if (key == _activeKey && turnKey == _activeTurnKey) {
        // Still inside the turn this banner first surfaced in: keep it up.
        stageNote = insight;
        break;
      }
      if (_seen.contains(key)) {
        // Already taught this round.
        continue;
      }
      _seen.add(key);
      _activeKey = key;
      _activeTurnKey = turnKey;
      stageNote = insight;
      break;
    }

    return CoachSelection(primary: primary, stageNote: stageNote);
  }

  // Per-category dedup identity. The qualifier picks what "again" means:
  // a different OPPONENT close to finishing is new teaching, a different
  // stock COUNT is not, every benchmark RAISE deserves a fresh alert, and
  // each distinct BAIT card is a live trap the player is about to step on —
  // deduping bait by category alone went silent on the round's second bait.
  String _stageKey(CoachingInsight insight, int roundNumber) {
    final qualifier = switch (insight.category) {
      CoachingInsightCategory.scorePosture ||
      CoachingInsightCategory.opponentCloseToFinish =>
        insight.subjectSeat?.name ?? '',
      CoachingInsightCategory.benchmarkAlert =>
        '${insight.openingRequirement ?? 0}',
      CoachingInsightCategory.baitDiscard => insight.highlightCardIds.join(','),
      _ => '',
    };
    return '$roundNumber:${insight.category.name}:$qualifier';
  }
}
