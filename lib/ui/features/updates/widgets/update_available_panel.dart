import 'package:flutter/material.dart';

import '../../../../domain/updates/app_release.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/cards/card_theme.dart';
import '../../../core/panels/lounge_panel.dart';
import '../../../core/theme/lounge_tokens.dart';

/// Home-screen prompt offering a newer release.
///
/// A lounge panel rather than a dialog: it sits in the menu's flow and never
/// interrupts the player. Download and release notes are the two buttons;
/// skipping is a quieter text action below them, and the header's close
/// button only collapses the panel for this session.
class UpdateAvailablePanel extends StatelessWidget {
  /// Creates the prompt for [release].
  const UpdateAvailablePanel({
    super.key,
    required this.release,
    required this.installedVersion,
    required this.onDownload,
    required this.onReleaseNotes,
    required this.onSkip,
    required this.onLater,
  });

  /// The newer release.
  final AppRelease release;

  /// The installed version, when known.
  final String? installedVersion;

  /// Opens the APK download.
  final VoidCallback onDownload;

  /// Opens the release page.
  final VoidCallback onReleaseNotes;

  /// Skips this release for good.
  final VoidCallback onSkip;

  /// Collapses the panel for this session.
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final summary = release.notesSummary;

    return LoungePanel(
      highContrast: CardContrastScope.enabledOf(context),
      padding: const EdgeInsets.all(LoungeTokens.space4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LoungePanelHeader(
            icon: Icons.system_update_outlined,
            title: strings.updateAvailableTitle(release.version.toString()),
            subtitle: strings.updateInstalledVersion(
              installedVersion ?? strings.updateVersionUnknown,
            ),
            onClose: onLater,
            closeTooltip: strings.updateLater,
          ),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: LoungeTokens.space3),
            Text(summary, style: LoungeTokens.bodyMuted),
          ],
          const SizedBox(height: LoungeTokens.space4),
          LoungePanelActions(
            primary: LoungePanelAction(
              icon: Icons.download_outlined,
              label: strings.updateDownload,
              onTap: onDownload,
              tone: LoungePanelActionTone.primary,
            ),
            secondary: LoungePanelAction(
              icon: Icons.article_outlined,
              label: strings.updateReleaseNotes,
              onTap: onReleaseNotes,
              tone: LoungePanelActionTone.neutral,
            ),
          ),
          const SizedBox(height: LoungeTokens.space2),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: onSkip,
              style: TextButton.styleFrom(
                foregroundColor: LoungeTokens.textMuted,
              ),
              child: Text(strings.updateSkipVersion),
            ),
          ),
        ],
      ),
    );
  }
}
