import 'package:flutter/material.dart';

import '../../../l10n/app_strings.dart';
import '../../core/panels/lounge_panel.dart';
import '../../core/theme/lounge_tokens.dart';

/// What the player chose to do with a match report from the confirmation sheet.
enum MatchReportExportChoice {
  /// Share the report through the platform share sheet.
  share,

  /// Copy the report JSON to the clipboard.
  copy,
}

/// Shows the match-report confirmation sheet and resolves to the player's
/// choice, or null when they dismiss it.
///
/// The sheet explains what the report contains (game state + diagnostics, no
/// personal data) before anything is generated or shared, and stays a transient
/// modal so it never adds a permanent control or large panel to the table.
Future<MatchReportExportChoice?> showMatchReportConfirmation(
  BuildContext context, {
  bool highContrast = false,
}) {
  return showDialog<MatchReportExportChoice>(
    context: context,
    barrierColor: LoungeTokens.overlayScrim,
    builder: (context) => _MatchReportConfirmDialog(highContrast: highContrast),
  );
}

class _MatchReportConfirmDialog extends StatelessWidget {
  const _MatchReportConfirmDialog({required this.highContrast});

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
                const SizedBox(height: LoungeTokens.space5),
                LoungePanelActions(
                  primary: LoungePanelAction(
                    icon: Icons.ios_share,
                    label: strings.shareReport,
                    tone: LoungePanelActionTone.primary,
                    onTap: () => Navigator.of(
                      context,
                    ).pop(MatchReportExportChoice.share),
                  ),
                  secondary: LoungePanelAction(
                    icon: Icons.copy_all_outlined,
                    label: strings.copyReport,
                    tone: LoungePanelActionTone.neutral,
                    onTap: () => Navigator.of(
                      context,
                    ).pop(MatchReportExportChoice.copy),
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
