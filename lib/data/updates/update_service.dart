import 'package:flutter/foundation.dart';

import '../../domain/updates/update_decision.dart';
import 'installed_version_source.dart';
import 'update_cache_repository.dart';
import 'update_channel.dart';

/// Outcome of a manual "Check for updates".
sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

/// A newer release than the installed build exists.
final class UpdateCheckAvailable extends UpdateCheckResult {
  /// Creates an available-update result.
  const UpdateCheckAvailable(this.offer);

  /// The newest release and every listed release between it and the
  /// installed build.
  final UpdateOffer offer;
}

/// The installed build is the newest release.
final class UpdateCheckUpToDate extends UpdateCheckResult {
  /// Creates an up-to-date result.
  const UpdateCheckUpToDate();
}

/// The check did not get an answer (offline, rate limited, bad response).
final class UpdateCheckFailed extends UpdateCheckResult {
  /// Creates a failed result.
  const UpdateCheckFailed([this.kind]);

  /// The failure category, when the channel reported one.
  final UpdateCheckFailureKind? kind;
}

/// Updates come through a store; the app can only open its listing.
final class UpdateCheckStoreManaged extends UpdateCheckResult {
  /// Creates a store-managed result.
  const UpdateCheckStoreManaged(this.listingUrl);

  /// The store listing.
  final Uri listingUrl;
}

/// Learns about newer releases: the automatic once-a-day check and the
/// manual check.
///
/// All failures are silent here (a debug log line, never an exception): an
/// update check is a courtesy, and nothing about it may disturb the menu.
class UpdateService {
  /// Creates the service.
  ///
  /// [supported] is false on web, where the PWA updates itself; every method
  /// is then a no-op. [clock] is injectable for cadence tests.
  UpdateService({
    required UpdateChannel channel,
    required InstalledVersionSource installedVersion,
    required UpdateCacheRepository cache,
    this.supported = !kIsWeb,
    DateTime Function()? clock,
    this.interval = updateCheckInterval,
  }) : _channel = channel,
       _installedVersion = installedVersion,
       _cache = cache,
       _clock = clock ?? DateTime.now;

  final UpdateChannel _channel;
  final InstalledVersionSource _installedVersion;
  final UpdateCacheRepository _cache;
  final DateTime Function() _clock;

  /// Whether this platform checks for updates at all.
  final bool supported;

  /// Minimum gap between automatic network checks.
  final Duration interval;

  String? _installed;

  /// The installed version name, or null when it cannot be read.
  Future<String?> installedVersion() async {
    if (_installed != null) return _installed;
    try {
      return _installed = await _installedVersion.installedVersion();
    } catch (error) {
      debugPrint('[updates] Could not read the installed version: $error');
      return null;
    }
  }

  /// The automatic launch check.
  ///
  /// Reaches the network only when [autoCheckEnabled] and the last successful
  /// check is at least [interval] old; otherwise it answers from the cached
  /// listing. Returns the offer to show, or null.
  Future<UpdateOffer?> startupCheck({
    required bool autoCheckEnabled,
    String? skippedVersion,
  }) async {
    if (!supported || !autoCheckEnabled || !_channel.reportsVersions) {
      return null;
    }
    try {
      final installed = await installedVersion();
      if (installed == null) return null;
      var cache = await _loadCache();
      if (isUpdateCheckDue(
        lastCheckedAt: cache.lastCheckedAt,
        now: _clock(),
        interval: interval,
      )) {
        try {
          cache = await _fetchAndRemember();
        } on UpdateCheckException catch (error) {
          debugPrint('[updates] Automatic check failed: $error');
        }
      }
      return buildUpdateOffer(
        installedVersion: installed,
        releases: cache.releases,
        listingMayBeTruncated: cache.mayBeTruncated,
        skippedVersion: skippedVersion,
      );
    } catch (error) {
      debugPrint('[updates] Automatic check failed: $error');
      return null;
    }
  }

  /// The manual check: always asks the channel, whatever the cadence.
  ///
  /// A skipped version is still reported here, because the player asked.
  Future<UpdateCheckResult> checkNow() async {
    if (!supported) return const UpdateCheckFailed();
    final listing = _channel.storeListingUrl;
    if (!_channel.reportsVersions && listing != null) {
      return UpdateCheckStoreManaged(listing);
    }
    try {
      final installed = await installedVersion();
      if (installed == null) return const UpdateCheckFailed();
      final cache = await _fetchAndRemember();
      final offer = buildUpdateOffer(
        installedVersion: installed,
        releases: cache.releases,
        listingMayBeTruncated: cache.mayBeTruncated,
      );
      return offer == null
          ? const UpdateCheckUpToDate()
          : UpdateCheckAvailable(offer);
    } on UpdateCheckException catch (error) {
      debugPrint('[updates] Manual check failed: $error');
      return UpdateCheckFailed(error.kind);
    } catch (error) {
      debugPrint('[updates] Manual check failed: $error');
      return const UpdateCheckFailed();
    }
  }

  Future<UpdateCache> _loadCache() async {
    try {
      return await _cache.load();
    } catch (error) {
      debugPrint('[updates] Could not read the update cache: $error');
      return UpdateCache.empty;
    }
  }

  /// Fetches the release listing and records it with the check time. Only a
  /// successful lookup is recorded, so an offline launch retries next time.
  Future<UpdateCache> _fetchAndRemember() async {
    final listing = await _channel.fetchReleases();
    final next = UpdateCache(
      lastCheckedAt: _clock(),
      releases: listing.releases,
      mayBeTruncated: listing.mayBeTruncated,
    );
    try {
      await _cache.save(next);
    } catch (error) {
      debugPrint('[updates] Could not save the update cache: $error');
    }
    return next;
  }
}
