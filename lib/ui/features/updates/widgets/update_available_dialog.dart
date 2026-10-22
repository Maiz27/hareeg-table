import 'package:flutter/material.dart';

import '../../../../domain/updates/update_decision.dart';
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
  required UpdateOffer offer,
  required String? installedVersion,
  required bool highContrast,
  required VoidCallback onDownload,
  required VoidCallback onReleaseNotes,
}) async {
  final choice = await showDialog<UpdateDialogChoice>(
    context: context,
    barrierColor: LoungeTokens.scrim,
    builder: (context) => UpdateAvailableDialog(
      offer: offer,
      installedVersion: installedVersion,
      highContrast: highContrast,
      onDownload: onDownload,
      onReleaseNotes: onReleaseNotes,
    ),
  );
  return choice ?? UpdateDialogChoice.later;
}

/// The update prompt: the newest version, what changed since the installed
/// build as a capped scrollable list of bullets, Download and Release notes,
/// and a quieter Skip.
///
/// The notes add up every release in the offer, newest first, each under its
/// version; a single release needs no version heading because the title
/// already names it.
///
/// A lounge panel without its corner medallion: the dialog floats over the
/// menu backdrop's motif already. Pops with an [UpdateDialogChoice].
class UpdateAvailableDialog extends StatelessWidget {
  /// Creates the dialog for [offer].
  const UpdateAvailableDialog({
    super.key,
    required this.offer,
    required this.installedVersion,
    required this.highContrast,
    required this.onDownload,
    required this.onReleaseNotes,
  });

  /// The newest release and the releases between it and the installed build.
  final UpdateOffer offer;

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
    final notes = _ReleaseNotesList.entriesFor(offer, strings);

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
                    offer.newest.version.toString(),
                  ),
                  subtitle: strings.updateInstalledVersion(
                    installedVersion ?? strings.updateVersionUnknown,
                  ),
                  onClose: () =>
                      Navigator.of(context).pop(UpdateDialogChoice.later),
                  closeTooltip: strings.updateLater,
                ),
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: LoungeTokens.space4),
                  _ReleaseNotesList(children: notes),
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
  const _ReleaseNotesList({required this.children});

  /// The rows built by [entriesFor].
  final List<Widget> children;

  static const maxHeight = 220.0;

  /// A release's version above its notes: a notch above the section
  /// headings, in the accent.
  static final versionStyle = LoungeTokens.title.copyWith(
    color: LoungeTokens.accent,
  );

  /// The rows for [offer]'s notes, or none when there is nothing to show.
  ///
  /// Each release, newest first, gets its version (only when the offer holds
  /// more than one) and then its headed bullets. A last muted line says so
  /// when releases older than the listing were left out.
  static List<Widget> entriesFor(UpdateOffer offer, AppStrings strings) {
    final showVersions = offer.releases.length > 1;
    final children = <Widget>[];
    for (final release in offer.releases) {
      final sections = release.noteSections;
      if (!showVersions && sections.isEmpty) continue;
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: LoungeTokens.space4));
      }
      if (showVersions) {
        children
          ..add(Text(release.version.toString(), style: versionStyle))
          ..add(const SizedBox(height: LoungeTokens.space2));
      }
      var firstSection = true;
      for (final section in sections) {
        if (!firstSection) {
          children.add(const SizedBox(height: LoungeTokens.space3));
        }
        firstSection = false;
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
    }
    if (offer.hasOlderUnlisted) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: LoungeTokens.space3));
      }
      children.add(
        Text(
          strings.updateEarlierReleasesUnlisted,
          style: LoungeTokens.bodyMuted,
        ),
      );
    }
    return children;
  }

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
            children: widget.children,
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
