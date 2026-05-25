import 'card_theme.dart';
import 'themes/bundled_themes.dart';

/// Registry of bundled card themes shown in the picker.
///
/// Order matters — this is the order players see in Settings → Card theme.
abstract final class CardThemeRegistry {
  /// Default theme id used on first launch.
  static const defaultThemeId = 'sandline_lounge';

  static const _themes = <HareegCardTheme>[
    sandlineLoungeCardTheme,
    ironRoseCardTheme,
    minimalSymbolsCardTheme,
    kenneyClassicCardTheme,
    wikimediaPdCardTheme,
  ];

  /// Returns all bundled themes.
  static List<HareegCardTheme> all() => List.unmodifiable(_themes);

  /// Returns the theme matching [id], or the default theme if no match.
  static HareegCardTheme byId(String? id) {
    for (final theme in _themes) {
      if (theme.id == id) {
        return theme;
      }
    }
    return _themes.first;
  }
}
