import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum _OrientationMode { portrait, landscape }

/// Carries out an orientation request.
///
/// Extracted so a test can observe what a screen asked for. A plain
/// `SystemChannels.platform` mock is not enough on its own: the real policy
/// skips the platform call when the requested mode is already in force, so a
/// mode left over from an earlier screen would suppress the call entirely and
/// a test could pass while asserting nothing.
abstract interface class OrientationPolicy {
  /// Requests portrait.
  Future<void> usePortrait();

  /// Requests landscape.
  Future<void> useLandscape();
}

/// The real policy: talks to the platform, and skips redundant requests.
class SystemOrientationPolicy implements OrientationPolicy {
  /// Creates a system policy.
  SystemOrientationPolicy();

  _OrientationMode? _currentMode;

  @override
  Future<void> usePortrait() async {
    if (kIsWeb || _currentMode == _OrientationMode.portrait) {
      return;
    }
    _currentMode = _OrientationMode.portrait;

    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  @override
  Future<void> useLandscape() async {
    if (kIsWeb || _currentMode == _OrientationMode.landscape) {
      return;
    }
    _currentMode = _OrientationMode.landscape;

    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }
}

/// Owns app-level orientation policy.
///
/// Menus and setup stay portrait-first. The table screen switches to landscape
/// while it is mounted so the four seats can use the screen edges naturally,
/// and replay review does the same because it renders the same table.
abstract final class AppOrientation {
  static OrientationPolicy _policy = SystemOrientationPolicy();

  /// Swaps in a recording policy for a test, returning the previous one.
  @visibleForTesting
  static OrientationPolicy installPolicy(OrientationPolicy policy) {
    final previous = _policy;
    _policy = policy;
    return previous;
  }

  /// Restores the real policy with a fresh, empty mode cache.
  @visibleForTesting
  static void resetPolicy() => _policy = SystemOrientationPolicy();

  /// Locks the shell and non-table screens to portrait.
  static Future<void> usePortrait() => _policy.usePortrait();

  /// Locks the live table to landscape and hides system overlays.
  static Future<void> useLandscape() => _policy.useLandscape();
}
