import 'package:flutter/material.dart';

import '../../../core/theme/lounge_tokens.dart';

/// One collapsible settings section: a card on the felt with an icon
/// medallion, a title, a description and, while closed, preview pills of the
/// current values.
class SettingsAccordionSection extends StatelessWidget {
  /// Creates a settings section.
  const SettingsAccordionSection({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.preview,
    required this.expanded,
    required this.onToggle,
    required this.child,
    this.isLast = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final List<String> preview;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    // Each section is a card on the felt (design contract 8, option card):
    // an icon medallion, a raised surface, and a gold edge with warm light
    // while it is open.
    return AnimatedContainer(
      duration: LoungeTokens.motionStandard,
      curve: Curves.easeOutCubic,
      margin: EdgeInsets.only(bottom: isLast ? 0 : LoungeTokens.space3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: expanded
              ? [
                  Color.lerp(
                    LoungeTokens.coffeeCharcoal,
                    LoungeTokens.goldAccent,
                    0.08,
                  )!.withValues(alpha: 0.85),
                  LoungeTokens.coffeeCharcoal.withValues(alpha: 0.7),
                ]
              : [
                  LoungeTokens.coffeeCharcoal.withValues(alpha: 0.5),
                  LoungeTokens.coffeeCharcoal.withValues(alpha: 0.38),
                ],
        ),
        borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
        border: Border.all(
          color: expanded
              ? LoungeTokens.goldAccent.withValues(alpha: 0.45)
              : LoungeTokens.sandLine.withValues(alpha: 0.16),
        ),
        boxShadow: expanded ? LoungeTokens.elevationL2 : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
              child: Padding(
                padding: const EdgeInsets.all(LoungeTokens.space4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _IconMedallion(icon: icon, lit: expanded),
                    const SizedBox(width: LoungeTokens.space3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: LoungeTokens.heading),
                          const SizedBox(height: 3),
                          Text(description, style: LoungeTokens.bodyMuted),
                          if (preview.isNotEmpty && !expanded) ...[
                            const SizedBox(height: LoungeTokens.space2),
                            Wrap(
                              spacing: LoungeTokens.space2,
                              runSpacing: LoungeTokens.space1,
                              children: [
                                for (final pill in preview) _PreviewPill(pill),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: LoungeTokens.space2),
                    _RotatingChevron(expanded: expanded),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: ClipRect(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                opacity: expanded ? 1 : 0,
                child: expanded
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(
                          LoungeTokens.space4,
                          0,
                          LoungeTokens.space4,
                          LoungeTokens.space5,
                        ),
                        child: child,
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A section's icon on a small lacquered medallion, warmed while open.
class _IconMedallion extends StatelessWidget {
  const _IconMedallion({required this.icon, required this.lit});

  final IconData icon;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: LoungeTokens.motionStandard,
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.3, -0.45),
          colors: [Color(0xFF3A2A1C), LoungeTokens.coffeeCharcoal],
        ),
        border: Border.all(
          color: lit
              ? LoungeTokens.goldAccent
              : LoungeTokens.sandLine.withValues(alpha: 0.35),
        ),
        boxShadow: [
          if (lit)
            BoxShadow(
              color: LoungeTokens.goldAccent.withValues(alpha: 0.3),
              blurRadius: 10,
            ),
        ],
      ),
      child: Icon(icon, color: LoungeTokens.goldAccent, size: 19),
    );
  }
}

class _PreviewPill extends StatelessWidget {
  const _PreviewPill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: LoungeTokens.sandLine.withValues(alpha: 0.22),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: LoungeTokens.space2,
          vertical: 3,
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: LoungeTokens.offWhiteText,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

class _RotatingChevron extends StatelessWidget {
  const _RotatingChevron({required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: expanded ? 0.5 : 0),
      duration: LoungeTokens.motionStandard,
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return Transform.rotate(
          angle: value * 3.141592653589793,
          child: const Icon(
            Icons.expand_more,
            color: LoungeTokens.sandLine,
            size: 22,
          ),
        );
      },
    );
  }
}
