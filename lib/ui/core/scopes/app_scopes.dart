import 'package:flutter/material.dart';

import '../aids/table_aids.dart';
import '../cards/card_theme.dart';
import '../cards/card_theme_registry.dart';
import '../haptics/table_haptics.dart';

/// Inherits the active [HareegCardTheme] from preferences.
class CardThemeScope extends InheritedWidget {
  /// Creates a card-theme scope.
  const CardThemeScope({super.key, required this.theme, required super.child});

  /// Active card theme.
  final HareegCardTheme theme;

  /// Reads the nearest theme; falls back to the default if not wrapped.
  static HareegCardTheme of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<CardThemeScope>();
    return scope?.theme ?? CardThemeRegistry.byId(null);
  }

  @override
  bool updateShouldNotify(covariant CardThemeScope oldWidget) {
    return oldWidget.theme.id != theme.id;
  }
}

/// Inherits the active [TableAids] selection.
class AidsScope extends InheritedWidget {
  /// Creates a table-aids scope.
  const AidsScope({super.key, required this.aids, required super.child});

  /// Active aid level.
  final TableAids aids;

  /// Reads the nearest aid level; falls back to [TableAids.guided] if not
  /// wrapped.
  static TableAids of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AidsScope>();
    return scope?.aids ?? TableAids.guided;
  }

  @override
  bool updateShouldNotify(covariant AidsScope oldWidget) {
    return oldWidget.aids != aids;
  }
}

/// Provides a singleton [TableHaptics] gateway to descendants.
class HapticsScope extends InheritedWidget {
  /// Creates a haptics scope.
  const HapticsScope({
    super.key,
    required this.haptics,
    required super.child,
  });

  /// Shared haptics gateway.
  final TableHaptics haptics;

  /// Reads the nearest haptics gateway; creates an enabled fallback if not
  /// wrapped (useful for tests).
  static TableHaptics of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<HapticsScope>();
    return scope?.haptics ?? TableHaptics();
  }

  @override
  bool updateShouldNotify(covariant HapticsScope oldWidget) {
    return oldWidget.haptics != haptics;
  }
}
