import 'package:hareeg_table/data/updates/installed_version_source.dart';
import 'package:hareeg_table/data/updates/update_channel.dart';
import 'package:hareeg_table/domain/updates/app_release.dart';
import 'package:hareeg_table/domain/updates/app_version.dart';

/// A release with predictable URLs for [tag].
AppRelease fakeRelease(String tag, {String notes = 'Notes for the release.'}) {
  return AppRelease(
    tag: tag,
    version: AppVersion.tryParse(tag)!,
    releaseNotesUrl: Uri.parse('https://example.test/releases/$tag'),
    downloadUrl: Uri.parse('https://example.test/download/$tag.apk'),
    notes: notes,
  );
}

/// An [UpdateChannel] that answers from memory and counts its lookups.
class FakeUpdateChannel implements UpdateChannel {
  FakeUpdateChannel({
    AppRelease? release,
    List<AppRelease>? releases,
    this.mayBeTruncated = false,
    this.failure,
  }) : releases = releases ?? [?release];

  /// What the next lookup returns, newest first.
  List<AppRelease> releases;

  /// Whether the next lookup reports a possibly truncated listing.
  bool mayBeTruncated;

  /// When set, the next lookups throw this instead.
  UpdateCheckException? failure;

  /// How many lookups ran.
  var fetchCount = 0;

  @override
  bool get reportsVersions => true;

  @override
  Uri? get storeListingUrl => null;

  @override
  Future<ReleaseListing> fetchReleases() async {
    fetchCount++;
    final error = failure;
    if (error != null) throw error;
    return ReleaseListing(releases: releases, mayBeTruncated: mayBeTruncated);
  }
}

/// A fixed installed version.
class FakeInstalledVersionSource implements InstalledVersionSource {
  const FakeInstalledVersionSource(this.version);

  final String version;

  @override
  Future<String> installedVersion() async => version;
}
