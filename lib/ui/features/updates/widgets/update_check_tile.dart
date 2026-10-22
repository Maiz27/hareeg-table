import 'package:flutter/material.dart';

import '../../../../data/updates/update_service.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../update_offer.dart';
import '../update_prompt_controller.dart';

/// A manual "Check for updates" row: tap it to ask the channel now.
///
/// The subtitle carries the installed version until a check runs, then its
/// answer: up to date, could not check, or store-managed with a button to
/// the listing. A newer release opens the update dialog over the current
/// screen, and a button stays behind to open it again.
class UpdateCheckTile extends StatefulWidget {
  /// Creates the row over [controller].
  const UpdateCheckTile({super.key, required this.controller});

  /// The update flow.
  final UpdatePromptController controller;

  @override
  State<UpdateCheckTile> createState() => _UpdateCheckTileState();
}

class _UpdateCheckTileState extends State<UpdateCheckTile> {
  var _checking = false;
  UpdateCheckResult? _result;

  @override
  void initState() {
    super.initState();
    widget.controller.loadInstalledVersion();
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _result = null;
    });
    final result = await widget.controller.checkNow();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _result = result;
    });
    if (result is UpdateCheckAvailable) {
      await offerUpdate(context, widget.controller, result.release);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final installed =
            widget.controller.installedVersion ?? strings.updateVersionUnknown;
        final result = _result;
        final status = _checking
            ? strings.updateChecking
            : switch (result) {
                null => strings.updateInstalledVersion(installed),
                UpdateCheckUpToDate() => strings.updateUpToDate,
                UpdateCheckFailed() => strings.updateCheckFailed,
                UpdateCheckStoreManaged() => strings.updateStoreManaged,
                UpdateCheckAvailable(:final release) =>
                  strings.updateAvailableTitle(release.version.toString()),
              };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              enabled: !_checking,
              leading: const Icon(Icons.refresh, color: LoungeTokens.accent),
              title: Text(
                strings.checkForUpdates,
                style: LoungeTokens.titleSmall,
              ),
              subtitle: Text(status, style: LoungeTokens.bodyMuted),
              trailing: const Icon(
                Icons.chevron_right,
                color: LoungeTokens.line,
              ),
              onTap: _check,
            ),
            if (result case UpdateCheckStoreManaged(:final listingUrl))
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: () => openUpdateLink(
                    context,
                    widget.controller.open(listingUrl),
                  ),
                  child: Text(strings.updateOpenStore),
                ),
              ),
            if (result case UpdateCheckAvailable(:final release))
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: () =>
                      offerUpdate(context, widget.controller, release),
                  icon: const Icon(Icons.system_update_outlined, size: 18),
                  label: Text(strings.updateViewOffer),
                ),
              ),
          ],
        );
      },
    );
  }
}
