import '../models/playing_card.dart';

/// True when [left] and [right] hold the same physical cards regardless of
/// order — compared by [HareegCard.id], which uniquely identifies a deck copy.
///
/// Lives outside any specific module because three call sites (controller,
/// turn journal, turn checkpoint) all need it for matching meld instances
/// across retraction / projection paths.
bool samePhysicalCards(List<HareegCard> left, List<HareegCard> right) {
  if (left.length != right.length) {
    return false;
  }
  final leftIds = left.map((card) => card.id).toList()..sort();
  final rightIds = right.map((card) => card.id).toList()..sort();
  for (var index = 0; index < leftIds.length; index += 1) {
    if (leftIds[index] != rightIds[index]) {
      return false;
    }
  }
  return true;
}
