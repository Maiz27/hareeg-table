import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Owns app-level orientation policy.
///
/// Menus and setup stay portrait-first. The table screen switches to landscape
/// while it is mounted so the four seats can use the screen edges naturally.
abstract final class AppOrientation {
  /// Locks the shell and non-table screens to portrait.
  static Future<void> usePortrait() {
    if (kIsWeb) {
      return Future<void>.value();
    }

    return SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  /// Locks the live table to landscape.
  static Future<void> useLandscape() {
    if (kIsWeb) {
      return Future<void>.value();
    }

    return SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }
}
