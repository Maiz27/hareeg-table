import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/lounge_tokens.dart';

/// Size class of the table chrome, read from the width of the playing surface.
///
/// One definition for every surface that sets a [TableHudCapsule] on the
/// table — the live and practice tables, the branch sandbox and the replay
/// viewer — so the capsule is the same object wherever it appears.
@immutable
class TableHudMetrics {
  const TableHudMetrics._({
    required this.buttonSize,
    required this.iconSize,
    required this.edgeInset,
  });

  /// Metrics for a playing surface [viewportWidth] wide.
  ///
  /// [floor] raises every segment to a minimum target. The live and practice
  /// tables pass none and keep the corner geometry earlier sprints accepted;
  /// the sandbox and the replay viewer floor at 44 dp.
  factory TableHudMetrics.forViewport(
    double viewportWidth, {
    double floor = 0,
  }) {
    final isLarge = viewportWidth >= 900;
    final isTablet = viewportWidth >= 720;
    return TableHudMetrics._(
      buttonSize: math.max(
        floor,
        isLarge
            ? 44.0
            : isTablet
            ? 38.0
            : 30.0,
      ),
      iconSize: isLarge
          ? 20.0
          : isTablet
          ? 18.0
          : 16.0,
      // The chrome sits on the playing surface inside the rail, so it needs
      // only a hairline of breathing room.
      edgeInset: isLarge
          ? 10.0
          : isTablet
          ? 8.0
          : 6.0,
    );
  }

  /// Side of each square segment.
  final double buttonSize;

  /// Glyph size inside a segment.
  final double iconSize;

  /// Gap between the capsule and the playing surface's edge.
  final double edgeInset;

  /// The capsule's horizontal padding, per side.
  static const double capsulePadding = 4;

  /// Width of the hairline between two segments.
  static const double dividerWidth = 1;

  /// Width of a capsule holding [segments] segments.
  double capsuleWidth(int segments) =>
      segments * buttonSize +
      (segments - 1) * dividerWidth +
      capsulePadding * 2;
}

/// Softly-rounded chrome button used for the shortcuts in the table's HUD
/// capsule. Matches the open-need pill's surface treatment (charcoal fill,
/// hairline border, soft shadow) so the corner controls read as part of the
/// same chrome family across every table theme rather than floating dark
/// blobs.
class TableChromeButton extends StatelessWidget {
  /// Creates a capsule segment.
  const TableChromeButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    required this.diameter,
    required this.iconSize,
    this.semanticsLabel,
    this.toggled,
    this.emphasized = false,
    super.key,
  });

  /// Tooltip shown on long press / hover.
  final String tooltip;

  /// The glyph.
  final IconData icon;

  /// Null disables the segment; it stays visible, quietened.
  final VoidCallback? onPressed;

  /// Side of the square target.
  final double diameter;

  /// Glyph size.
  final double iconSize;

  /// Explicit accessible name, when the icon alone is not enough.
  ///
  /// Opt-in rather than defaulted from [tooltip]: the corner chrome the live
  /// and practice tables ship is unchanged by it, and giving every one of
  /// those buttons a new label would be a change to surfaces nobody asked to
  /// touch.
  final String? semanticsLabel;

  /// Whether the segment is a switch, and if so whether it is on. Null for a
  /// plain action. A toggled-on segment lights gold.
  final bool? toggled;

  /// Lights the glyph gold: the segment leads off the surface rather than
  /// adjusting it.
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final label = semanticsLabel;
    final enabled = onPressed != null;
    final lit = emphasized || (toggled ?? false);
    final color = !enabled
        ? LoungeTokens.sandLine.withValues(alpha: 0.32)
        : lit
        ? LoungeTokens.goldAccent
        : LoungeTokens.sandLine;
    // The label wraps the tooltip rather than sitting inside it: `Tooltip`
    // publishes its own semantics node, so a label added underneath would
    // arrive as a *second* node and the outer one — the one a hit test and
    // `getSemantics` land on — would still be an unnamed button.
    return _MaybeLabelled(
      label: label,
      enabled: enabled,
      toggled: toggled,
      child: Tooltip(
        message: tooltip,
        // Excluded from semantics only where an explicit label exists: web
        // renders a node's label and tooltip both as text, so a control
        // carrying both says its name twice. Where there is no label the
        // tooltip IS the name, and it stays in the tree.
        excludeFromSemantics: label != null,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onPressed,
            child: SizedBox.square(
              dimension: diameter,
              child: toggled ?? false
                  // A switched-on segment sits in a lit well, so "on" is
                  // read from shape as well as from colour.
                  ? Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: LoungeTokens.goldAccent.withValues(
                            alpha: 0.16,
                          ),
                          border: Border.all(
                            color: LoungeTokens.goldAccent.withValues(
                              alpha: 0.55,
                            ),
                          ),
                        ),
                        child: SizedBox.square(
                          dimension: diameter - 8,
                          child: Icon(icon, color: color, size: iconSize),
                        ),
                      ),
                    )
                  : Icon(icon, color: color, size: iconSize),
            ),
          ),
        ),
      ),
    );
  }
}

/// The table's control capsule: lacquered charcoal with a brass edge, its
/// segments split by hairlines.
class TableHudCapsule extends StatelessWidget {
  /// Creates a capsule around [children].
  const TableHudCapsule({required this.children, super.key});

  /// The segments, in reading order.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xF2241A12), Color(0xF2140F0B)],
        ),
        borderRadius: BorderRadius.circular(LoungeTokens.radiusPill),
        border: Border.all(
          color: LoungeTokens.sandLine.withValues(alpha: 0.32),
        ),
        boxShadow: LoungeTokens.elevationL2,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TableHudMetrics.capsulePadding,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Container(
                  width: TableHudMetrics.dividerWidth,
                  height: 14,
                  color: LoungeTokens.sandLine.withValues(alpha: 0.22),
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// Names a control for assistive technology, or leaves it alone.
class _MaybeLabelled extends StatelessWidget {
  const _MaybeLabelled({
    required this.child,
    required this.enabled,
    this.label,
    this.toggled,
  });

  final Widget child;
  final String? label;
  final bool enabled;
  final bool? toggled;

  @override
  Widget build(BuildContext context) {
    final label = this.label;
    if (label == null) {
      return child;
    }
    // Merged, so the button role and the name arrive as one node rather than
    // as a named box containing an anonymous button. The role is restated
    // here rather than inherited from the `InkWell` underneath, because the
    // outer node is the one a hit test and a screen reader land on.
    return MergeSemantics(
      child: Semantics(
        label: label,
        button: true,
        enabled: enabled,
        toggled: toggled,
        child: child,
      ),
    );
  }
}
