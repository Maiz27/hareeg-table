import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/ui/features/learning/models/practice_catalog.dart';

void main() {
  group('PracticeCatalog', () {
    test('lesson ids are unique', () {
      // Ids double as persistence keys and scenario-lookup keys; a duplicate
      // would silently share progress between two lessons.
      final ids = PracticeCatalog.lessonIds;
      expect(ids.toSet().length, ids.length);
    });

    test('every lesson belongs to exactly one pack listing', () {
      final fromPacks = [
        for (final pack in PracticePackId.values)
          ...PracticeCatalog.lessonsIn(pack).map((lesson) => lesson.id),
      ];
      expect(fromPacks, unorderedEquals(PracticeCatalog.lessonIds));
    });

    test('byId resolves every catalog lesson and rejects unknown ids', () {
      for (final id in PracticeCatalog.lessonIds) {
        expect(PracticeCatalog.byId(id)?.id, id);
      }
      expect(PracticeCatalog.byId('unknown-lesson'), isNull);
    });
  });
}
