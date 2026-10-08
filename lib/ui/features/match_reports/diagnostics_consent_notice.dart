import 'package:flutter/material.dart';

import '../../../l10n/app_strings.dart';
import '../../core/panels/lounge_panel.dart';
import '../../core/theme/lounge_tokens.dart';

/// Shows the first-run disclosure for crash and bug reports.
///
/// Resolves to true when the player keeps reports on, false when they turn
/// them off. The dialog cannot be dismissed without a choice, so a resolved
/// notice is always an explicit answer the shell can persist.
Future<bool?> showDiagnosticsConsentNotice(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: LoungeTokens.overlayScrim,
    builder: (context) => const DiagnosticsConsentNotice(),
  );
}

/// The disclosure panel: what is sent, what never is, and how to opt out.
class DiagnosticsConsentNotice extends StatelessWidget {
  /// Creates the notice.
  const DiagnosticsConsentNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(LoungeTokens.space4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            child: LoungePanel(
              highContrast: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // No close button: the two actions are the whole contract.
                  LoungePanelHeader(
                    icon: Icons.shield_outlined,
                    title: strings.diagnosticsNoticeTitle,
                    subtitle: strings.diagnosticsSectionTitle,
                    onClose: null,
                    closeTooltip: null,
                  ),
                  const SizedBox(height: LoungeTokens.space4),
                  Text(
                    strings.diagnosticsNoticeBody,
                    style: LoungeTokens.bodyMuted,
                  ),
                  const SizedBox(height: LoungeTokens.space5),
                  LoungePanelActions(
                    primary: LoungePanelAction(
                      icon: Icons.check,
                      label: strings.diagnosticsNoticeKeepOn,
                      tone: LoungePanelActionTone.primary,
                      onTap: () => Navigator.of(context).pop(true),
                    ),
                    secondary: LoungePanelAction(
                      icon: Icons.block,
                      label: strings.diagnosticsNoticeTurnOff,
                      tone: LoungePanelActionTone.neutral,
                      onTap: () => Navigator.of(context).pop(false),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
