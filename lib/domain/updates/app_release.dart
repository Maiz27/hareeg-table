import 'app_version.dart';

/// A published app release, as the update flow knows it.
///
/// Channel-neutral: the GitHub channel builds one from the releases API, and
/// the update cache stores one so a known release survives an offline launch.
class AppRelease {
  /// Creates a release description.
  const AppRelease({
    required this.tag,
    required this.version,
    required this.releaseNotesUrl,
    this.downloadUrl,
    this.notes = '',
    this.publishedAt,
  });

  /// Restores a cached release, or returns null when [json] is not one.
  static AppRelease? fromJson(Map<String, Object?>? json) {
    if (json == null) return null;
    final tag = json['tag'];
    final notesUrl = json['releaseNotesUrl'];
    if (tag is! String || notesUrl is! String) return null;
    final version = AppVersion.tryParse(tag);
    final releaseNotesUrl = Uri.tryParse(notesUrl);
    if (version == null || releaseNotesUrl == null) return null;
    final download = json['downloadUrl'];
    final notes = json['notes'];
    final published = json['publishedAt'];
    return AppRelease(
      tag: tag,
      version: version,
      releaseNotesUrl: releaseNotesUrl,
      downloadUrl: download is String ? Uri.tryParse(download) : null,
      notes: notes is String ? notes : '',
      publishedAt: published is String ? DateTime.tryParse(published) : null,
    );
  }

  /// The release tag, e.g. `v1.0.0-alpha.12`.
  final String tag;

  /// The parsed version behind [tag].
  final AppVersion version;

  /// The release page, for the full notes.
  final Uri releaseNotesUrl;

  /// The installable artifact, or null when the release has none for this
  /// platform (the release page is the fallback).
  final Uri? downloadUrl;

  /// Raw release notes (markdown).
  final String notes;

  /// When the release was published, when known.
  final DateTime? publishedAt;

  /// A short plain-text digest of [notes] for the in-app prompt.
  String get notesSummary => summarizeReleaseNotes(notes);

  /// JSON-compatible form for the update cache.
  Map<String, Object?> toJson() => {
    'tag': tag,
    'releaseNotesUrl': releaseNotesUrl.toString(),
    if (downloadUrl != null) 'downloadUrl': downloadUrl.toString(),
    'notes': notes,
    if (publishedAt != null) 'publishedAt': publishedAt!.toIso8601String(),
  };
}

/// Reduces markdown release notes to plain text of at most [maxLength]
/// characters, cut at a word boundary with an ellipsis when trimmed.
///
/// Strips the markers a release body actually carries (headings, list
/// bullets, emphasis, inline code, links, images, HTML comments) and folds
/// the lines into one paragraph. It is a digest for a prompt, not a renderer.
String summarizeReleaseNotes(String markdown, {int maxLength = 300}) {
  var text = markdown.replaceAll('\r\n', '\n');
  text = text.replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ');
  text = text.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
  text = text.replaceAll(RegExp(r'!\[([^\]]*)\]\([^)]*\)'), r'$1');
  text = text.replaceAllMapped(
    RegExp(r'\[([^\]]*)\]\([^)]*\)'),
    (match) => match.group(1)!,
  );
  final lines = <String>[];
  for (var line in text.split('\n')) {
    line = line.trim();
    line = line.replaceFirst(RegExp(r'^#{1,6}\s*'), '');
    line = line.replaceFirst(RegExp(r'^>\s*'), '');
    line = line.replaceFirst(RegExp(r'^([-*+]|\d+[.)])\s+'), '');
    if (RegExp(r'^([-*_]\s*){3,}$').hasMatch(line)) continue;
    line = line.replaceAll(RegExp(r'(\*\*|__|\*|`|~~)'), '');
    line = line.replaceAll(RegExp(r'<[^>]+>'), '');
    line = line.trim();
    if (line.isNotEmpty) lines.add(line);
  }
  final joined = lines.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (joined.length <= maxLength) return joined;
  var cut = joined.substring(0, maxLength);
  final lastSpace = cut.lastIndexOf(' ');
  if (lastSpace > maxLength * 0.6) cut = cut.substring(0, lastSpace);
  return '${cut.trimRight()}…';
}
