import 'app_release.dart';
import 'app_version.dart';

/// How often the automatic check may reach the network.
const updateCheckInterval = Duration(hours: 24);

/// Whether an automatic check is due at [now], given the last successful
/// check at [lastCheckedAt].
///
/// Due when there has never been a check, when [interval] has passed, or when
/// the clock reads earlier than the last check (a clock moved backwards must
/// not silence checks for however long it was wound back).
bool isUpdateCheckDue({
  required DateTime? lastCheckedAt,
  required DateTime now,
  Duration interval = updateCheckInterval,
}) {
  if (lastCheckedAt == null) return true;
  final elapsed = now.difference(lastCheckedAt);
  return elapsed.isNegative || elapsed >= interval;
}

/// Whether [release] should be offered to a player running
/// [installedVersion] who skipped [skippedVersion].
///
/// Offered only when it is strictly newer than what is installed and strictly
/// newer than the skipped version, so skipping one release hides it until a
/// later one appears. An installed version that cannot be parsed offers
/// nothing: "no update" is the safe answer to a version the app cannot read.
bool shouldOfferUpdate({
  required String? installedVersion,
  required AppRelease? release,
  String? skippedVersion,
}) {
  if (release == null) return false;
  return buildUpdateOffer(
        installedVersion: installedVersion,
        releases: [release],
        listingMayBeTruncated: false,
        skippedVersion: skippedVersion,
      ) !=
      null;
}

/// What the update prompt offers: the newest release, plus every listed
/// release between it and the installed build, so the notes add up to
/// everything the player would get by updating.
class UpdateOffer {
  /// Creates an offer. [releases] is newest first and starts with [newest].
  const UpdateOffer({
    required this.newest,
    required this.releases,
    this.hasOlderUnlisted = false,
  });

  /// The release the prompt names, downloads and skips.
  final AppRelease newest;

  /// Every listed release newer than the installed build, newest first;
  /// [newest] is the first entry.
  final List<AppRelease> releases;

  /// True when the listing may have been cut short and even its oldest
  /// release is newer than the installed build: releases between it and the
  /// installed one may be missing, so the notes may not be the whole story.
  final bool hasOlderUnlisted;
}

/// Builds the offer for a player running [installedVersion] who skipped
/// [skippedVersion], from the channel's [releases] (any order).
///
/// Returns null when nothing should be offered, by the [shouldOfferUpdate]
/// rules: the newest release must be strictly newer than the installed and
/// the skipped versions, and an unreadable installed version offers nothing.
/// Releases between a skipped version and the newest one still contribute
/// their notes, because updating installs them all.
///
/// [listingMayBeTruncated] says the channel may have left older releases
/// out; only then can [UpdateOffer.hasOlderUnlisted] be true. A complete
/// listing that is entirely newer than the installed build is simply the
/// whole history.
UpdateOffer? buildUpdateOffer({
  required String? installedVersion,
  required List<AppRelease> releases,
  required bool listingMayBeTruncated,
  String? skippedVersion,
}) {
  final installed = AppVersion.tryParse(installedVersion);
  if (installed == null || releases.isEmpty) return null;
  final newer =
      releases
          .where((release) => release.version.isNewerThan(installed))
          .toList()
        ..sort((a, b) => b.version.compareTo(a.version));
  if (newer.isEmpty) return null;
  final newest = newer.first;
  final skipped = AppVersion.tryParse(skippedVersion);
  if (skipped != null && !newest.version.isNewerThan(skipped)) return null;
  final oldestListed = releases
      .map((release) => release.version)
      .reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
  return UpdateOffer(
    newest: newest,
    releases: List.unmodifiable(newer),
    hasOlderUnlisted:
        listingMayBeTruncated && oldestListed.isNewerThan(installed),
  );
}
