import 'package:flutter/material.dart';

import '../../../domain/updates/app_release.dart';
import '../../../l10n/app_strings.dart';
import '../../core/cards/card_theme.dart';
import 'update_prompt_controller.dart';
import 'widgets/update_available_dialog.dart';

/// Offers [release] in the update dialog over whatever screen is up and
/// applies the player's answer to [updates]: Skip persists the version, any
/// other way out collapses the prompt for this session.
Future<void> offerUpdate(
  BuildContext context,
  UpdatePromptController updates,
  AppRelease release,
) async {
  final choice = await showUpdateAvailableDialog(
    context,
    release: release,
    installedVersion: updates.installedVersion,
    highContrast: CardContrastScope.enabledOf(context),
    onDownload: () => openUpdateLink(context, updates.download(release)),
    onReleaseNotes: () =>
        openUpdateLink(context, updates.openReleaseNotes(release)),
  );
  switch (choice) {
    case UpdateDialogChoice.skip:
      await updates.skip();
    case UpdateDialogChoice.download:
    case UpdateDialogChoice.later:
      updates.later();
  }
}

/// Awaits [opening] and tells the player when the link could not be opened.
Future<void> openUpdateLink(BuildContext context, Future<bool> opening) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final message = context.strings.updateCouldNotOpenLink;
  if (!await opening) {
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }
}
