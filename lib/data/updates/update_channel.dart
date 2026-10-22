import '../../domain/updates/app_release.dart';
import 'github_releases_update_channel.dart';
import 'play_store_update_channel.dart';

/// Why a release lookup failed.
enum UpdateCheckFailureKind {
  /// No connection, DNS failure, TLS failure or timeout.
  network,

  /// The server refused for rate limiting (GitHub answers 403 or 429).
  rateLimited,

  /// Any other non-success HTTP status.
  http,

  /// The response arrived but could not be read.
  malformed,
}

/// A release lookup that did not produce an answer.
class UpdateCheckException implements Exception {
  /// Creates a lookup failure.
  const UpdateCheckException(this.kind, [this.detail]);

  /// The failure category.
  final UpdateCheckFailureKind kind;

  /// Diagnostic detail for the debug log; never shown to the player.
  final Object? detail;

  @override
  String toString() => 'UpdateCheckException(${kind.name}: $detail)';
}

/// Where the app learns about newer releases.
///
/// The GitHub channel serves today's sideloaded APK. A store build delegates
/// updates to its store and only knows how to open its listing.
abstract interface class UpdateChannel {
  /// Whether this channel can tell which release is newest. False for a
  /// store channel, whose store does the comparison itself.
  bool get reportsVersions;

  /// The store listing to open instead of comparing versions, or null.
  Uri? get storeListingUrl;

  /// The published releases the channel can see, newest first; empty when it
  /// has none to report.
  ///
  /// Throws [UpdateCheckException] when the lookup fails.
  Future<ReleaseListing> fetchReleases();
}

/// The releases a channel reported, and whether older ones may exist beyond
/// what it returned.
class ReleaseListing {
  /// Creates a listing. [releases] is newest first.
  const ReleaseListing({this.releases = const [], this.mayBeTruncated = false});

  /// A listing with no releases that is known to be complete.
  static const empty = ReleaseListing();

  /// The usable releases, newest first.
  final List<AppRelease> releases;

  /// True when the channel returned a full page, so older releases may exist
  /// that it did not list. False when the listing is known to be complete.
  final bool mayBeTruncated;
}

/// The compile-time channel selector: `github` (default) or `play`.
const updateChannelName = String.fromEnvironment(
  'HAREEG_UPDATE_CHANNEL',
  defaultValue: 'github',
);

/// Builds the channel named by [name] (`HAREEG_UPDATE_CHANNEL`).
///
/// An unrecognised name falls back to GitHub, the only distribution that
/// exists today.
UpdateChannel createUpdateChannel({String name = updateChannelName}) {
  return switch (name.trim().toLowerCase()) {
    'play' || 'playstore' || 'play_store' => const PlayStoreUpdateChannel(),
    _ => GitHubReleasesUpdateChannel(),
  };
}
