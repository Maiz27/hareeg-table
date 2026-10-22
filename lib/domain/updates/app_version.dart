/// A semantic app version: `major.minor.patch` plus an optional pre-release.
///
/// Every published build so far is a pre-release (`1.0.0-alpha.12`), so the
/// ordering rules for pre-release identifiers carry real weight here:
///
/// - the numeric core compares first, field by field;
/// - a version **without** a pre-release is newer than the same core with
///   one (`1.0.0-beta.1 < 1.0.0`);
/// - pre-release identifiers compare dot-segment by dot-segment, numeric
///   segments numerically (`alpha.9 < alpha.12`), anything else lexically
///   (`alpha < beta`), a numeric segment sorting below a textual one, and a
///   shorter list below a longer one it is a prefix of.
///
/// Build metadata (`+42`) is accepted and ignored, as is a leading `v` (tags
/// are named `v1.0.0-alpha.12`).
class AppVersion implements Comparable<AppVersion> {
  /// Creates a version from its parts.
  const AppVersion({
    required this.major,
    required this.minor,
    required this.patch,
    this.preRelease = const [],
  });

  static final _pattern = RegExp(
    r'^[vV]?(\d+)\.(\d+)\.(\d+)'
    r'(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?'
    r'(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$',
  );

  /// Parses [source], or returns null when it is not a version.
  ///
  /// Null is the answer the update flow relies on: a tag or installed version
  /// that cannot be read is never treated as "newer".
  static AppVersion? tryParse(String? source) {
    if (source == null) return null;
    final match = _pattern.firstMatch(source.trim());
    if (match == null) return null;
    final major = int.tryParse(match.group(1)!);
    final minor = int.tryParse(match.group(2)!);
    final patch = int.tryParse(match.group(3)!);
    if (major == null || minor == null || patch == null) return null;
    final pre = match.group(4);
    return AppVersion(
      major: major,
      minor: minor,
      patch: patch,
      preRelease: pre == null ? const [] : pre.split('.'),
    );
  }

  /// Major version.
  final int major;

  /// Minor version.
  final int minor;

  /// Patch version.
  final int patch;

  /// Pre-release identifiers (`['alpha', '12']`); empty for a final release.
  final List<String> preRelease;

  /// Whether this is a pre-release.
  bool get isPreRelease => preRelease.isNotEmpty;

  /// Whether this version is strictly newer than [other].
  bool isNewerThan(AppVersion other) => compareTo(other) > 0;

  @override
  int compareTo(AppVersion other) {
    final core = _compareInts(major, other.major) != 0
        ? _compareInts(major, other.major)
        : _compareInts(minor, other.minor) != 0
        ? _compareInts(minor, other.minor)
        : _compareInts(patch, other.patch);
    if (core != 0) return core;
    if (preRelease.isEmpty && other.preRelease.isEmpty) return 0;
    if (preRelease.isEmpty) return 1;
    if (other.preRelease.isEmpty) return -1;
    final shared = preRelease.length < other.preRelease.length
        ? preRelease.length
        : other.preRelease.length;
    for (var i = 0; i < shared; i++) {
      final result = _compareIdentifiers(preRelease[i], other.preRelease[i]);
      if (result != 0) return result;
    }
    return _compareInts(preRelease.length, other.preRelease.length);
  }

  static int _compareIdentifiers(String a, String b) {
    final numericA = _isNumeric(a) ? int.tryParse(a) : null;
    final numericB = _isNumeric(b) ? int.tryParse(b) : null;
    if (numericA != null && numericB != null) {
      return _compareInts(numericA, numericB);
    }
    if (numericA != null) return -1;
    if (numericB != null) return 1;
    return a.compareTo(b).sign;
  }

  static bool _isNumeric(String value) => RegExp(r'^\d+$').hasMatch(value);

  static int _compareInts(int a, int b) => a.compareTo(b).sign;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, preRelease.join('.'));

  @override
  String toString() => preRelease.isEmpty
      ? '$major.$minor.$patch'
      : '$major.$minor.$patch-${preRelease.join('.')}';
}
