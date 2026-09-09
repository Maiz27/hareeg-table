import 'package:flutter/material.dart';

import '../../../core/theme/lounge_tokens.dart';
import '../replay_hud_layout.dart';

/// Marker shared by every replay HUD surface that must not dismiss the
/// analysis popover.
///
/// Transport is part of the review interaction, not "outside" it: stepping,
/// changing round and seeking all update the open card rather than closing it.
/// Giving the rails, the scrub target and the card one `TapRegion` group is
/// what makes that true without a barrier — a tap on the table is still
/// outside the group, so it both dismisses and reaches the table.
class ReplayHudTapGroup {
  /// Creates the marker.
  const ReplayHudTapGroup();
}

/// The single group id every HUD surface registers under.
const ReplayHudTapGroup replayHudTapGroup = ReplayHudTapGroup();

/// One permanent HUD affordance, sized to exactly one collision-map slot.
///
/// The horizontal corner clusters this file used to hold are withdrawn: they
/// covered opponent cards at every approved short size. What replaces them is a
/// pair of fixed 44 dp edge columns, and this is one cell of one column.
///
/// Icon-only, which makes the tooltip and semantics label load-bearing rather
/// than decorative: without them the rail is unreadable to a screen reader. It
/// is also why no localized string can widen a rail, and therefore why no
/// localized string can reach the routing metric.
/// Which way a rail glyph is allowed to point.
enum ReplayGlyphDirection {
  /// The glyph means "toward the start / end of the match". That is physical
  /// and chronological, and it does not reverse with the reading direction.
  timeline,

  /// The glyph means "back the way you came" — route navigation, which *is*
  /// locale-directional and should mirror.
  locale,
}

/// Renders a rail glyph with its direction decided by the action, not by the
/// ambient reading direction.
///
/// Material opts several of these glyphs into `matchTextDirection`, so under
/// Arabic `first_page`, `last_page`, `chevron_left` and `chevron_right` all
/// flip while `skip_previous` and `skip_next` do not. The result was a rail
/// where Next pointed backwards and Previous pointed forwards, inconsistently
/// with the two skip glyphs beside them.
///
/// Pinning the timeline glyphs to LTR is the seam: the timeline runs one way
/// whichever way the language reads, so its arrows must too.
class ReplayRailGlyph extends StatelessWidget {
  /// Creates a rail glyph.
  const ReplayRailGlyph({
    required this.icon,
    required this.direction,
    this.size = 22,
    this.color,
    super.key,
  });

  /// The glyph.
  final IconData icon;

  /// Whether this glyph follows the timeline or the locale.
  final ReplayGlyphDirection direction;

  /// Glyph size in logical pixels.
  final double size;

  /// Glyph colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final glyph = Icon(icon, size: size, color: color);
    return switch (direction) {
      ReplayGlyphDirection.locale => glyph,
      ReplayGlyphDirection.timeline => Directionality(
        textDirection: TextDirection.ltr,
        child: glyph,
      ),
    };
  }
}

class ReplayRailButton extends StatelessWidget {
  /// Creates a rail affordance.
  const ReplayRailButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.glyphDirection = ReplayGlyphDirection.timeline,
    super.key,
  });

  /// The glyph.
  final IconData icon;

  /// Localized tooltip and semantics label.
  final String label;

  /// Null disables the action; it stays visible either way.
  final VoidCallback? onPressed;

  /// Whether the glyph mirrors with the locale. Only Back does.
  final ReplayGlyphDirection glyphDirection;

  /// Inset between the 44 dp target and the visible chrome, per side.
  ///
  /// The target is what the collision map cleared and what a finger has to
  /// find; the chrome is what the eye reads. Insetting only the chrome gives
  /// the rail visible separation without moving a single accepted rectangle.
  static const double chromeInset = 3;

  /// Side of the visible surface: the 44 dp cell less the inset either side.
  static const double chromeExtent =
      ReplayHudLayout.minTapTarget - (chromeInset * 2);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: ReplayHudLayout.minTapTarget,
      height: ReplayHudLayout.minTapTarget,
      child: Tooltip(
        message: label,
        // The tooltip alone is not enough. `Tooltip` publishes its message as
        // a semantics *tooltip*, and an icon-only button publishes a button
        // node with no label at all — so a screen reader would announce an
        // unnamed button. The explicit label is merged onto the button's own
        // node so the two are one announcement rather than two.
        child: MergeSemantics(
          child: Semantics(
            label: label,
            button: true,
            enabled: onPressed != null,
            // Transparent, and the full 44 dp: the ink and the hit test cover
            // the whole target while only the inner box is painted, so the
            // inset ring still belongs to this control and never falls
            // through to the table underneath.
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onPressed,
                borderRadius: BorderRadius.circular(10),
                child: Center(
                  child: IgnorePointer(
                    child: Container(
                      width: chromeExtent,
                      height: chromeExtent,
                      decoration: BoxDecoration(
                        color: LoungeTokens.coffeeCharcoal.withValues(
                          alpha: 0.94,
                        ),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Center(
                        child: ReplayRailGlyph(
                          icon: icon,
                          direction: glyphDirection,
                          color: onPressed == null
                              ? LoungeTokens.sandLine.withValues(alpha: 0.38)
                              : LoungeTokens.sandLine,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
