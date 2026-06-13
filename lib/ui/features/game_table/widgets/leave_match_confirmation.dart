import 'package:flutter/material.dart';

import '../../../../l10n/app_strings.dart';
import '../../../core/panels/lounge_panel.dart';
import '../../../core/theme/lounge_tokens.dart';

/// Confirms leaving an in-progress match before navigating away.
///
/// Used on web, where the browser Back button maps onto the table's Navigator
/// pop and would otherwise jump straight to the menu mid-hand. The match is
/// persisted, so this is a courtesy confirm rather than a data-loss guard.
/// Resolves to true when the player chooses to leave, false/null otherwise.
Future<bool?> showLeaveMatchConfirmation(
  BuildContext context, {
  bool highContrast = false,
}) {
  return showDialog<bool>(
    context: context,
    barrierColor: LoungeTokens.overlayScrim,
    builder: (context) => _LeaveMatchConfirmDialog(highContrast: highContrast),
  );
}

class _LeaveMatchConfirmDialog extends StatelessWidget {
  const _LeaveMatchConfirmDialog({required this.highContrast});

  final bool highContrast;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(LoungeTokens.space4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: LoungePanel(
            highContrast: highContrast,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LoungePanelHeader(
                  icon: Icons.logout_rounded,
                  title: strings.leaveMatchTitle,
                  subtitle: strings.leaveTable,
                  onClose: () => Navigator.of(context).pop(false),
                  closeTooltip: MaterialLocalizations.of(
                    context,
                  ).closeButtonTooltip,
                ),
                const SizedBox(height: LoungeTokens.space4),
                Text(strings.leaveMatchBody, style: LoungeTokens.bodyMuted),
                const SizedBox(height: LoungeTokens.space5),
                LoungePanelActions(
                  primary: LoungePanelAction(
                    icon: Icons.logout_rounded,
                    label: strings.returnToMenu,
                    tone: LoungePanelActionTone.primary,
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                  secondary: LoungePanelAction(
                    icon: Icons.play_arrow_rounded,
                    label: strings.continueGame,
                    tone: LoungePanelActionTone.neutral,
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
