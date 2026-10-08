import 'package:flutter/material.dart';

import '../../core/motif/geometric_motif_painter.dart';

/// The felt decoration behind the menu-side screens: a faint medallion
/// hanging off the top-right corner and, optionally, a geometric border strip
/// just above the bottom edge.
///
/// Each screen tunes where its medallion sits; everything else is shared.
class MedallionBackdrop extends StatelessWidget {
  /// Creates a backdrop with the medallion's top-right corner at
  /// ([top], [right]).
  const MedallionBackdrop({
    super.key,
    required this.top,
    required this.right,
    required this.opacity,
    required this.size,
    this.borderStrip = true,
  });

  /// Medallion offset from the top edge.
  final double top;

  /// Medallion offset from the right edge.
  final double right;

  /// Medallion stroke opacity.
  final double opacity;

  /// Medallion side length.
  final double size;

  /// Whether the geometric border strip runs along the bottom.
  final bool borderStrip;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: top,
          right: right,
          child: LoungeMotif(
            variant: LoungeMotifVariant.medallion,
            opacity: opacity,
            strokeWidth: 1.0,
            density: 4,
            size: Size.square(size),
          ),
        ),
        if (borderStrip)
          const Positioned(
            left: 0,
            right: 0,
            bottom: 18,
            child: SizedBox(
              height: 30,
              child: CustomPaint(
                painter: GeometricMotifPainter(
                  variant: LoungeMotifVariant.border,
                  opacity: 0.08,
                  strokeWidth: 1.0,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
