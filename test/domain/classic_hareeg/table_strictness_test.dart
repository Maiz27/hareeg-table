import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/table_strictness.dart';

void main() {
  group('TableStrictness', () {
    test('has four tiers in expected order', () {
      expect(TableStrictness.values, [
        TableStrictness.coaching,
        TableStrictness.standard,
        TableStrictness.strict,
        TableStrictness.table,
      ]);
    });

    test('each tier exposes a non-empty label and description', () {
      for (final tier in TableStrictness.values) {
        expect(tier.label, isNotEmpty);
        expect(tier.description, isNotEmpty);
      }
    });

    group('fromName', () {
      test('parses known enum names', () {
        expect(TableStrictness.fromName('coaching'), TableStrictness.coaching);
        expect(TableStrictness.fromName('standard'), TableStrictness.standard);
        expect(TableStrictness.fromName('strict'), TableStrictness.strict);
        expect(TableStrictness.fromName('table'), TableStrictness.table);
      });

      test('falls back to coaching for null input', () {
        expect(TableStrictness.fromName(null), TableStrictness.coaching);
      });

      test('falls back to coaching for unknown names', () {
        expect(TableStrictness.fromName(''), TableStrictness.coaching);
        expect(
          TableStrictness.fromName('hardTable17'),
          TableStrictness.coaching,
        );
        expect(TableStrictness.fromName('???'), TableStrictness.coaching);
      });

      test('round-trips through enum name serialization', () {
        for (final tier in TableStrictness.values) {
          expect(TableStrictness.fromName(tier.name), tier);
        }
      });
    });
  });
}
