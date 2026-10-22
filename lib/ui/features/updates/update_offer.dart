import 'package:flutter/material.dart';

import '../../../domain/updates/update_decision.dart';
import '../../../l10n/app_strings.dart';
import '../../core/cards/card_theme.dart';
import 'update_prompt_controller.dart';
import 'widgets/update_available_dialog.dart';

/// Shows [offer] in the update dialog over whatever screen is up and applies
/// the player's answer to [updates]: Skip persists the newest version, any
/// other way out collapses the prompt for this session. Download and Release
/// notes open the newest release.
Future<void> offerUpdate(
  BuildContext context,
  UpdatePromptController updates,
  UpdateOffer offer,
) async {
  final release = offer.newest;
  final choice = await showUpdateAvailableDialog(
    context,
    offer: offer,
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
///
/// An opener that throws counts as "could not open": the platform opener
/// already answers false on failure, but an injected one may not.
Future<void> openUpdateLink(BuildContext context, Future<bool> opening) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final message = context.strings.updateCouldNotOpenLink;
  var opened = false;
  try {
    opened = await opening;
  } catch (error) {
    debugPrint('[updates] Could not open a link: $error');
  }
  if (!opened) {
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }
}
