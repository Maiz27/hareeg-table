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

  /// [notes] as headed lists of plain-text items for the in-app prompt.
  List<ReleaseNoteSection> get noteSections => parseReleaseNotes(notes);

  /// JSON-compatible form for the update cache.
  Map<String, Object?> toJson() => {
    'tag': tag,
    'releaseNotesUrl': releaseNotesUrl.toString(),
    if (downloadUrl != null) 'downloadUrl': downloadUrl.toString(),
    'notes': notes,
    if (publishedAt != null) 'publishedAt': publishedAt!.toIso8601String(),
  };
}

/// One heading of release notes and the items listed under it.
class ReleaseNoteSection {
  /// Creates a section.
  const ReleaseNoteSection({this.heading, required this.items});

  /// The section heading, or null for items that precede any heading.
  final String? heading;

  /// Plain-text items, one per bullet or paragraph line.
  final List<String> items;
}

/// Reads markdown release notes into headed lists of plain-text items.
///
/// A release body (release-please output) is a version heading, then
/// `### Features` / `### Bug Fixes` headings with one bullet per change.
/// Headings become sections; bullets and plain paragraphs become items.
/// Links, images, emphasis, inline code, HTML comments, fenced code, rules
/// and the trailing commit hash are stripped. The version heading is
/// dropped because the prompt title already names the version. It is a
/// digest for a prompt, not a renderer.
List<ReleaseNoteSection> parseReleaseNotes(String markdown) {
  var text = markdown.replaceAll('\r\n', '\n');
  text = text.replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ');
  text = text.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
  final sections = <ReleaseNoteSection>[];
  String? heading;
  var items = <String>[];
  void flush() {
    if (items.isNotEmpty) {
      sections.add(ReleaseNoteSection(heading: heading, items: items));
    }
    items = <String>[];
  }

  for (final raw in text.split('\n')) {
    var line = raw.trim();
    if (line.isEmpty) continue;
    if (RegExp(r'^([-*_]\s*){3,}$').hasMatch(line)) continue;
    final headingMatch = RegExp(r'^#{1,6}\s*(.*)$').firstMatch(line);
    if (headingMatch != null) {
      flush();
      final title = _plainNoteText(headingMatch.group(1)!);
      heading = title.isEmpty || _versionHeading.hasMatch(title) ? null : title;
      continue;
    }
    line = line.replaceFirst(RegExp(r'^>\s*'), '');
    line = line.replaceFirst(RegExp(r'^([-*+]|\d+[.)])\s+'), '');
    final item = _plainNoteText(line);
    if (item.isNotEmpty) items.add(item);
  }
  flush();
  return sections;
}

final _versionHeading = RegExp(r'^[vV]?\d+\.\d+\.\d+');

String _plainNoteText(String line) {
  var text = line.replaceAllMapped(
    RegExp(r'!\[([^\]]*)\]\([^)]*\)'),
    (match) => match.group(1)!,
  );
  text = text.replaceAllMapped(
    RegExp(r'\[([^\]]*)\]\([^)]*\)'),
    (match) => match.group(1)!,
  );
  text = text.replaceAll(RegExp(r'(\*\*|__|\*|`|~~)'), '');
  text = text.replaceAll(RegExp(r'<[^>]+>'), '');
  // release-please ends each item with its commit: "… ([abc1234](url))",
  // which is "(abc1234)" once the link is gone and says nothing to a player.
  text = text.replaceAll(RegExp(r'\s*\(\s*[0-9a-f]{7,40}\s*\)\s*$'), '');
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}
