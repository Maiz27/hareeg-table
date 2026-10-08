import 'package:flutter/material.dart';

import '../../../core/theme/lounge_tokens.dart';

/// Icon-and-label pill stating one fact about a theme or bundled asset.
class MetaPill extends StatelessWidget {
  /// Creates a pill.
  const MetaPill({super.key, required this.icon, required this.label});

  /// Leading icon.
  final IconData icon;

  /// Pill text.
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: LoungeTokens.sandLine.withValues(alpha: 0.22),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: LoungeTokens.space2,
          vertical: LoungeTokens.space1,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: LoungeTokens.goldAccent),
            const SizedBox(width: LoungeTokens.space1),
            Text(label, style: LoungeTokens.bodyMuted),
          ],
        ),
      ),
    );
  }
}
