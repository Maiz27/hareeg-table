/// Available table surface themes.
enum TableSurfaceTheme {
  /// Current dark felt lounge table.
  felt('Dark felt'),

  /// Light wood physical tabletop.
  wood('Light wood');

  const TableSurfaceTheme(this.label);

  /// Settings label.
  final String label;

  /// Parses a saved enum name.
  static TableSurfaceTheme fromName(String? name) {
    for (final theme in TableSurfaceTheme.values) {
      if (theme.name == name) {
        return theme;
      }
    }
    return TableSurfaceTheme.felt;
  }
}
