import 'package:package_info_plus/package_info_plus.dart';

/// Reads the version name of the build that is running.
abstract interface class InstalledVersionSource {
  /// The installed version name, e.g. `1.0.0-alpha.12`.
  Future<String> installedVersion();
}

/// Reads the native version name through `package_info_plus`.
///
/// Release builds set it from `version.txt`; debug builds report pubspec's
/// `1.0.0-alpha.1`. `HareegAppMetadata.version` is deliberately not used: it
/// is a dart-define that CI never passes, so it would always read stale.
class PackageInfoInstalledVersionSource implements InstalledVersionSource {
  /// Creates the package-info reader.
  const PackageInfoInstalledVersionSource();

  @override
  Future<String> installedVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }
}
