import 'package:flutter/material.dart';

import '../../../../l10n/app_strings.dart';
import '../../../core/motion/motion_speed.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../coach/coach_hint.dart';

/// Renders the active coaching [CoachHint] over the table.
///
/// Two presentations, both anchored to the hint's zone rather than to a
/// specific card (the coach highlight ring does the precise pointing):
///
/// - [CoachIntensity.quiet]: a compact callout docked in the relevant zone
///   (above the hand, or below the chrome for discard hints).
/// - [CoachIntensity.popIn]: an urgent finish/Fifty banner that scales into
///   the top of the table. Finish uses gold, Fifty uses the reserved flame.
///
/// The overlay is entirely pointer-transparent ([IgnorePointer]): the coach
/// must never intercept a tap, drag, or long-press meant for the table, so it
/// purely decorates. Hints clear on their own when the situation changes (the
/// player acts, the turn passes) or when the "Coaching tips" toggle is off.
/// Place it as a direct child of the table body [Stack].
class CoachOverlay extends StatelessWidget {
  /// Creates a coach overlay.
  const CoachOverlay({
    super.key,
    required this.hint,
    required this.highContrast,
    this.stageHint,
  });

  /// Hint to present.
  final CoachHint hint;

  /// Optional once-per-round stage note rendered as a compact second row
  /// under the primary hint (game-stage teaching: thin stock, score
  /// pressure, an opponent nearly done). Suppressed during urgent pop-ins so
  /// the win/Fifty moment stays clean.
  final CoachHint? stageHint;

  /// Whether high-contrast card cues are enabled (strengthens the panel).
  final bool highContrast;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final motion = MotionScope.of(context);
    final accent = _accentColor(hint.accent);
    final isPopIn = hint.intensity == CoachIntensity.popIn;
    final note = isPopIn ? null : stageHint;

    final callout = _CoachCallout(
      hint: hint,
      stageHint: note,
      strings: strings,
      accent: accent,
      highContrast: highContrast,
    );

    // Re-run the entrance whenever the situation (situationKey) changes.
    final animated = TweenAnimationBuilder<double>(
      key: ValueKey(
        'coach-anim-${hint.situationKey}#${note?.situationKey ?? ''}',
      ),
      tween: Tween(begin: 0, end: 1),
      duration: motion.scale(const Duration(milliseconds: 180)),
      curve: motion.curve(Curves.easeOutCubic),
      builder: (context, t, child) {
        final dy = isPopIn ? (1 - t) * -10.0 : (1 - t) * 8.0;
        final scale = isPopIn ? 0.94 + 0.06 * t : 1.0;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, dy),
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
      child: callout,
    );

    return Positioned.fill(
      child: IgnorePointer(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxHeight <= 360 || constraints.maxWidth <= 700;
              // A slim full-width strip pinned to the very top, riding over the
              // north hand rail (face-down CPU cards the player never touches).
              // This is the one band clear of the central discard, the
              // table-meld lanes, and the player's hand; the coach ring on the
              // referenced cards does the precise pointing. Side insets clear
              // the top-corner score / pause buttons.
              return Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: compact ? 54 : 66,
                    right: compact ? 54 : 66,
                    top: compact ? 4 : 8,
                  ),
                  child: SizedBox(width: double.infinity, child: animated),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  static Color _accentColor(CoachAccent accent) {
    return switch (accent) {
      CoachAccent.coach => LoungeTokens.coachHighlight,
      CoachAccent.finish => LoungeTokens.goldAccent,
      CoachAccent.fifty => LoungeTokens.fiftyFlame,
    };
  }
}

class _CoachCallout extends StatelessWidget {
  const _CoachCallout({
    required this.hint,
    required this.stageHint,
    required this.strings,
    required this.accent,
    required this.highContrast,
  });

  final CoachHint hint;
  final CoachHint? stageHint;
  final AppStrings strings;
  final Color accent;
  final bool highContrast;

  @override
  Widget build(BuildContext context) {
    final isPopIn = hint.intensity == CoachIntensity.popIn;
    final panelColor = LoungeTokens.coffeeCharcoal.withValues(
      alpha: highContrast ? 0.97 : 0.92,
    );
    final note = stageHint;

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        _AccentIcon(icon: hint.icon, accent: accent, large: isPopIn),
        const SizedBox(width: LoungeTokens.space3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    strings.coachLabel.toUpperCase(),
                    style: TextStyle(
                      color: accent,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(width: LoungeTokens.space2),
                  Flexible(
                    child: Text(
                      hint.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: LoungeTokens.offWhiteText,
                        fontSize: isPopIn ? 16 : 14.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                hint.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: LoungeTokens.bodyMuted,
              ),
              if (note != null) ...[
                const SizedBox(height: 3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(
                        note.icon,
                        color: LoungeTokens.goldAccent.withValues(alpha: 0.9),
                        size: 12,
                      ),
                    ),
                    const SizedBox(width: LoungeTokens.space2),
                    Expanded(
                      child: Text(
                        note.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: LoungeTokens.bodyMuted.copyWith(
                          fontSize: 11,
                          color: LoungeTokens.goldAccent.withValues(
                            alpha: 0.92,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );

    final panel = DecoratedBox(
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
        border: Border.all(color: accent.withValues(alpha: 0.55), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: isPopIn ? 0.30 : 0.16),
            blurRadius: isPopIn ? 26 : 16,
            spreadRadius: isPopIn ? 1 : 0,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: LoungeTokens.space4,
          vertical: LoungeTokens.space2,
        ),
        child: content,
      ),
    );

    return Semantics(
      liveRegion: true,
      label: [
        '${strings.coachLabel}. ${hint.title}. ${hint.body}',
        if (note != null) '${note.title}. ${note.body}',
      ].join(' '),
      child: panel,
    );
  }
}

class _AccentIcon extends StatelessWidget {
  const _AccentIcon({
    required this.icon,
    required this.accent,
    required this.large,
  });

  final IconData icon;
  final Color accent;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final dimension = large ? 40.0 : 34.0;
    return Container(
      width: dimension,
      height: dimension,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: accent, size: large ? 22 : 18),
    );
  }
}
