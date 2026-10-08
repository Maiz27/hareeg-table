import 'package:flutter/material.dart';

import '../../../l10n/app_strings.dart';
import '../../core/panels/lounge_panel.dart';
import '../../core/theme/lounge_tokens.dart';

/// What the player chose to do with a match report from the confirmation sheet.
enum MatchReportExportChoice {
  /// Send the report to the developer through diagnostics.
  send,

  /// Share the report through the platform share sheet.
  share,

  /// Copy the report JSON to the clipboard.
  copy,
}

/// Whether the confirmation sheet can offer sending the report directly.
enum MatchReportSendAvailability {
  /// Diagnostics are running: "Send report" is the primary action.
  available,

  /// This build has no diagnostics backend (no DSN).
  unavailable,

  /// The player turned crash & bug reports off.
  disabled,
}

/// Shows the match-report confirmation sheet and resolves to the player's
/// choice, or null when they dismiss it.
///
/// The sheet explains what the report contains (game state + diagnostics, no
/// personal data) before anything is generated or shared, and stays a transient
/// modal so it never adds a permanent control or large panel to the table.
///
/// When [send] is available, sending is the primary action and Share/Copy are
/// demoted to an offline/power-user fallback beneath it. Otherwise Share/Copy
/// lead; after an opt-out a line says reports are off, and a build without a
/// DSN does not mention sending at all.
Future<MatchReportExportChoice?> showMatchReportConfirmation(
  BuildContext context, {
  bool highContrast = false,
  MatchReportSendAvailability send = MatchReportSendAvailability.unavailable,
}) {
  return showDialog<MatchReportExportChoice>(
    context: context,
    barrierColor: LoungeTokens.overlayScrim,
    builder: (context) =>
        _MatchReportConfirmDialog(highContrast: highContrast, send: send),
  );
}

class _MatchReportConfirmDialog extends StatelessWidget {
  const _MatchReportConfirmDialog({
    required this.highContrast,
    required this.send,
  });

  final bool highContrast;
  final MatchReportSendAvailability send;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final canSend = send == MatchReportSendAvailability.available;
    // A build without a DSN never mentions sending: there is nothing the
    // player could turn on.
    final sendNotice = send == MatchReportSendAvailability.disabled
        ? strings.matchReportSendDisabled
        : null;
    final share = LoungePanelAction(
      icon: Icons.ios_share,
      label: strings.shareReport,
      tone: canSend
          ? LoungePanelActionTone.neutral
          : LoungePanelActionTone.primary,
      onTap: () => Navigator.of(context).pop(MatchReportExportChoice.share),
    );
    final copy = LoungePanelAction(
      icon: Icons.copy_all_outlined,
      label: strings.copyReport,
      tone: LoungePanelActionTone.neutral,
      onTap: () => Navigator.of(context).pop(MatchReportExportChoice.copy),
    );
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
                  icon: Icons.bug_report_outlined,
                  title: strings.matchReportConfirmTitle,
                  subtitle: strings.exportMatchReport,
                  onClose: () => Navigator.of(context).pop(),
                  closeTooltip: MaterialLocalizations.of(
                    context,
                  ).closeButtonTooltip,
                ),
                const SizedBox(height: LoungeTokens.space4),
                Text(
                  strings.matchReportConfirmBody,
                  style: LoungeTokens.bodyMuted,
                ),
                if (sendNotice != null) ...[
                  const SizedBox(height: LoungeTokens.space3),
                  Text(sendNotice, style: LoungeTokens.bodyMuted),
                ],
                const SizedBox(height: LoungeTokens.space5),
                LoungePanelActions(
                  tertiary: canSend
                      ? LoungePanelAction(
                          icon: Icons.send_outlined,
                          label: strings.sendReport,
                          tone: LoungePanelActionTone.primary,
                          onTap: () => Navigator.of(
                            context,
                          ).pop(MatchReportExportChoice.send),
                        )
                      : null,
                  primary: share,
                  secondary: copy,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
