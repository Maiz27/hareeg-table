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
      padding: const EdgeInsets.all(LoungeTokens.space3),
      decoration: BoxDecoration(
        color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(LoungeTokens.radiusCard),
        border: Border.all(
          color: LoungeTokens.sandLine.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: LoungeTokens.bodyMuted.copyWith(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: LoungeTokens.space1),
          Text(
            value,
            style: const TextStyle(
              color: LoungeTokens.offWhiteText,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.1,
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
