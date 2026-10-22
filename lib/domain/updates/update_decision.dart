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
  final installed = AppVersion.tryParse(installedVersion);
  if (installed == null) return false;
  if (!release.version.isNewerThan(installed)) return false;
  final skipped = AppVersion.tryParse(skippedVersion);
  if (skipped != null && !release.version.isNewerThan(skipped)) return false;
  return true;
}
