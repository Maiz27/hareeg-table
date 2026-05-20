import 'package:flutter/material.dart';

import '../../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/cards/card_state.dart';
import '../../../core/cards/card_theme.dart';
import '../../../core/cards/card_view.dart';
import '../../../core/theme/lounge_tokens.dart';

/// Sort modes available to the south seat hand.
enum HandSortMode {
  /// Player ordering — no auto sort.
  manual,

  /// Rank-major, then suit.
  byRank,

  /// Suit-major, then rank.
  bySuit,
}

/// South seat (human) hand strip + sort mode toggle.
///
/// Cards are tappable and (optionally) draggable. The strip scrolls
/// horizontally if cards overflow. The hand reorder is driven by
/// [ReorderableListView]; the parent persists the new order back to the
/// controller via [onReorder] (no-op when [reorderable] is false).
class SouthSeatHand extends StatelessWidget {
  /// Creates a south seat hand strip.
  const SouthSeatHand({
    super.key,
    required this.theme,
    required this.cards,
    required this.selectedIds,
    required this.pendingId,
    required this.onSelect,
    required this.onReorder,
    required this.sortMode,
    required this.onSortModeChanged,
    this.cardSize = const Size(56, 80),
    this.reorderable = true,
  });

  /// Active card theme.
  final HareegCardTheme theme;

  /// Cards in the seat hand.
  final List<HareegCard> cards;

  /// Currently selected card IDs.
  final Set<String> selectedIds;

  /// The pending discard's id (rendered with pending overlay), if any.
  final String? pendingId;

  /// Tap-to-select handler.
  final ValueChanged<HareegCard> onSelect;

  /// Manual reorder handler (oldIndex, newIndex).
  final void Function(int oldIndex, int newIndex) onReorder;

  /// Current sort mode toggle value.
  final HandSortMode sortMode;

  /// Sort mode change handler.
  final ValueChanged<HandSortMode> onSortModeChanged;

  /// Default render size for a hand card.
  final Size cardSize;

  /// True when manual drag-to-reorder should be enabled.
  final bool reorderable;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SortBar(value: sortMode, onChanged: onSortModeChanged),
        const SizedBox(height: 4),
        SizedBox(
          height: cardSize.height + LoungeTokens.space2,
          child: reorderable && sortMode == HandSortMode.manual
              ? _ReorderableHand(
                  theme: theme,
                  cards: cards,
                  selectedIds: selectedIds,
                  pendingId: pendingId,
                  cardSize: cardSize,
                  onSelect: onSelect,
                  onReorder: onReorder,
                )
              : _ScrollingHand(
                  theme: theme,
                  cards: cards,
                  selectedIds: selectedIds,
                  pendingId: pendingId,
                  cardSize: cardSize,
                  onSelect: onSelect,
                ),
        ),
      ],
    );
  }
}

class _SortBar extends StatelessWidget {
  const _SortBar({required this.value, required this.onChanged});

  final HandSortMode value;
  final ValueChanged<HandSortMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(AppStrings.sortModeLabel, style: LoungeTokens.bodyMuted),
        const SizedBox(width: LoungeTokens.space2),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<HandSortMode>(
              segments: const [
                ButtonSegment(
                  value: HandSortMode.manual,
                  label: Text(AppStrings.sortManual),
                  icon: Icon(Icons.drag_indicator),
                ),
                ButtonSegment(
                  value: HandSortMode.byRank,
                  label: Text(AppStrings.sortByRank),
                ),
                ButtonSegment(
                  value: HandSortMode.bySuit,
                  label: Text(AppStrings.sortBySuit),
                ),
              ],
              selected: {value},
              onSelectionChanged: (selection) => onChanged(selection.first),
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: WidgetStateProperty.all(
                  LoungeTokens.titleSmall.copyWith(fontSize: 11),
                ),
                padding: WidgetStateProperty.all(
                  const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScrollingHand extends StatelessWidget {
  const _ScrollingHand({
    required this.theme,
    required this.cards,
    required this.selectedIds,
    required this.pendingId,
    required this.cardSize,
    required this.onSelect,
  });

  final HareegCardTheme theme;
  final List<HareegCard> cards;
  final Set<String> selectedIds;
  final String? pendingId;
  final Size cardSize;
  final ValueChanged<HareegCard> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: cards.length,
      separatorBuilder: (context, index) => const SizedBox(width: 4),
      itemBuilder: (context, index) {
        final card = cards[index];
        return _HandCardChip(
          theme: theme,
          card: card,
          selected: selectedIds.contains(card.id),
          pending: pendingId == card.id,
          size: cardSize,
          onTap: () => onSelect(card),
        );
      },
    );
  }
}

class _ReorderableHand extends StatelessWidget {
  const _ReorderableHand({
    required this.theme,
    required this.cards,
    required this.selectedIds,
    required this.pendingId,
    required this.cardSize,
    required this.onSelect,
    required this.onReorder,
  });

