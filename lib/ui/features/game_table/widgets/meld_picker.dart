import 'package:flutter/material.dart';

import '../../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../../domain/classic_hareeg/rules/meld_validator.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/cards/card_theme.dart';
import '../../../core/cards/card_view.dart';
import '../../../core/theme/lounge_tokens.dart';

/// Compact panel beside the action bar that shows the validity of the
/// currently selected meld and (when valid) a single confirmation button.
///
/// True legal-only combinatorial pickers across the full hand would require
/// engine support beyond the controller's current API. For now the picker
/// reflects the validity of the user's current selection and explains why
/// invalid groups are invalid — this still satisfies the Guided promise to
/// never show invalid options without a reason.
class MeldPickerPanel extends StatelessWidget {
  /// Creates the meld picker panel.
  const MeldPickerPanel({
    super.key,
    required this.theme,
    required this.selectedCards,
    required this.validation,
    required this.openingRequirement,
    required this.hasOpened,
    required this.onConfirm,
    this.canConfirm = false,
  });

  /// Active card theme.
  final HareegCardTheme theme;

  /// Currently selected cards (in order).
  final List<HareegCard> selectedCards;

  /// Validation result reported by the controller.
  final MeldValidationResult validation;

  /// Current opening benchmark for opening-progress text.
  final int openingRequirement;

  /// Whether the player has already opened.
  final bool hasOpened;

  /// Tap to confirm the meld.
  final VoidCallback onConfirm;

  /// True when the controller has a play-meld action ready (joker identity
  /// may still need a dialog before applying).
  final bool canConfirm;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    if (selectedCards.length < 3) {
      return const SizedBox.shrink();
    }

    final reason = validation.isValid
        ? _validReason(strings)
        : (validation.message.isEmpty
              ? strings.selectedCardsDoNotFormLegalMeld
              : strings.gameMessage(validation.message));

    return Container(
      padding: const EdgeInsets.all(LoungeTokens.space3),
      decoration: BoxDecoration(
        color: LoungeTokens.coffeeCharcoal,
        borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
        border: Border.all(
          color: validation.isValid
              ? LoungeTokens.goldAccent
              : LoungeTokens.sandLine.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                validation.isValid
                    ? Icons.check_circle_outline
                    : Icons.info_outline,
                size: 16,
                color: validation.isValid
                    ? LoungeTokens.goldAccent
                    : LoungeTokens.mutedText,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  reason,
                  style: LoungeTokens.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: LoungeTokens.space2),
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: selectedCards.length,
              separatorBuilder: (context, _) => const SizedBox(width: 4),
              itemBuilder: (context, index) {
                return HareegCardView(
                  theme: theme,
                  card: selectedCards[index],
                  variant: CardVariant.picker,
                  size: const Size(32, 46),
                );
              },
            ),
          ),
          const SizedBox(height: LoungeTokens.space2),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: canConfirm ? onConfirm : null,
              icon: const Icon(Icons.table_rows_outlined),
              label: Text(strings.playMeld),
            ),
          ),
        ],
      ),
    );
  }

  String _validReason(AppStrings strings) {
    final base = validation.message.isEmpty
        ? strings.legalMeld
        : strings.gameMessage(validation.message);
    if (hasOpened) {
      return base;
    }
    final remaining = openingRequirement - validation.value;
    if (remaining <= 0) {
      return '$base ${strings.openingReady(validation.value)}';
    }
    return '$base ${strings.valueNeedsOpening(validation.value, openingRequirement)}';
  }
}
