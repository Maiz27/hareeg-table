part of 'game_table_screen.dart';

// Table chrome: the feedback chip, the animated overlay slot, and the web
// zoom-to-fill wrapper. The HUD capsule and its buttons are shared with the
// replay viewer and live in `widgets/table_hud_capsule.dart`.

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
