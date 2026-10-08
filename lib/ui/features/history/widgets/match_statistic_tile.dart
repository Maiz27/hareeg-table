import 'package:flutter/material.dart';

import '../../../core/theme/lounge_tokens.dart';

/// One labelled statistic.
///
/// The value arrives already formatted. This widget performs no arithmetic and
/// never sees a `double`, so a raw repeating decimal cannot originate here.
class MatchStatisticTile extends StatelessWidget {
  /// Creates a statistic tile.
  const MatchStatisticTile({
    required this.label,
    required this.value,
    this.hint,
    super.key,
  });

  /// What the number means.
  final String label;

  /// The already-formatted number, or the unavailable marker.
  final String value;

  /// Optional clarification shown beneath the value.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(LoungeTokens.space4),
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-1, -1),
          radius: 1.6,
          colors: [
            Color.lerp(
              LoungeTokens.coffeeCharcoal,
              LoungeTokens.goldAccent,
              0.07,
            )!.withValues(alpha: 0.7),
            LoungeTokens.coffeeCharcoal.withValues(alpha: 0.45),
          ],
        ),
        borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
        border: Border.all(
          color: LoungeTokens.sandLine.withValues(alpha: 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: LoungeTokens.overline.copyWith(
              fontSize: 10.5,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: LoungeTokens.space2),
          Text(
            value,
            style: LoungeTokens.numericDisplay.copyWith(
              fontSize: 26,
              height: 1.05,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: LoungeTokens.space1),
            Text(
              hint!,
              style: LoungeTokens.bodyMuted.copyWith(fontSize: 11, height: 1.3),
            ),
          ],
        ],
      ),
    );
  }
}
