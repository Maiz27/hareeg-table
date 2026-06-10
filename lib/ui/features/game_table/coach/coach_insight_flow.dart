import '../../../../cpu/classic_hareeg/coaching/coaching_insight.dart';

/// Cross-turn surfacing policy for coaching insights — the anti-spam layer.
///
/// The advisor is pure and re-emits every applicable insight on every call;
/// this flow decides which one the table actually shows. Per-turn guidance
/// (wins, plays, floors) always surfaces. STAGE banners
/// ([CoachingInsightCategory.isStageBanner]) surface at most once per round
/// each: they hold the callout for the turn they first appear in, then yield
/// to the guidance ranked below them for the rest of the round. Without this,
/// a banner whose condition holds all round (thin stock, score pressure)
/// would repeat every turn — the exact fixation failure the overhaul removes.
///
/// One instance lives in the table screen's state for the lifetime of a match;
/// keys embed the round number, so no per-round reset is needed.
class CoachInsightFlow {
  /// Creates an insight flow with no banner history.
  CoachInsightFlow();

  final Set<String> _seen = {};
  String? _activeKey;
  String? _activeTurnKey;

  /// Picks the insight to present from priority-sorted [insights], or null
  /// when nothing should show. Call only when the coach is actually allowed
  /// to display — selection marks stage banners as consumed.
  ///
  /// [turnKey] identifies the current turn (any value that changes when the
  /// turn passes); a banner keeps the callout while it stays the top eligible
  /// insight within one turn, then is retired for the round.
  CoachingInsight? select({
    required List<CoachingInsight> insights,
    required int roundNumber,
    required String turnKey,
  }) {
    for (final insight in insights) {
      if (!insight.category.isStageBanner) {
        _activeKey = null;
        return insight;
      }
      final key = _stageKey(insight, roundNumber);
      if (key == _activeKey && turnKey == _activeTurnKey) {
        // Still inside the turn this banner first surfaced in: keep it up.
        return insight;
      }
      if (_seen.contains(key)) {
        // Already taught this round; let lower-priority guidance through.
        continue;
      }
      _seen.add(key);
      _activeKey = key;
      _activeTurnKey = turnKey;
      return insight;
    }
    _activeKey = null;
    return null;
  }

  // Per-category dedup identity. The qualifier picks what "again" means:
  // a different OPPONENT close to finishing is new teaching, a different
  // stock COUNT is not, and every benchmark RAISE deserves a fresh alert.
  String _stageKey(CoachingInsight insight, int roundNumber) {
    final qualifier = switch (insight.category) {
      CoachingInsightCategory.scorePosture ||
      CoachingInsightCategory.opponentCloseToFinish =>
        insight.subjectSeat?.name ?? '',
      CoachingInsightCategory.benchmarkAlert =>
        '${insight.openingRequirement ?? 0}',
      _ => '',
    };
    return '$roundNumber:${insight.category.name}:$qualifier';
  }
}
