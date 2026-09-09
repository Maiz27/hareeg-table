import '../game/classic_hareeg_match_snapshot.dart';
import '../models/player_seat.dart';

/// Returns human-readable lines describing how [actual] diverges from
/// [expected], or an empty list when the meaningful game state matches.
///
/// Volatile fields (save timestamp, Fifty window clock readings) are ignored —
/// only reproducible game state is compared.
List<String> describeSnapshotMismatch({
  required ClassicHareegMatchSnapshot expected,
  required ClassicHareegMatchSnapshot actual,
}) {
  final lines = <String>[];

  if (expected.roundNumber != actual.roundNumber) {
    lines.add(
      'round: expected ${expected.roundNumber}, got ${actual.roundNumber}',
    );
  }
  if (expected.currentSeat != actual.currentSeat) {
    lines.add(
      'current seat: expected ${expected.currentSeat.name}, '
      'got ${actual.currentSeat.name}',
    );
  }
  if (expected.turnPhase != actual.turnPhase) {
    lines.add(
      'turn phase: expected ${expected.turnPhase.name}, '
      'got ${actual.turnPhase.name}',
    );
  }

  for (final seat in PlayerSeat.values) {
    final want = expected.scores[seat] ?? 0;
    final got = actual.scores[seat] ?? 0;
    if (want != got) {
      lines.add('score ${seat.name}: expected $want, got $got');
    }
  }

  final wantRemoved = _seatNames(expected.removedSeats);
  final gotRemoved = _seatNames(actual.removedSeats);
  if (!_listEquals(wantRemoved, gotRemoved)) {
    lines.add('removed seats: expected $wantRemoved, got $gotRemoved');
  }
  final wantActive = expected.activeSeats.map((s) => s.name).toList();
  final gotActive = actual.activeSeats.map((s) => s.name).toList();
  if (!_listEquals(wantActive, gotActive)) {
    lines.add('active seats: expected $wantActive, got $gotActive');
  }

  if (expected.pendingDiscard?.id != actual.pendingDiscard?.id) {
    lines.add(
      'pending discard: expected ${expected.pendingDiscard?.id}, '
      'got ${actual.pendingDiscard?.id}',
    );
  }

  for (final seat in PlayerSeat.values) {
    final want = _sortedIds(expected.hands[seat]?.map((c) => c.id));
    final got = _sortedIds(actual.hands[seat]?.map((c) => c.id));
    if (!_listEquals(want, got)) {
      lines.add('hand ${seat.name}: expected $want, got $got');
    }
  }

  final wantStock = _sortedIds(expected.stock.map((c) => c.id));
  final gotStock = _sortedIds(actual.stock.map((c) => c.id));
  if (!_listEquals(wantStock, gotStock)) {
    // Emit the full (sorted) contents, not just counts, so a composition
    // mismatch — same size, different cards — is visible. Matches the
    // discard-pile/hand reporting below and above.
    lines.add('stock: expected $wantStock, got $gotStock');
  }

  final wantDiscard = expected.discardPile.map((c) => c.id).toList();
  final gotDiscard = actual.discardPile.map((c) => c.id).toList();
  if (!_listEquals(wantDiscard, gotDiscard)) {
    lines.add('discard pile: expected $wantDiscard, got $gotDiscard');
  }

  for (final seat in PlayerSeat.values) {
    final want = _meldSignature(expected, seat);
    final got = _meldSignature(actual, seat);
    if (!_listEquals(want, got)) {
      lines.add('table melds ${seat.name}: expected $want, got $got');
    }
  }

  return lines;
}

List<String> _meldSignature(
  ClassicHareegMatchSnapshot snapshot,
  PlayerSeat seat,
) {
  final melds = snapshot.tableMelds[seat] ?? const [];
  return [for (final meld in melds) meld.cards.map((c) => c.id).join('+')];
}

List<String> _sortedIds(Iterable<String>? ids) {
  final list = (ids ?? const []).toList()..sort();
  return list;
}

List<String> _seatNames(List<PlayerSeat> seats) {
  return (seats.map((s) => s.name).toList())..sort();
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
