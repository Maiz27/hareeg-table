import 'package:flutter/material.dart';

import '../../../../l10n/app_strings.dart';
import '../../../core/panels/lounge_panel.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../../game_table/table_session_config.dart';

/// Asks blind or full-visibility before a sandbox starts.
///
/// The choice is taken **before** the table exists rather than toggled on it.
/// Visibility is a mode capability, and a mid-session switch would mean a
/// surface whose capabilities change under it — exactly the representable
/// invalid state the mode table exists to close.
///
/// Resolves to the chosen visibility, or null when the player backs out.
Future<BranchVisibility?> showBranchEntrySheet(
  BuildContext context, {
  bool highContrast = false,
}) {
  return showDialog<BranchVisibility>(
    context: context,
    barrierColor: LoungeTokens.overlayScrim,
    builder: (context) => _BranchEntryDialog(highContrast: highContrast),
  );
}

class _BranchEntryDialog extends StatelessWidget {
  const _BranchEntryDialog({required this.highContrast});

  final bool highContrast;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(LoungeTokens.space4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: LoungePanel(
            highContrast: highContrast,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LoungePanelHeader(
                  icon: Icons.alt_route_rounded,
                  title: strings.branchEntryTitle,
                  subtitle: strings.branchSandboxBadge,
                  onClose: () => Navigator.of(context).pop(),
                  // The app's own string: the shell ships no Material
                  // localization delegate for Arabic, so MaterialLocalizations
                  // would read "Close" on an Arabic chooser.
                  closeTooltip: strings.close,
                ),
                const SizedBox(height: LoungeTokens.space4),
                Text(strings.branchEntryBody, style: LoungeTokens.bodyMuted),
                const SizedBox(height: LoungeTokens.space4),
                _VisibilityChoice(
                  choiceKey: const ValueKey('branch-entry-blind'),
                  icon: Icons.visibility_off_outlined,
                  title: strings.branchEntryBlind,
                  note: strings.branchEntryBlindNote,
                  onTap: () =>
                      Navigator.of(context).pop(BranchVisibility.blind),
                ),
                const SizedBox(height: LoungeTokens.space3),
                _VisibilityChoice(
                  choiceKey: const ValueKey('branch-entry-study'),
                  icon: Icons.visibility_outlined,
                  title: strings.branchEntryStudy,
                  note: strings.branchEntryStudyNote,
                  onTap: () =>
                      Navigator.of(context).pop(BranchVisibility.study),
                ),
                const SizedBox(height: LoungeTokens.space4),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  // Sized and named like every other control on this
                  // surface: a bare TextButton is 36 dp tall and publishes no
                  // tooltip at all.
                  child: MergeSemantics(
                    child: Tooltip(
                      message: strings.branchEntryCancel,
                      excludeFromSemantics: true,
                      child: TextButton(
                        key: const ValueKey('branch-entry-cancel'),
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(44, 44),
                          padding: const EdgeInsets.symmetric(
                            horizontal: LoungeTokens.space4,
                          ),
                        ),
                        child: Text(strings.branchEntryCancel),
                      ),
                    ),
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

/// One visibility option: a title, why it matters, and a whole-row target.
class _VisibilityChoice extends StatelessWidget {
  const _VisibilityChoice({
    required this.choiceKey,
    required this.icon,
    required this.title,
    required this.note,
    required this.onTap,
  });

  final Key choiceKey;
  final IconData icon;
  final String title;
  final String note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      // The row already reads its own title, so the tooltip carries the
      // consequence: which one you pick decides what the sandbox shows you,
      // and it cannot be changed once the table exists.
      message: '$title. $note',
      // The row's own semantics carries the name; web would otherwise render
      // the tooltip as a second copy of it.
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        enabled: true,
        label: '$title. $note',
        child: Material(
          key: choiceKey,
          color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
            child: ConstrainedBox(
              // The whole row is the target, so the 44 dp floor is a floor on
              // the row rather than on an icon inside it.
              constraints: const BoxConstraints(minHeight: 44),
              // The row already publishes "<title>. <note>" as its own name.
              // Without this the two Texts underneath merge in as well and a
              // screen reader reads the whole option twice.
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.all(LoungeTokens.space3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, color: LoungeTokens.goldAccent, size: 22),
                      const SizedBox(width: LoungeTokens.space3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: LoungeTokens.body.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(note, style: LoungeTokens.bodyMuted),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
