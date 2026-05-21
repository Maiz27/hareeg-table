import 'package:flutter/material.dart';

import '../theme/lounge_tokens.dart';

/// Brand artwork used where the app needs a compact identity mark.
abstract final class AppBrandAssets {
  /// Production launcher-icon composite.
  static const launcherIcon =
      'assets/brand/launcher/sandline_joker_composite.png';
}

/// Compact app icon mark for menu, help, and about surfaces.
class AppBrandMark extends StatelessWidget {
  /// Creates an app brand mark.
  const AppBrandMark({super.key, this.size = 50, this.semanticLabel});

  /// Square size in logical pixels.
  final double size;

  /// Optional image semantic label.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.24);
    return Semantics(
      image: true,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: LoungeTokens.goldAccent.withValues(alpha: 0.34),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.24),
              blurRadius: size * 0.22,
              offset: Offset(0, size * 0.08),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Image.asset(
            AppBrandAssets.launcherIcon,
            width: size,
            height: size,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            excludeFromSemantics: true,
          ),
        ),
      ),
    );
  }
}
