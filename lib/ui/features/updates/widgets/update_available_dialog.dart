import 'package:flutter/material.dart';

import '../../../../domain/updates/app_release.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/panels/lounge_panel.dart';
import '../../../core/theme/lounge_tokens.dart';

/// How the player left the update dialog.
enum UpdateDialogChoice {
  /// Download was tapped (the link is already being opened).
  download,

  /// Skip this version.
  skip,

  /// Closed for now: the close button, the barrier or Back.
  later,
}

/// Shows the "update available" prompt as a lounge dialog over the menu.
///
/// Download and release notes open through the callbacks; Download also
/// closes the dialog, Release notes keeps it open so the player can come back
/// to download. Any other way out resolves to [UpdateDialogChoice.later].
Future<UpdateDialogChoice> showUpdateAvailableDialog(
  BuildContext context, {
  required AppRelease release,
  required String? installedVersion,
  required bool highContrast,
  required VoidCallback onDownload,
  required VoidCallback onReleaseNotes,
}) async {
  final choice = await showDialog<UpdateDialogChoice>(
    context: context,
    barrierColor: LoungeTokens.scrim,
    builder: (context) => UpdateAvailableDialog(
      release: release,
      installedVersion: installedVersion,
      highContrast: highContrast,
      onDownload: onDownload,
      onReleaseNotes: onReleaseNotes,
    ),
  );
  return choice ?? UpdateDialogChoice.later;
}

/// The update prompt: version, what changed as a capped scrollable list of
/// bullets, Download and Release notes, and a quieter Skip.
///
/// A lounge panel without its corner medallion: the dialog floats over the
/// menu backdrop's motif already. Pops with an [UpdateDialogChoice].
class UpdateAvailableDialog extends StatelessWidget {
  /// Creates the dialog for [release].
  const UpdateAvailableDialog({
    super.key,
    required this.release,
    required this.installedVersion,
    required this.highContrast,
    required this.onDownload,
    required this.onReleaseNotes,
  });

  /// The newer release.
  final AppRelease release;

  /// The installed version, when known.
  final String? installedVersion;

  /// Whether the high-contrast accessibility surface is active.
  final bool highContrast;

  /// Opens the APK download.
  final VoidCallback onDownload;

  /// Opens the release page.
  final VoidCallback onReleaseNotes;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final sections = release.noteSections;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(LoungeTokens.space4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: LoungePanel(
            highContrast: highContrast,
            showMotif: false,
            padding: const EdgeInsets.all(LoungeTokens.space4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LoungePanelHeader(
                  icon: Icons.system_update_outlined,
                  title: strings.updateAvailableTitle(
                    release.version.toString(),
                  ),
                  subtitle: strings.updateInstalledVersion(
                    installedVersion ?? strings.updateVersionUnknown,
                  ),
                  onClose: () =>
                      Navigator.of(context).pop(UpdateDialogChoice.later),
                  closeTooltip: strings.updateLater,
                ),
                if (sections.isNotEmpty) ...[
                  const SizedBox(height: LoungeTokens.space4),
                  _ReleaseNotesList(sections: sections),
                ],
                const SizedBox(height: LoungeTokens.space5),
                LoungePanelActions(
                  primary: LoungePanelAction(
                    icon: Icons.download_outlined,
                    label: strings.updateDownload,
                    tone: LoungePanelActionTone.primary,
                    onTap: () {
                      onDownload();
                      Navigator.of(context).pop(UpdateDialogChoice.download);
                    },
                  ),
                  secondary: LoungePanelAction(
                    icon: Icons.article_outlined,
                    label: strings.updateReleaseNotes,
                    tone: LoungePanelActionTone.neutral,
                    onTap: onReleaseNotes,
                  ),
                ),
                const SizedBox(height: LoungeTokens.space2),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: () =>
                        Navigator.of(context).pop(UpdateDialogChoice.skip),
                    style: TextButton.styleFrom(
                      foregroundColor: LoungeTokens.textMuted,
                    ),
                    child: Text(strings.updateSkipVersion),
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

/// The release notes as headed bullets inside an inset box that grows with
/// its content up to [maxHeight] and scrolls beyond it.
class _ReleaseNotesList extends StatefulWidget {
  const _ReleaseNotesList({required this.sections});

  final List<ReleaseNoteSection> sections;

  static const maxHeight = 220.0;

  @override
  State<_ReleaseNotesList> createState() => _ReleaseNotesListState();
}

class _ReleaseNotesListState extends State<_ReleaseNotesList> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final section in widget.sections) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: LoungeTokens.space3));
      }
      final heading = section.heading;
      if (heading != null) {
        children
          ..add(Text(heading, style: LoungeTokens.titleSmall))
          ..add(const SizedBox(height: LoungeTokens.space1));
      }
      for (final item in section.items) {
        children.add(_Bullet(text: item));
      }
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _ReleaseNotesList.maxHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: LoungeTokens.surfaceInset,
          borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
          border: Border.all(color: LoungeTokens.lineSoft),
        ),
        child: Scrollbar(
          controller: _scroll,
          thumbVisibility: true,
          child: ListView(
            controller: _scroll,
            shrinkWrap: true,
            padding: const EdgeInsetsDirectional.fromSTEB(
              LoungeTokens.space3,
              LoungeTokens.space3,
              LoungeTokens.space4,
              LoungeTokens.space3,
            ),
            children: children,
          ),
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LoungeTokens.space1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsetsDirectional.only(end: LoungeTokens.space2),
            child: Text('•', style: LoungeTokens.body),
          ),
          Expanded(child: Text(text, style: LoungeTokens.body)),
        ],
      ),
    );
  }
}
