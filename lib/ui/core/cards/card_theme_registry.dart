import 'card_theme.dart';
import 'themes/hareeg_original_theme.dart';
import 'themes/high_contrast_theme.dart';
import 'themes/kenney_classic_theme.dart';
import 'themes/minimal_symbols_theme.dart';
import 'themes/sandline_lounge_theme.dart';
import 'themes/wikimedia_pd_theme.dart';

/// Registry of bundled card themes shown in the picker.
///
/// Order matters — this is the order players see in Settings → Card theme.
abstract final class CardThemeRegistry {
  /// Default theme id used on first launch.
  static const defaultThemeId = 'hareeg_original';

  static const _themes = <HareegCardTheme>[
    HareegOriginalCardTheme(),
    SandlineLoungeCardTheme(),
    HighContrastCardTheme(),
    MinimalSymbolsCardTheme(),
    KenneyClassicCardTheme(),
    WikimediaPdCardTheme(),
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
