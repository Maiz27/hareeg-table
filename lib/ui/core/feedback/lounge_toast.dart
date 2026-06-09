import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/lounge_tokens.dart';

OverlayEntry? _activeLoungeToast;
Timer? _activeLoungeToastTimer;

/// Shows a compact, table-style transient message above the current route.
void showLoungeToast(
  BuildContext context, {
  required String message,
  IconData icon = Icons.check_circle_outline,
  bool isError = false,
  String? actionLabel,
  VoidCallback? onActionPressed,
}) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) {
    return;
  }

  _activeLoungeToastTimer?.cancel();
  _activeLoungeToast?.remove();

  late final OverlayEntry entry;
  void dismiss() {
    if (entry.mounted) {
      entry.remove();
    }
    if (_activeLoungeToast == entry) {
      _activeLoungeToast = null;
    }
  }

  entry = OverlayEntry(
    builder: (context) => _LoungeToastOverlay(
      message: message,
      icon: icon,
      isError: isError,
      actionLabel: actionLabel,
      onActionPressed: onActionPressed == null
          ? null
          : () {
              _activeLoungeToastTimer?.cancel();
              dismiss();
              onActionPressed();
            },
    ),
  );

  _activeLoungeToast = entry;
  overlay.insert(entry);
  _activeLoungeToastTimer = Timer(
    actionLabel == null
        ? const Duration(seconds: 3)
        : const Duration(seconds: 6),
    dismiss,
  );
}

class _LoungeToastOverlay extends StatelessWidget {
  const _LoungeToastOverlay({
    required this.message,
    required this.icon,
    required this.isError,
    required this.actionLabel,
    required this.onActionPressed,
  });

  final String message;
  final IconData icon;
  final bool isError;
  final String? actionLabel;
  final VoidCallback? onActionPressed;

  @override
  Widget build(BuildContext context) {
    final accent = isError ? LoungeTokens.deepRed : LoungeTokens.goldAccent;
    final top = MediaQuery.paddingOf(context).top + LoungeTokens.space4;
    return Positioned(
      top: top,
      left: LoungeTokens.space4,
      right: LoungeTokens.space4,
      child: IgnorePointer(
        ignoring: onActionPressed == null,
        child: Align(
          alignment: Alignment.topCenter,
          child: Material(
            key: const ValueKey('lounge-toast'),
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 360),
              padding: const EdgeInsets.symmetric(
                horizontal: LoungeTokens.space3,
                vertical: 7,
              ),
              decoration: BoxDecoration(
                color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
                border: Border.all(color: accent.withValues(alpha: 0.78)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.26),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: accent),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      message,
                      style: LoungeTokens.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (actionLabel != null && onActionPressed != null) ...[
                    const SizedBox(width: LoungeTokens.space2),
                    TextButton(
                      onPressed: onActionPressed,
                      style: TextButton.styleFrom(
                        foregroundColor: LoungeTokens.goldAccent,
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: LoungeTokens.space2,
                          vertical: 0,
                        ),
                        textStyle: LoungeTokens.titleSmall,
                      ),
                      child: Text(actionLabel!),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
