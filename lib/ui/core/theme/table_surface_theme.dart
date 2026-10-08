/// Available table surface themes.
enum TableSurfaceTheme {
  /// Generated Sandline Lounge surface matching the default card theme.
  sandline,

  /// Warm dark felt lounge table.
  felt,

  /// Light wood physical tabletop with herbal accent.
  wood,

  /// Cool midnight sapphire velvet table.
  sapphire,

  /// Warm Sudanese clay surface with brass hairline.
  clay;

  /// Parses a saved enum name.
  static TableSurfaceTheme fromName(String? name) {
    for (final theme in TableSurfaceTheme.values) {
      if (theme.name == name) {
        return theme;
      }
    }
    return TableSurfaceTheme.sandline;
  }
}
