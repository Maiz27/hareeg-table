import 'package:flutter/material.dart';

import '../theme/lounge_tokens.dart';

/// Finish of a [LoungeMedallion].
enum LoungeMedallionTone {
  /// Lacquered charcoal with a sand ring: the resting state.
  lacquer,

  /// Lacquered charcoal with a gold ring and glow: active or celebrated.
  lit,

  /// Solid gold face: an achievement (a win, a completed lesson).
  gold,

  /// Lacquered charcoal with a warm red ring: something went wrong.
  alert,
}

/// The lounge's round badge (design contract section 8): an icon or short
/// label on a lacquered disc, lit from the top-start corner like the table.
class LoungeMedallion extends StatelessWidget {
  /// Creates a medallion with an [icon].
  const LoungeMedallion({
    super.key,
    required IconData this.icon,
    this.size = 44,
    this.tone = LoungeMedallionTone.lacquer,
  }) : label = null;

  /// Creates a medallion with a short text [label] (a number, a rank).
  const LoungeMedallion.label({
    super.key,
    required String this.label,
    this.size = 44,
    this.tone = LoungeMedallionTone.lacquer,
  }) : icon = null;

  /// Icon on the medallion.
  final IconData? icon;

  /// Text on the medallion.
  final String? label;

  /// Diameter.
  final double size;

  /// Finish.
  final LoungeMedallionTone tone;

  @override
  Widget build(BuildContext context) {
    final gold = tone == LoungeMedallionTone.gold;
    final ring = switch (tone) {
      LoungeMedallionTone.lacquer => LoungeTokens.sandLine.withValues(
        alpha: 0.4,
      ),
      LoungeMedallionTone.lit ||
      LoungeMedallionTone.gold => LoungeTokens.goldAccent,
      LoungeMedallionTone.alert => LoungeTokens.invalidAction,
    };
    final ink = switch (tone) {
      LoungeMedallionTone.gold => LoungeTokens.coffeeCharcoal,
      LoungeMedallionTone.alert => LoungeTokens.invalidAction,
      _ => LoungeTokens.goldAccent,
    };
    final glow = switch (tone) {
      LoungeMedallionTone.lacquer => null,
      LoungeMedallionTone.alert => LoungeTokens.invalidAction,
      _ => LoungeTokens.goldAccent,
    };
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: gold
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE8B95A), LoungeTokens.goldAccent],
              )
            : const RadialGradient(
                center: Alignment(-0.3, -0.45),
                colors: [Color(0xFF3A2A1C), LoungeTokens.coffeeCharcoal],
              ),
        border: Border.all(color: ring, width: size >= 40 ? 1.6 : 1.2),
        boxShadow: [
          if (glow != null)
            BoxShadow(
              color: glow.withValues(alpha: 0.35),
              blurRadius: size * 0.35,
            ),
        ],
      ),
      child: icon != null
          ? Icon(icon, size: size * 0.48, color: ink)
          : Text(
              label!,
              style: LoungeTokens.numericDisplay.copyWith(
                fontSize: size * 0.4,
                color: gold
                    ? LoungeTokens.coffeeCharcoal
                    : LoungeTokens.sandLine,
              ),
            ),
    );
  }
}

/// Decoration for a lounge panel lit by a warm pool of light from its
/// top-start corner, tinted by [glow] (gold by default).
BoxDecoration loungeLitPanel({
  Color glow = LoungeTokens.goldAccent,
  double strength = 0.14,
  Color? edge,
  double radius = LoungeTokens.radiusPanel,
}) {
  return BoxDecoration(
    gradient: RadialGradient(
      center: const Alignment(-0.7, -1.1),
      radius: 1.4,
      colors: [
        Color.lerp(
          LoungeTokens.coffeeCharcoal,
          glow,
          strength,
        )!.withValues(alpha: 0.98),
        LoungeTokens.coffeeCharcoal.withValues(alpha: 0.97),
      ],
    ),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: edge ?? glow.withValues(alpha: 0.45), width: 1.2),
    boxShadow: LoungeTokens.elevationL3,
  );
}
