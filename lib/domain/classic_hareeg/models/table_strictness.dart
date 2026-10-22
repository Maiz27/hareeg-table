/// How the table enforces rules, presents hints, and handles jokers.
///
/// Collapses the legacy three-axis surface (rule preset × table aids ×
/// memory joker display) into a single ladder. Lower tiers favor teaching
/// (illegal moves blocked, hints shown, joker identities persistent); higher
/// tiers favor authentic play (mistakes allowed with penalties, hints gone,
/// joker identities revealed only briefly).
///
/// Rules-relevant derivations live on `StrictnessRuleProfile`
/// (`lib/domain/classic_hareeg/rules/strictness_rule_profile.dart`).
/// UI-relevant derivations live on `StrictnessUiProfile`
/// (`lib/ui/core/strictness/strictness_ui_profile.dart`).
enum TableStrictness {
  /// Blocks illegal moves; shows proactive contextual hints (the coaching
  /// advisor surfaces the best move and rings the cards it points to) and full
  /// inspect detail. Persistent joker identity badge.
  coaching('Coaching', 'Blocks illegal moves and shows proactive hints.'),

  /// Blocks illegal moves; no proactive hints. Persistent joker identity
  /// badge.
  standard('Standard', 'Blocks illegal moves, no proactive hints.'),

  /// Allows selected mistakes with a +3 score penalty; no hints. Joker
  /// identity revealed briefly on placement then hidden — players must
  /// remember.
  strict('Strict', 'Allows mistakes with +3 penalty, no hints.'),

  /// Allows selected mistakes with a +17 score penalty and round-out; no
  /// hints. Joker identity revealed briefly on placement then hidden.
  table('Table', 'Allows mistakes with +17 and round-out, no hints.');

  const TableStrictness(this.label, this.description);

  /// Player-facing label.
  final String label;

  /// Short setup description.
  final String description;

  /// Parses a saved enum name, falling back to [standard] when missing or
  /// unrecognized. Standard is the fresh-install default: illegal moves stay
  /// blocked and nothing is charged, so it is a safe fallback for corrupted
  /// persistence.
  static TableStrictness fromName(String? name) {
    return _enumByName(TableStrictness.values, name) ??
        TableStrictness.standard;
  }
}

T? _enumByName<T extends Enum>(Iterable<T> values, String? name) {
  if (name == null) {
    return null;
  }

  for (final value in values) {
    if (value.name == name) {
      return value;
    }
  }

  return null;
}
