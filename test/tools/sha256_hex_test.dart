import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../support/sha256_hex.dart';

void main() {
  // The oracle checks that pin byte-for-byte fixtures are only as good as the
  // digest they compare with, so the digest is checked against the standard's
  // own test vectors.
  test('the digest routine itself is correct', () {
    expect(
      sha256Hex(utf8.encode('abc')),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    expect(
      sha256Hex(const <int>[]),
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
  });
}
