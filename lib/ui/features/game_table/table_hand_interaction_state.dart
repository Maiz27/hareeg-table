import '../../../domain/classic_hareeg/game/classic_hareeg_action.dart';
import '../../../domain/classic_hareeg/models/playing_card.dart';

/// Sort modes available to the south seat hand.
enum HandSortMode {
  /// Player ordering, with no automatic sort.
  manual,

  /// Rank-major, then suit.
  byRank,

  /// Suit-major, then rank.
  bySuit,
}

/// Immutable view of the south hand after ordering and selection reconciliation.
class TableHandInteractionSnapshot {
  /// Creates a south hand interaction snapshot.
  const TableHandInteractionSnapshot({
    required this.orderedCards,
    required this.selectedIds,
    required this.selectedCardIds,
  });

  /// South hand cards in display order.
  final List<HareegCard> orderedCards;

  /// Selected physical card ids, exposed as a set for card rendering.
  final Set<String> selectedIds;

  /// Selected physical card ids in current display order.
  final List<String> selectedCardIds;

  /// Whether at least one visible card is selected.
  bool get hasSelection => selectedCardIds.isNotEmpty;
}

/// Owns the human hand's local ordering and selected-card lifecycle.
class ClassicHareegHandInteractionState {
  final List<String> _displayOrder = [];
  final Set<String> _selectedIds = <String>{};

  /// Current display-order ids.
  List<String> get displayOrder => List.unmodifiable(_displayOrder);

  /// Clears local state and seeds display order from [hand].
  void resetFromHand(List<HareegCard> hand, HandSortMode initialSort) {
    _displayOrder
      ..clear()
      ..addAll(HandSorting.sort(hand, initialSort).map((card) => card.id));
    _selectedIds.clear();
  }

  /// Returns ordered hand state, pruning stale selected ids as cards leave.
  TableHandInteractionSnapshot reconcile(List<HareegCard> hand) {
    final byId = {for (final card in hand) card.id: card};
    final ordered = <HareegCard>[];
    final keptOrder = <String>[];
    final seen = <String>{};

    for (final id in _displayOrder) {
      final card = byId[id];
      if (card != null && seen.add(id)) {
        keptOrder.add(id);
        ordered.add(card);
      }
    }

    for (final card in hand) {
      if (seen.add(card.id)) {
        keptOrder.add(card.id);
        ordered.add(card);
      }
    }

    if (!_listEquals(_displayOrder, keptOrder)) {
      _displayOrder
        ..clear()
        ..addAll(keptOrder);
    }

    _selectedIds.removeWhere((id) => !byId.containsKey(id));
    final selectedInDisplayOrder = [
      for (final card in ordered)
        if (_selectedIds.contains(card.id)) card.id,
    ];

    return TableHandInteractionSnapshot(
      orderedCards: List<HareegCard>.of(ordered),
      selectedIds: Set<String>.of(_selectedIds),
      selectedCardIds: selectedInDisplayOrder,
    );
  }

  /// Toggles [card] in the selected-card set.
  void toggleSelection(HareegCard card) {
    if (!_selectedIds.remove(card.id)) {
      _selectedIds.add(card.id);
    }
  }

  /// Moves [card] to [targetIndex] in display order.
  bool reorder(HareegCard card, int targetIndex) {
    final sourceIndex = _displayOrder.indexOf(card.id);
    if (sourceIndex < 0 || sourceIndex == targetIndex) {
      return false;
    }
    _displayOrder.removeAt(sourceIndex);
    final insertAt = targetIndex > sourceIndex ? targetIndex - 1 : targetIndex;
    _displayOrder.insert(insertAt.clamp(0, _displayOrder.length), card.id);
    return true;
  }

  /// Clears selected-card state.
  void clearSelection() {
    _selectedIds.clear();
  }

  /// Clears selection when [actionId] consumes or mutates selected cards.
  void clearSelectionForAction(String actionId) {
    if (ClassicHareegActionIds.describe(actionId).clearsSelection) {
      clearSelection();
    }
  }
}

/// Sort utility for rendering a stable hand view without mutating engine state.
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

bool _listEquals(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i += 1) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
