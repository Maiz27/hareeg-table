import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/ui/core/cards/card_theme_registry.dart';

void main() {
  test('Sandline Lounge is the default selectable card theme', () {
    expect(CardThemeRegistry.defaultThemeId, 'sandline_lounge');
    expect(CardThemeRegistry.byId(null).id, 'sandline_lounge');
    expect(CardThemeRegistry.all().first.id, 'sandline_lounge');
  });

  test('Iron Rose is the second selectable official card theme', () {
    expect(CardThemeRegistry.all().take(2).map((theme) => theme.id), [
      'sandline_lounge',
      'iron_rose',
    ]);
  });

  test('High Contrast is not a selectable card theme', () {
    expect(
      CardThemeRegistry.all().map((theme) => theme.id),
      isNot(contains('high_contrast')),
    );
  });
}
