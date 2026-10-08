part of 'game_table_screen.dart';

// Table chrome: the HUD capsule and its buttons, the feedback chip, the
// animated overlay slot, and the web zoom-to-fill wrapper.

/// Softly-rounded chrome button used for the score / pause shortcuts in the
/// table's top corners. Matches the open-need pill's surface treatment
/// (charcoal fill, hairline border, soft shadow) so the corner controls read
/// as part of the same chrome family across every table theme rather than
/// floating dark blobs.
class _TableChromeButton extends StatelessWidget {
  const _TableChromeButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    required this.diameter,
    required this.iconSize,
    this.semanticsLabel,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final double diameter;
  final double iconSize;

  /// Explicit accessible name, when the icon alone is not enough.
  ///
  /// Opt-in rather than defaulted from [tooltip]: the corner chrome the live
  /// and practice tables ship is unchanged by this sprint, and giving every
  /// one of those buttons a new label would be a change to surfaces nobody
  /// asked me to touch.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final label = semanticsLabel;
    // The label wraps the tooltip rather than sitting inside it: `Tooltip`
    // publishes its own semantics node, so a label added underneath would
    // arrive as a *second* node and the outer one — the one a hit test and
    // `getSemantics` land on — would still be an unnamed button.
    return _MaybeLabelled(
      label: label,
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
              child: Icon(icon, color: LoungeTokens.sandLine, size: iconSize),
            ),
          ),
        ),
      ),
    );
  }
}

/// The table's control capsule: lacquered charcoal with a brass edge, its
/// segments split by hairlines.
class _TableHudCapsule extends StatelessWidget {
  const _TableHudCapsule({required this.children});

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
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Container(
                  width: 1,
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
  const _MaybeLabelled({required this.child, this.label});

  final Widget child;
  final String? label;

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
      child: Semantics(label: label, button: true, enabled: true, child: child),
    );
  }
}

class _AnimatedOverlaySlot extends StatelessWidget {
  const _AnimatedOverlaySlot({
    required this.visible,
    required this.overlayKey,
    required this.duration,
    required this.child,
  });

  final bool visible;
  final String overlayKey;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AnimatedSwitcher(
        duration: duration,
        reverseDuration: duration,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
              child: child,
            ),
          );
        },
        child: visible
            ? KeyedSubtree(key: ValueKey(overlayKey), child: child)
            : const SizedBox.shrink(key: ValueKey('overlay-empty')),
      ),
    );
  }
}

/// Web-only "zoom to fill" for the live table.
///
/// The table layout is tuned in logical pixels for a phone held in landscape,
/// with hardcoded card sizes (see [PhysicalTablePlayfield]). On a large desktop
/// browser those phone-sized cards leave the cards tiny and the felt mostly
/// empty, and the 256px card art gets over-shrunk into an aliased blur. Here we
/// render the whole table at a fixed reference height and scale it up to the
/// viewport, so desktop becomes a clean zoomed-in version of the phone layout:
/// bigger, sharper cards with the felt filling the window.
///
/// Everything that uses table geometry — the playfield, the card/meld flight
/// overlays, the opening-deal overlay, the felt — lives inside [child] in one
/// coordinate space, so flights stay aligned and pointer events transform back
/// through the [FittedBox] automatically. Native builds keep their validated
/// per-device layout untouched.
class _ZoomToFillTable extends StatelessWidget {
  const _ZoomToFillTable({required this.child});

  final Widget child;

  /// Reference table height the layout is scaled from. Comfortably above the
  /// `compact` cutoff (360) so the desktop table always renders at regular size.
  static const _designHeight = 430.0;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return child;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final width = constraints.maxWidth;
        if (!height.isFinite || !width.isFinite || height <= 0 || width <= 0) {
          return child;
        }
        // Match the design canvas aspect to the viewport so BoxFit.fill scales
        // uniformly (no distortion) and the felt fills edge to edge with no
        // letterbox bands.
        final designWidth = width * _designHeight / height;
        // BoxFit.fill maps the design height onto the viewport height, so this
        // is the uniform scale every card is painted at. Drag feedback rides
        // the root overlay (outside this FittedBox) and reads it via
        // [TableViewScale] to size itself to match.
        final scale = height / _designHeight;
        return FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: designWidth,
            height: _designHeight,
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(size: Size(designWidth, _designHeight)),
              child: TableViewScale(scale: scale, child: child),
            ),
          ),
        );
      },
    );
  }
}

class _FeedbackChip extends StatelessWidget {
  const _FeedbackChip({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? LoungeTokens.deepRed : LoungeTokens.goldAccent;
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.symmetric(
        horizontal: LoungeTokens.space3,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              message,
              style: LoungeTokens.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
