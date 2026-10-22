import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/persistence/preferences_repository.dart';
import '../../../data/updates/update_service.dart';
import '../../../domain/updates/app_release.dart';
import '../../../domain/updates/update_decision.dart';

/// Opens [url] outside the app; true when something handled it.
typedef ExternalUrlOpener = Future<bool> Function(Uri url);

/// Opens [url] in the platform browser or installer via `url_launcher`.
Future<bool> openExternalUrl(Uri url) async {
  try {
    return await launchUrl(url, mode: LaunchMode.externalApplication);
  } catch (error) {
    debugPrint('[updates] Could not open $url: $error');
    return false;
  }
}

/// App-wide state of the "update available" prompt.
///
/// Owned by the app shell, which knows the saved preferences, and listened to
/// by the home panel and the About screen's manual check. The automatic check
/// runs once per process, after the home screen is up, and never blocks it.
class UpdatePromptController extends ChangeNotifier {
  /// Creates the controller.
  ///
  /// [preferences] resolves to the loaded preferences (waiting for the first
  /// load); [onSkip] persists a skipped version.
  UpdatePromptController({
    required UpdateService service,
    required Future<GamePreferences> Function() preferences,
    required Future<void> Function(String version) onSkip,
    ExternalUrlOpener openUrl = openExternalUrl,
  }) : _service = service,
       _preferences = preferences,
       _onSkip = onSkip,
       _openUrl = openUrl;

  final UpdateService _service;
  final Future<GamePreferences> Function() _preferences;
  final Future<void> Function(String version) _onSkip;
  final ExternalUrlOpener _openUrl;

  UpdateOffer? _available;
  String? _installedVersion;
  var _collapsed = false;
  var _startupCheckStarted = false;
  var _disposed = false;

  /// Whether this platform has an update flow at all (false on web).
  bool get supported => _service.supported;

  /// The offer the home menu should show, or null to show nothing.
  UpdateOffer? get prompt => _collapsed ? null : _available;

  /// The installed version, once read.
  String? get installedVersion => _installedVersion;

  /// Runs the automatic launch check, once per process.
  Future<void> runStartupCheck() async {
    if (_startupCheckStarted || !supported) return;
    _startupCheckStarted = true;
    try {
      final preferences = await _preferences();
      _installedVersion = await _service.installedVersion();
      final offer = await _service.startupCheck(
        autoCheckEnabled: preferences.updateCheckEnabled,
        skippedVersion: preferences.skippedUpdateVersion,
      );
      if (offer != null) _available = offer;
      _notify();
    } catch (error) {
      debugPrint('[updates] Startup check failed: $error');
    }
  }

  /// Reads the installed version for display.
  ///
  /// Notifies only after an await and only on a change, so calling it from
  /// `initState` never marks another listener dirty mid-build.
  Future<String?> loadInstalledVersion() async {
    if (_installedVersion != null) return _installedVersion;
    final version = await _service.installedVersion();
    if (version != null && version != _installedVersion) {
      _installedVersion = version;
      _notify();
    }
    return version;
  }

  /// The manual check. A newer, unskipped release also becomes the home
  /// prompt, so leaving the About screen shows it there too.
  Future<UpdateCheckResult> checkNow() async {
    final result = await _service.checkNow();
    _installedVersion ??= await _service.installedVersion();
    if (result is UpdateCheckAvailable) {
      GamePreferences? preferences;
      try {
        preferences = await _preferences();
      } catch (_) {
        preferences = null;
      }
      if (shouldOfferUpdate(
        installedVersion: _installedVersion,
        release: result.offer.newest,
        skippedVersion: preferences?.skippedUpdateVersion,
      )) {
        _available = result.offer;
        _collapsed = false;
      }
    }
    _notify();
    return result;
  }

  /// Hides the prompt for this session only.
  void later() {
    _collapsed = true;
    _notify();
  }

  /// Skips the offered release (the offer's newest) for good: the prompt
  /// returns only for a newer one.
  Future<void> skip() async {
    final offer = _available;
    if (offer == null) return;
    _available = null;
    _notify();
    await _onSkip(offer.newest.version.toString());
  }

  /// Opens the release's download, falling back to its release page.
  Future<bool> download(AppRelease release) =>
      _openUrl(release.downloadUrl ?? release.releaseNotesUrl);

  /// Opens the release page.
  Future<bool> openReleaseNotes(AppRelease release) =>
      _openUrl(release.releaseNotesUrl);

  /// Opens an arbitrary [url] (the store listing).
  Future<bool> open(Uri url) => _openUrl(url);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
