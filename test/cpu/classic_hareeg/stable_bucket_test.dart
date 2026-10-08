import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/cpu_move_plan_pipeline.dart';

/// Exact 32-bit FNV-1a, computed with BigInt so no runtime can round it.
int _referenceBucket(String value, int modulo) {
  final mask = BigInt.from(0xffffffff);
  var hash = BigInt.from(0x811c9dc5);
  for (final codeUnit in value.codeUnits) {
    hash = (hash ^ BigInt.from(codeUnit)) * BigInt.from(0x01000193) & mask;
  }
  return (hash % BigInt.from(modulo)).toInt();
}

void main() {
  test('the Fifty decision bucket is exact 32-bit FNV-1a', () {
    // The same arithmetic every runtime must reproduce: compiled JavaScript
    // used to lose low bits past 2^53 and bucket differently from native.
    const samples = [
      '',
      'a',
      'expert|east|7H.0|7H|12|3|51|2C.0,3C.0,4C.0,JK.0',
      'casual|north|-|-|0|0|71|',
      'standard|west|KS.1|KS|40|9|51|AS.0,AS.1,KD.0,QD.1,JD.0',
    ];
    for (final sample in samples) {
      expect(
        stableBucket(sample, modulo: 10000),
        _referenceBucket(sample, 10000),
        reason: sample,
      );
    }
  });
}
