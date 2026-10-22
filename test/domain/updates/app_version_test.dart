import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/updates/app_version.dart';

void main() {
  AppVersion v(String source) => AppVersion.tryParse(source)!;

  group('AppVersion.tryParse', () {
    test('reads core, pre-release, and tolerates a leading v', () {
      final version = v('v1.0.0-alpha.12');
      expect(version.major, 1);
      expect(version.minor, 0);
      expect(version.patch, 0);
      expect(version.preRelease, ['alpha', '12']);
      expect(version.toString(), '1.0.0-alpha.12');
    });

    test('ignores build metadata', () {
      expect(v('1.0.0-alpha.1+1'), v('1.0.0-alpha.1'));
      expect(v('2.3.4+build.7').toString(), '2.3.4');
    });

    test('rejects what is not a version', () {
      for (final source in [
        null,
        '',
        'nightly',
        '1.0',
        '1.0.0.0',
        '1.0.0-',
        '1.0.0-alpha..1',
        'version 1.0.0',
      ]) {
        expect(AppVersion.tryParse(source), isNull, reason: '$source');
      }
    });
  });

  group('AppVersion ordering', () {
    test('the spec chain holds in order', () {
      final chain = [
        '1.0.0-alpha.9',
        '1.0.0-alpha.12',
        '1.0.0-beta.1',
        '1.0.0',
      ].map(v).toList();
      for (var i = 0; i < chain.length - 1; i++) {
        expect(
          chain[i + 1].isNewerThan(chain[i]),
          isTrue,
          reason: '${chain[i + 1]} > ${chain[i]}',
        );
        expect(chain[i].isNewerThan(chain[i + 1]), isFalse);
      }
    });

    test('numeric pre-release segments compare numerically', () {
      expect(v('1.0.0-alpha.12').compareTo(v('1.0.0-alpha.9')), 1);
      expect(v('1.0.0-alpha.100').compareTo(v('1.0.0-alpha.99')), 1);
    });

    test('a final release beats any pre-release of the same core', () {
      expect(v('1.0.0').isNewerThan(v('1.0.0-rc.99')), isTrue);
      expect(v('1.0.0-rc.1').isNewerThan(v('1.0.0')), isFalse);
    });

    test('the core outranks the pre-release', () {
      expect(v('1.0.1-alpha.1').isNewerThan(v('1.0.0')), isTrue);
      expect(v('2.0.0-alpha.1').isNewerThan(v('1.9.9')), isTrue);
      expect(v('1.10.0').isNewerThan(v('1.9.0')), isTrue);
    });

    test('numeric identifiers sort below textual, prefix below longer', () {
      expect(v('1.0.0-alpha.beta').isNewerThan(v('1.0.0-alpha.1')), isTrue);
      expect(v('1.0.0-alpha.1').isNewerThan(v('1.0.0-alpha')), isTrue);
    });

    test('equal versions are equal, with or without v', () {
      expect(v('v1.0.0-alpha.12'), v('1.0.0-alpha.12'));
      expect(v('v1.0.0-alpha.12').compareTo(v('1.0.0-alpha.12')), 0);
    });
  });
}
