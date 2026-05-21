/// Player-selectable table aid level.
///
/// Aid level is distinct from CPU difficulty. It governs how much help the
/// UI surfaces (legal hints, cover target highlights, pending warnings,
/// invalid action explanations, valid Fifty prompts). Rule scoring is
/// untouched by this choice — see `docs/rules/classic-hareeg.md`.
enum TableAids {
  /// First-time default. Full hints: legal targets glow, pending warnings
  /// shout, invalid actions explain themselves, valid Fifty prompts appear.
  guided('Guided', 'Full hints, legal target highlights, explanations'),

  /// Legal meld picker still visible, fewer proactive hints.
  standard('Standard', 'Legal meld picker remains; fewer proactive hints'),

  /// Minimal aids while preserving accessibility/state feedback.
  tableMode('Table mode', 'Minimal aids — for confident players');

  const TableAids(this.label, this.description);

  /// Settings label.
  final String label;

  /// Long description used in pickers and pause overlay.
  final String description;

  /// Whether the UI should surface proactive hints (legal target glows,
  /// auto-explanations) at this level.
  bool get showsProactiveHints => this == TableAids.guided;

  /// Whether the meld picker should remain visible (true for Guided and
  /// Standard; Table mode hides it and relies on player meld assembly).
  bool get showsMeldPicker => this != TableAids.tableMode;

  /// Restores from a saved enum name.
  static TableAids fromName(String? name) {
    for (final value in TableAids.values) {
      if (value.name == name) {
        return value;
      }
    }
    return TableAids.guided;
  }
}
