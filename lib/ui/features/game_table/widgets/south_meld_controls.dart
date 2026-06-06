import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/cards/card_state.dart';
import '../../../core/cards/card_theme.dart';
import '../../../core/cards/card_view.dart';
import '../../../core/theme/lounge_tokens.dart';
import 'physical_table_playfield.dart' show TableMeldSuggestion;

/// Horizontal scrollable rack of up to three legal meld suggestions, shown
/// just above the south meld lane when the player has selected cards that
/// form one or more legal melds.
class MeldSuggestionRack extends StatelessWidget {
  /// Creates a meld suggestion rack.
  const MeldSuggestionRack({
    super.key,
    required this.theme,
    required this.suggestions,
    required this.cardSize,
    required this.onTapSuggestion,
    required this.onCardLongPress,
  });

  /// Card theme used to render suggestion cards.
  final HareegCardTheme theme;

  /// Legal meld options for the current selection.
  final List<TableMeldSuggestion> suggestions;

  /// Card size used by each suggestion group.
  final Size cardSize;

  /// Callback fired when a suggestion is tapped, with its action id.
  final ValueChanged<String> onTapSuggestion;

  /// Long-press handler for inspecting a suggestion card.
  final ValueChanged<HareegCard> onCardLongPress;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 140),
      child: Container(
        key: ValueKey(suggestions.map((s) => s.actionId).join('|')),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.90),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.13)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.24),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Separators go between groups only — a trailing one would pad
              // the rack asymmetrically after the last suggestion.
              for (final (index, suggestion) in suggestions.take(3).indexed) ...[
                if (index > 0) const SizedBox(width: 10),
                _SuggestionGroup(
                  theme: theme,
                  suggestion: suggestion,
                  cardSize: cardSize,
                  onTap: () => onTapSuggestion(suggestion.actionId),
                  onCardLongPress: onCardLongPress,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionGroup extends StatelessWidget {
  const _SuggestionGroup({
    required this.theme,
    required this.suggestion,
    required this.cardSize,
    required this.onTap,
    required this.onCardLongPress,
  });

  final HareegCardTheme theme;
  final TableMeldSuggestion suggestion;
  final Size cardSize;
  final VoidCallback onTap;
  final ValueChanged<HareegCard> onCardLongPress;

  @override
  Widget build(BuildContext context) {
    final cards = suggestion.cards;
    final gap = cardSize.width * 0.50;
    final width = cardSize.width + math.max(0, cards.length - 1) * gap;
    return Tooltip(
      message: context.strings.playMeld,
      child: GestureDetector(
        key: ValueKey('meld-suggestion-${suggestion.actionId}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: cardSize.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < cards.length; i++)
                Positioned(
                  left: i * gap,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onLongPress: () => onCardLongPress(cards[i]),
                    child: HareegCardView(
                      theme: theme,
                      card: cards[i],
                      jokerDisplay: JokerDisplay.assisted,
                      size: cardSize,
                      visualState: CardVisualState.coverTarget,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom-right pill column carrying the Meld CTA and the optional
/// take-back-opening-melds undo pill.
class SouthSideControls extends StatelessWidget {
  /// Creates the south side controls.
  const SouthSideControls({
    super.key,
    required this.meldRequirement,
    required this.meldSelectionValue,
    required this.meldSelectionValid,
    required this.meldSelectionHasOpened,
    required this.onPlaySelectedMeld,
    required this.compact,
    required this.canReturnOpeningMelds,
    required this.onReturnOpeningMelds,
  });

  /// Current opening requirement value shown on the chip when no selection.
  final int meldRequirement;

  /// Value of the currently selected meld when valid, else null.
  final int? meldSelectionValue;

  /// Whether the selected cards form a single playable meld action.
  final bool meldSelectionValid;

  /// Whether the south seat has already opened this round.
  final bool meldSelectionHasOpened;

  /// Tap handler that plays the currently selected meld, or null when no
  /// valid selection is in flight.
  final VoidCallback? onPlaySelectedMeld;

  /// Whether the table is rendering in compact mode.
  final bool compact;

  /// Whether the take-back-opening-melds pill should be visible.
  final bool canReturnOpeningMelds;

  /// Callback fired when the take-back pill is tapped.
  final VoidCallback onReturnOpeningMelds;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MeldCtaButton(
          requirement: meldRequirement,
          selectionValue: meldSelectionValue,
          selectionValid: meldSelectionValid,
          hasOpened: meldSelectionHasOpened,
          onTap: onPlaySelectedMeld,
          compact: compact,
        ),
        if (canReturnOpeningMelds) ...[
          SizedBox(height: compact ? 4 : 6),
          Tooltip(
            message: context.strings.takeBackMelds,
            child: _IconTablePill(
              icon: Icons.undo_rounded,
              compact: compact,
              onTap: onReturnOpeningMelds,
            ),
          ),
        ],
      ],
    );
  }
}

class _TablePill extends StatelessWidget {
  const _TablePill({required this.compact, required this.child});

  final bool compact;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 30 : 34,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: IconTheme(
        data: const IconThemeData(color: LoungeTokens.coffeeCharcoal),
        child: DefaultTextStyle(
          style: const TextStyle(color: LoungeTokens.coffeeCharcoal),
          child: child,
        ),
      ),
    );
  }
}

class _IconTablePill extends StatelessWidget {
  const _IconTablePill({
    required this.icon,
    required this.compact,
    required this.onTap,
  });

  final IconData icon;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: _TablePill(
          compact: compact,
          child: Icon(icon, size: compact ? 16 : 18),
        ),
      ),
    );
  }
}

/// Bottom-right Meld chip. When the human seat has selected a complete legal
/// meld, becomes a tappable confirmation CTA showing the played value;
/// otherwise renders the current opening requirement as a static reference.
class _MeldCtaButton extends StatelessWidget {
  const _MeldCtaButton({
    required this.requirement,
    required this.selectionValue,
    required this.selectionValid,
    required this.hasOpened,
    required this.onTap,
    required this.compact,
  });

  final int requirement;
  final int? selectionValue;
  final bool selectionValid;
  final bool hasOpened;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final isCta = selectionValid && onTap != null;
    final displayValue = selectionValue ?? requirement;
    final caption = isCta
        ? (hasOpened ? strings.playMeld : strings.openMeld)
        : (hasOpened ? strings.meld : strings.openNeed);
    final background = isCta
        ? LoungeTokens.goldAccent
        : LoungeTokens.coffeeCharcoal.withValues(alpha: 0.92);
    final foreground = isCta
        ? LoungeTokens.coffeeCharcoal
        : LoungeTokens.offWhiteText;

    final body = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      height: compact ? 40 : 48,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCta
              ? Colors.white.withValues(alpha: 0.32)
              : Colors.white.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: isCta
                ? LoungeTokens.goldAccent.withValues(alpha: 0.22)
                : Colors.black.withValues(alpha: 0.16),
            blurRadius: isCta ? 12 : 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              caption,
              style: TextStyle(
                color: foreground,
                fontSize: compact ? 8.5 : 10,
                fontWeight: FontWeight.w800,
                height: 1,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$displayValue',
              style: TextStyle(
                color: foreground,
                fontSize: compact ? 14 : 17,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );

    if (!isCta) return body;

    return Tooltip(
      message: strings.playSelectedMeld,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: body,
        ),
      ),
    );
  }
}
