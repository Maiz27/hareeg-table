/// Available table surface themes.
enum TableSurfaceTheme {
  /// Warm dark felt lounge table.
  felt('Dark felt'),

  /// Light wood physical tabletop with herbal accent.
  wood('Light wood'),

  /// Cool midnight sapphire velvet table.
  sapphire('Midnight sapphire'),

  /// Warm Sudanese clay surface with brass hairline.
  clay('Crimson clay');

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
