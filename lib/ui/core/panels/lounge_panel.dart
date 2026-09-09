import 'package:flutter/material.dart';

import '../motif/geometric_motif_painter.dart';
import '../theme/lounge_tokens.dart';

/// Shared Sudanese Lounge modal panel.
///
/// Coffee-charcoal surface with sand-line border, drop shadow, and a quiet
/// corner medallion. Used by the table's pause, score, and similar overlays
/// so every modal reads as the same product, not a stock dialog.
///
/// `highContrast` swaps the surface and border to satisfy the high-contrast
/// cards accessibility setting. `padding` defaults to symmetric `space5`;
/// overlays that need less vertical breathing room can override it.
class LoungePanel extends StatelessWidget {
  /// Creates a lounge panel.
  const LoungePanel({
    super.key,
    required this.highContrast,
    required this.child,
    this.padding = const EdgeInsets.all(LoungeTokens.space5),
  });

  /// Whether the high-contrast accessibility surface is active.
  final bool highContrast;

  /// Inner content.
  final Widget child;

  /// Inner padding around [child]. Defaults to symmetric `space5`.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: highContrast
              ? Colors.black.withValues(alpha: 0.98)
              : LoungeTokens.coffeeCharcoal.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
          border: Border.all(
            color: highContrast
                ? const Color(0xFFFFD400)
                : LoungeTokens.sandLine.withValues(alpha: 0.32),
            width: highContrast ? 2 : 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 28,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
          child: Stack(
            children: [
              // Quiet corner medallion echoes the home menu backdrop so the
              // panel reads as the same product, not a stock dialog.
              Positioned(
                top: -34,
                right: -42,
                child: IgnorePointer(
                  child: SizedBox.square(
                    dimension: 168,
                    child: CustomPaint(
                      painter: const GeometricMotifPainter(
                        variant: LoungeMotifVariant.medallion,
                        opacity: 0.05,
                        strokeWidth: 1.0,
                        density: 4,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(padding: padding, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// Standard header row for a [LoungePanel] — gold-accented badge, title +
/// subtitle, and a close button.
class LoungePanelHeader extends StatelessWidget {
  /// Creates a lounge panel header.
  const LoungePanelHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onClose,
    required this.closeTooltip,
  }) : assert(
         onClose == null || closeTooltip != null,
         'a close button must be named',
       );

  /// Icon shown in the leading badge.
  final IconData icon;

  /// Panel title (display style).
  final String title;

  /// Panel subtitle (muted body style).
  final String subtitle;

  /// Invoked when the close button is tapped, or null for no close button.
  ///
  /// Null is not "a disabled close": the button is not built at all. A panel
  /// whose contract is an exhaustive list of actions cannot carry a fourth one
  /// that merely repeats one of them.
  final VoidCallback? onClose;

  /// Tooltip for the close button. Required whenever [onClose] is non-null.
  final String? closeTooltip;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeaderBadge(icon: icon),
        const SizedBox(width: LoungeTokens.space4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: LoungeTokens.display.copyWith(fontSize: 22)),
              const SizedBox(height: 4),
              Text(subtitle, style: LoungeTokens.bodyMuted),
            ],
          ),
        ),
        if (onClose != null)
          // Named once. An icon-only `IconButton` publishes a button node
          // with a tooltip and no label, so a screen reader announces an
          // unnamed button; the name is put on the node instead, and the
          // tooltip is excluded from semantics so web does not render it as a
          // second copy of that name.
          Tooltip(
            message: closeTooltip!,
            excludeFromSemantics: true,
            child: MergeSemantics(
              child: Semantics(
                label: closeTooltip,
                button: true,
                enabled: true,
                child: IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                  color: LoungeTokens.mutedText,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _HeaderBadge extends StatelessWidget {
  const _HeaderBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: LoungeTokens.feltRaised,
        borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
        border: Border.all(color: LoungeTokens.sandLine.withValues(alpha: 0.4)),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: LoungeTokens.goldAccent, size: 22),
    );
  }
}

/// Visual tone for a [LoungePanelAction].
enum LoungePanelActionTone {
  /// Gold filled button — primary affordance.
  primary,

  /// Sand outlined button — neutral secondary affordance.
  neutral,

  /// Deep-red outlined button — destructive secondary affordance.
  danger,
}

/// Declarative description of a single panel action.
class LoungePanelAction {
  /// Creates a lounge panel action descriptor.
  const LoungePanelAction({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.tone,
    this.tooltip,
  });

  /// Leading icon.
  final IconData icon;

  /// Button label.
  final String label;

  /// Localized tooltip, or null to publish none.
  ///
  /// Optional so every existing panel is untouched. It is a **pointer**
  /// affordance: the button already publishes its name to assistive tech, and
  /// the tooltip is deliberately excluded from semantics so the name is
  /// announced once rather than twice.
  final String? tooltip;

  /// Tap handler.
  final VoidCallback onTap;

  /// Visual tone — primary, neutral, or danger.
  final LoungePanelActionTone tone;
}

/// Standard two-button action row for a [LoungePanel].
///
/// The [primary] action renders as a gold filled button and the [secondary]
/// action as an outlined button tinted by its tone (sand for neutral, deep
/// red for danger). When [tertiary] is supplied, it renders as a full-width
/// outlined action above the standard two-button row.
class LoungePanelActions extends StatelessWidget {
  /// Creates a lounge panel actions row.
  const LoungePanelActions({
    super.key,
    required this.primary,
    required this.secondary,
    this.tertiary,
  });

  /// Primary (filled) action.
  final LoungePanelAction primary;

  /// Secondary (outlined) action.
  final LoungePanelAction secondary;

  /// Optional tertiary action.
  final LoungePanelAction? tertiary;

  @override
  Widget build(BuildContext context) {
    final actionRow = Row(
      children: [
        Expanded(child: _buildAction(primary, isPrimary: true)),
        const SizedBox(width: LoungeTokens.space3),
        Expanded(child: _buildAction(secondary, isPrimary: false)),
      ],
    );
    final tertiaryAction = tertiary;
    if (tertiaryAction == null) {
      return actionRow;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildAction(tertiaryAction, isPrimary: false),
        const SizedBox(height: LoungeTokens.space3),
        actionRow,
      ],
    );
  }

  Widget _buildAction(LoungePanelAction action, {required bool isPrimary}) {
    final button = _buildButton(action, isPrimary: isPrimary);
    final tooltip = action.tooltip;
    if (tooltip == null) return button;
    // The tooltip is a pointer affordance and is deliberately kept OUT of the
    // semantics: the button's own node already carries the name, and Flutter
    // web renders a node's label and its tooltip both as text, so a node
    // carrying both makes a screen reader say the name twice. That is the
    // defect round 1 reproduced on the docked branch control. The visible
    // tooltip is unchanged.
    return Tooltip(message: tooltip, excludeFromSemantics: true, child: button);
  }

  Widget _buildButton(LoungePanelAction action, {required bool isPrimary}) {
    if (isPrimary) {
      return FilledButton.icon(
        onPressed: action.onTap,
        style: FilledButton.styleFrom(
          backgroundColor: LoungeTokens.goldAccent,
          foregroundColor: LoungeTokens.coffeeCharcoal,
          padding: const EdgeInsets.symmetric(
            horizontal: LoungeTokens.space4,
            vertical: LoungeTokens.space3,
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
          ),
        ),
        icon: Icon(action.icon, size: 20),
        label: Text(action.label),
      );
    }
    final isDanger = action.tone == LoungePanelActionTone.danger;
    final accent = isDanger ? LoungeTokens.deepRed : LoungeTokens.sandLine;
    return OutlinedButton.icon(
      onPressed: action.onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: LoungeTokens.offWhiteText,
        side: BorderSide(color: accent.withValues(alpha: 0.55)),
        padding: const EdgeInsets.symmetric(
          horizontal: LoungeTokens.space4,
          vertical: LoungeTokens.space3,
        ),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
        ),
      ),
      icon: Icon(action.icon, size: 20, color: accent),
      label: Text(action.label),
    );
  }
}
