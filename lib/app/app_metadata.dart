import '../domain/classic_hareeg/reporting/classic_hareeg_match_report.dart';

/// Compile-time app metadata used by diagnostic exports.
abstract final class HareegAppMetadata {
  /// App/package identifier used by release builds.
  static const appId = 'com.maiz27.hareegtable';

  /// Human-readable app name.
  static const appName = 'Hareeg Table';

  /// Version name baked into reports when no dart-define override is supplied.
  ///
  /// Release APK builds currently set the native build name from `version.txt`.
  /// A future package-info adapter can replace this source without changing the
  /// match report schema.
  static const version = String.fromEnvironment(
    'HAREEG_TABLE_VERSION',
    defaultValue: '1.0.0-alpha.9',
  );

  /// Build number baked into reports when no dart-define override is supplied.
  static const buildNumber = String.fromEnvironment(
    'HAREEG_TABLE_BUILD_NUMBER',
    defaultValue: 'debug',
  );

  /// App metadata shape embedded in match reports.
  static const reportMetadata = MatchReportAppMetadata(
    appId: appId,
    appName: appName,
    version: version,
    buildNumber: buildNumber,
  );
}
