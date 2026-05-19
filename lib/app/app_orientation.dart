import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Owns app-level orientation policy.
///
/// Menus and setup stay portrait-first. The table screen switches to landscape
/// while it is mounted so the four seats can use the screen edges naturally.
abstract final class AppOrientation {
  /// Locks the shell and non-table screens to portrait.
  static Future<void> usePortrait() async {
    if (kIsWeb) {
      return;
    }

    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  /// Locks the live table to landscape and hides system overlays.
  static Future<void> useLandscape() async {
    if (kIsWeb) {
      return;
    }

    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }
}
