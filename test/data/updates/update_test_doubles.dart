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
  FakeUpdateChannel({this.release, this.failure});

  /// What the next lookup returns.
  AppRelease? release;

  /// When set, the next lookups throw this instead.
  UpdateCheckException? failure;

  /// How many lookups ran.
  var fetchCount = 0;

  @override
  bool get reportsVersions => true;

  @override
  Uri? get storeListingUrl => null;

  @override
  Future<AppRelease?> fetchLatestRelease() async {
    fetchCount++;
    final error = failure;
    if (error != null) throw error;
    return release;
  }
}

/// A fixed installed version.
class FakeInstalledVersionSource implements InstalledVersionSource {
  const FakeInstalledVersionSource(this.version);

  final String version;

  @override
  Future<String> installedVersion() async => version;
}