  final HareegCardTheme theme;
  final List<HareegCard> cards;
  final Set<String> selectedIds;
  final String? pendingId;
  final Size cardSize;
  final ValueChanged<HareegCard> onSelect;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      scrollDirection: Axis.horizontal,
      buildDefaultDragHandles: false,
      itemCount: cards.length,
      // TODO: Replace with onReorderItem after the repo requires Flutter 3.44+.
      // ignore: deprecated_member_use
      onReorder: onReorder,
      proxyDecorator: (child, index, animation) => Material(
        color: Colors.transparent,
        elevation: 6,
        borderRadius: BorderRadius.circular(LoungeTokens.radiusCard),
        child: child,
      ),
      itemBuilder: (context, index) {
        final card = cards[index];
        return ReorderableDragStartListener(
          key: ValueKey(card.id),
          index: index,
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _HandCardChip(
              theme: theme,
              card: card,
              selected: selectedIds.contains(card.id),
              pending: pendingId == card.id,
              size: cardSize,
              onTap: () => onSelect(card),
            ),
          ),
        );
      },
    );
  }
}

class _HandCardChip extends StatelessWidget {
  const _HandCardChip({
    required this.theme,
    required this.card,
    required this.selected,
    required this.pending,
    required this.size,
    required this.onTap,
  });

  final HareegCardTheme theme;
  final HareegCard card;
  final bool selected;
  final bool pending;
  final Size size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final state = pending
        ? CardVisualState.pending
        : selected
            ? CardVisualState.selected
            : CardVisualState.normal;

    final offset = selected ? -6.0 : 0.0;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, offset, 0),
        child: HareegCardView(
          theme: theme,
          card: card,
          variant: CardVariant.full,
          size: size,
          visualState: state,
        ),
      ),
    );
  }
}

/// Sort utility used by the orchestrator to render a stable view order
/// without mutating the controller's internal hand list (which is the source
/// of truth for action IDs).
abstract final class HandSorting {
  /// Returns [cards] sorted according to [mode].
  static List<HareegCard> sort(List<HareegCard> cards, HandSortMode mode) {
    final copy = List<HareegCard>.of(cards);
    switch (mode) {
      case HandSortMode.manual:
        return copy;
      case HandSortMode.byRank:
        copy.sort((a, b) {
          final aRank = a.effectiveIdentity?.rank.order ?? 999;
          final bRank = b.effectiveIdentity?.rank.order ?? 999;
          if (aRank != bRank) return aRank - bRank;
          final aSuit = a.effectiveIdentity?.suit.index ?? 999;
          final bSuit = b.effectiveIdentity?.suit.index ?? 999;
          return aSuit - bSuit;
        });
      case HandSortMode.bySuit:
        copy.sort((a, b) {
          final aSuit = a.effectiveIdentity?.suit.index ?? 999;
          final bSuit = b.effectiveIdentity?.suit.index ?? 999;
          if (aSuit != bSuit) return aSuit - bSuit;
          final aRank = a.effectiveIdentity?.rank.order ?? 999;
          final bRank = b.effectiveIdentity?.rank.order ?? 999;
          return aRank - bRank;
        });
    }
    return copy;
  }
}
