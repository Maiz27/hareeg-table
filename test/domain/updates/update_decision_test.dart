import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/updates/app_release.dart';
import 'package:hareeg_table/domain/updates/app_version.dart';
import 'package:hareeg_table/domain/updates/update_decision.dart';

AppRelease release(String tag, {String notes = ''}) => AppRelease(
  tag: tag,
  version: AppVersion.tryParse(tag)!,
  releaseNotesUrl: Uri.parse('https://example.test/$tag'),
  notes: notes,
);

void main() {
  group('isUpdateCheckDue', () {
    final now = DateTime.utc(2026, 10, 22, 12);

    test('due when never checked', () {
      expect(isUpdateCheckDue(lastCheckedAt: null, now: now), isTrue);
    });

    test('not due inside 24 hours, due at and after', () {
      expect(
        isUpdateCheckDue(
          lastCheckedAt: now.subtract(const Duration(hours: 23, minutes: 59)),
          now: now,
        ),
        isFalse,
      );
      expect(
        isUpdateCheckDue(
          lastCheckedAt: now.subtract(const Duration(hours: 24)),
          now: now,
        ),
        isTrue,
      );
    });

    test('due when the clock reads earlier than the last check', () {
      expect(
        isUpdateCheckDue(
          lastCheckedAt: now.add(const Duration(days: 3)),
          now: now,
        ),
        isTrue,
      );
    });
  });

  group('shouldOfferUpdate', () {
    test('offers a strictly newer release', () {
      expect(
        shouldOfferUpdate(
          installedVersion: '1.0.0-alpha.12',
          release: release('v1.0.0-alpha.13'),
        ),
        isTrue,
      );
    });

    test('does not offer the same or an older release', () {
      for (final tag in ['v1.0.0-alpha.12', 'v1.0.0-alpha.9']) {
        expect(
          shouldOfferUpdate(
            installedVersion: '1.0.0-alpha.12',
            release: release(tag),
          ),
          isFalse,
          reason: tag,
        );
      }
    });

    test('a skipped release stays hidden until a newer one appears', () {
      expect(
        shouldOfferUpdate(
          installedVersion: '1.0.0-alpha.12',
          release: release('v1.0.0-alpha.13'),
          skippedVersion: '1.0.0-alpha.13',
        ),
        isFalse,
      );
      expect(
        shouldOfferUpdate(
          installedVersion: '1.0.0-alpha.12',
          release: release('v1.0.0-alpha.14'),
          skippedVersion: '1.0.0-alpha.13',
        ),
        isTrue,
      );
    });

    test('an unreadable installed version or no release offers nothing', () {
      expect(
        shouldOfferUpdate(
          installedVersion: 'debug',
          release: release('v9.0.0'),
        ),
        isFalse,
      );
      expect(
        shouldOfferUpdate(installedVersion: '1.0.0', release: null),
        isFalse,
      );
    });

    test('an unreadable skipped version is ignored', () {
      expect(
        shouldOfferUpdate(
          installedVersion: '1.0.0-alpha.12',
          release: release('v1.0.0-alpha.13'),
          skippedVersion: 'garbage',
        ),
        isTrue,
      );
    });
  });

  group('summarizeReleaseNotes', () {
    test('strips markdown markers and links to plain text', () {
      final summary = summarizeReleaseNotes(
        '## [1.0.0-alpha.13](https://x.test) (2026-10-20)\n\n'
        '### Features\n\n'
        '* **updates:** tell the player ([#130](https://x.test/130))\n'
        '- keep `Fifty` honest\n'
        '<!-- hidden -->',
      );
      expect(
        summary,
        '1.0.0-alpha.13 (2026-10-20) Features updates: tell the player '
        '(#130) keep Fifty honest',
      );
    });

    test('trims to the limit at a word boundary with an ellipsis', () {
      final long = List.filled(100, 'word').join(' ');
      final summary = summarizeReleaseNotes(long, maxLength: 300);
      expect(summary.length, lessThanOrEqualTo(301));
      expect(summary.endsWith('word…'), isTrue);
    });

    test('empty notes summarize to empty', () {
      expect(summarizeReleaseNotes(''), isEmpty);
      expect(summarizeReleaseNotes('\n---\n'), isEmpty);
    });
  });

  group('AppRelease JSON', () {
    test('round-trips through the cache shape', () {
      final original = AppRelease(
        tag: 'v1.0.0-alpha.13',
        version: AppVersion.tryParse('v1.0.0-alpha.13')!,
        releaseNotesUrl: Uri.parse('https://example.test/notes'),
        downloadUrl: Uri.parse('https://example.test/app.apk'),
        notes: 'Notes',
        publishedAt: DateTime.utc(2026, 10, 20),
      );
      final restored = AppRelease.fromJson(original.toJson())!;
      expect(restored.tag, original.tag);
      expect(restored.version, original.version);
      expect(restored.releaseNotesUrl, original.releaseNotesUrl);
      expect(restored.downloadUrl, original.downloadUrl);
      expect(restored.notes, 'Notes');
      expect(restored.publishedAt, original.publishedAt);
    });

    test('rejects a malformed cache entry', () {
      expect(AppRelease.fromJson(null), isNull);
      expect(AppRelease.fromJson({'tag': 'nightly'}), isNull);
    });
  });
}
