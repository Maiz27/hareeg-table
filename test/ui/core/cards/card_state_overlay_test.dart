import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/ui/core/cards/card_state.dart';

void main() {
  test('high contrast resolves stronger overlays without replacing normal', () {
    final normal = DefaultCardStateOverlays.map[CardVisualState.normal]!;

    expect(
      HighContrastCardStateOverlays.resolve(CardVisualState.normal, normal),
      same(normal),
    );
    expect(
      HighContrastCardStateOverlays.resolve(
        CardVisualState.selected,
        DefaultCardStateOverlays.map[CardVisualState.selected]!,
      ).outline,
      const Color(0xFFFFD400),
    );
    expect(
      HighContrastCardStateOverlays.resolve(
        CardVisualState.coverTarget,
        DefaultCardStateOverlays.map[CardVisualState.coverTarget]!,
      ).outlineWidth,
      greaterThan(
        DefaultCardStateOverlays.map[CardVisualState.coverTarget]!.outlineWidth,
      ),
    );
  });
}
