import 'package:flutter/material.dart';

import '../../../../l10n/app_strings.dart';
import '../../../core/theme/lounge_tokens.dart';

/// Available human actions that the rail can surface.
class HumanActionAvailability {
  /// Snapshot of the actions visible/available right now.
  const HumanActionAvailability({
    required this.canDraw,
    required this.canTakeDiscard,
    required this.canClaimFifty,
    required this.canPlaceCover,
    required this.canReplaceJoker,
    required this.canReturnDiscard,
    required this.canReturnOpeningMelds,
    required this.canDiscard,
    required this.showPlaceCover,
    required this.showReplaceJoker,
    required this.showDiscard,
  });

  /// Whether the draw button should be shown.
  final bool canDraw;

  /// Whether take-discard is currently legal.
  final bool canTakeDiscard;

  /// Whether the human can claim Fifty.
  final bool canClaimFifty;

  /// Whether the player can place a cover with the current selection.
  final bool canPlaceCover;

  /// Whether the player can replace a table joker with the selection.
  final bool canReplaceJoker;

  /// Whether the return-pending-discard control is legal.
  final bool canReturnDiscard;

  /// Whether the player can take back uncommitted opening melds.
  final bool canReturnOpeningMelds;

  /// Whether the discard action is legal for the current selection.
  final bool canDiscard;

  /// Whether the cover button should be shown (visible but maybe disabled).
  final bool showPlaceCover;

  /// Whether the replace-joker button should be shown.
  final bool showReplaceJoker;

  /// Whether the discard button should be shown.
  final bool showDiscard;
}

/// Compact action rail used on the side of the table.
class ActionRail extends StatelessWidget {
  /// Creates the action rail.
  const ActionRail({
    super.key,
    required this.actions,
    required this.onDraw,
    required this.onTakeDiscard,
    required this.onClaimFifty,
    required this.onPlaceCover,
    required this.onReplaceJoker,
    required this.onReturnDiscard,
    required this.onReturnOpeningMelds,
    required this.onDiscard,
  });

  /// Action availability snapshot.
  final HumanActionAvailability actions;

  /// Action handlers — null means the button is suppressed.
  final VoidCallback? onDraw;
  final VoidCallback? onTakeDiscard;
  final VoidCallback? onClaimFifty;
  final VoidCallback? onPlaceCover;
  final VoidCallback? onReplaceJoker;
  final VoidCallback? onReturnDiscard;
  final VoidCallback? onReturnOpeningMelds;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[
      if (actions.canDraw)
        _RailButton(
          icon: Icons.style_outlined,
          label: AppStrings.drawStock,
          onPressed: onDraw,
          tone: _RailTone.primary,
        ),
      if (actions.canTakeDiscard)
        _RailButton(
          icon: Icons.move_down_outlined,
          label: AppStrings.takeDiscard,
          onPressed: onTakeDiscard,
          tone: _RailTone.tonal,
        ),
      if (actions.canClaimFifty)
        _RailButton(
          icon: Icons.local_fire_department_outlined,
          label: AppStrings.claimFifty,
          onPressed: onClaimFifty,
          tone: _RailTone.flame,
        ),
      if (actions.showPlaceCover)
        _RailButton(
          icon: Icons.call_merge,
          label: AppStrings.placeCover,
          onPressed: actions.canPlaceCover ? onPlaceCover : null,
          tone: _RailTone.tonal,
        ),
      if (actions.showReplaceJoker)
        _RailButton(
          icon: Icons.change_circle_outlined,
          label: AppStrings.replaceJoker,
          onPressed: actions.canReplaceJoker ? onReplaceJoker : null,
          tone: _RailTone.tonal,
        ),
      if (actions.canReturnDiscard)
        _RailButton(
          icon: Icons.undo,
          label: AppStrings.returnDiscard,
          onPressed: onReturnDiscard,
          tone: _RailTone.outlined,
        ),
      if (actions.canReturnOpeningMelds)
        _RailButton(
          icon: Icons.undo_outlined,
          label: AppStrings.takeBackMelds,
          onPressed: onReturnOpeningMelds,
          tone: _RailTone.outlined,
        ),
      if (actions.showDiscard)
        _RailButton(
          icon: Icons.remove_circle_outline,
          label: AppStrings.discardCard,
          onPressed: actions.canDiscard ? onDiscard : null,
          tone: _RailTone.primary,
        ),
    ];

    if (buttons.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: LoungeTokens.space2,
      runSpacing: LoungeTokens.space2,
      children: buttons,
    );
  }
}

enum _RailTone { primary, tonal, outlined, flame }

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final _RailTone tone;

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(icon, size: 18);
    final labelWidget = Text(label);
    switch (tone) {
      case _RailTone.primary:
        return FilledButton.icon(
          onPressed: onPressed,
          icon: iconWidget,
          label: labelWidget,
        );
      case _RailTone.tonal:
        return FilledButton.tonalIcon(
          onPressed: onPressed,
          icon: iconWidget,
          label: labelWidget,
        );
      case _RailTone.outlined:
        return OutlinedButton.icon(
          onPressed: onPressed,
          icon: iconWidget,
          label: labelWidget,
        );
      case _RailTone.flame:
        return FilledButton.icon(
          onPressed: onPressed,
          icon: iconWidget,
          label: labelWidget,
          style: FilledButton.styleFrom(
            backgroundColor: LoungeTokens.fiftyFlame,
            foregroundColor: LoungeTokens.offWhiteText,
          ),
        );
    }
  }
}
