import 'package:flutter/material.dart';

import '../../../domain/classic_hareeg/models/table_strictness.dart';
import '../audio/table_audio.dart';
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
    final scope = context.dependOnInheritedWidgetOfExactType<CardThemeScope>();
    return scope?.theme ?? CardThemeRegistry.byId(null);
  }

  @override
  bool updateShouldNotify(covariant CardThemeScope oldWidget) {
    return oldWidget.theme.id != theme.id;
  }
}

/// Inherits the active [TableStrictness] selection.
class StrictnessScope extends InheritedWidget {
  /// Creates a strictness scope.
  const StrictnessScope({
    super.key,
    required this.strictness,
    required super.child,
  });

  /// Active strictness tier.
  final TableStrictness strictness;

  /// Reads the nearest strictness tier; falls back to [TableStrictness.coaching]
  /// if not wrapped (matches the fresh-install default).
  static TableStrictness of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<StrictnessScope>();
    return scope?.strictness ?? TableStrictness.coaching;
  }

  @override
  bool updateShouldNotify(covariant StrictnessScope oldWidget) {
    return oldWidget.strictness != strictness;
  }
}

/// Provides a singleton [TableHaptics] gateway to descendants.
class HapticsScope extends InheritedWidget {
  /// Creates a haptics scope.
  const HapticsScope({super.key, required this.haptics, required super.child});

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

/// Provides a singleton [TableAudio] gateway to descendants.
class AudioScope extends InheritedWidget {
  /// Creates an audio scope.
  const AudioScope({super.key, required this.audio, required super.child});

  /// Shared audio gateway.
  final TableAudio audio;

  /// Reads the nearest audio gateway; falls back to a muted no-op gateway.
  static TableAudio of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AudioScope>();
    return scope?.audio ?? TableAudio.noop();
  }

  @override
  bool updateShouldNotify(covariant AudioScope oldWidget) {
    return oldWidget.audio != audio;
  }
}
