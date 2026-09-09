/// Versioned deal-seed arithmetic. New games use exact 32-bit multiplication.
/// The second mode exists only to read/resume recordings made by older web
/// builds, whose double-precision multiplication rounded the low bits.
enum RoundSeedAlgorithm { exact32, legacyWeb }

int fnvMultiply32(int value) {
  // Both partial products stay below 2^53, including on compiled JavaScript.
  final low = (value & 0xffff) * 0x0193;
  final high = ((value >>> 16) * 0x0193 + (value & 0xffff) * 0x0100) & 0xffff;
  return (low + (high << 16)) & 0xffffffff;
}

int legacyWebFnvMultiply(int value) =>
    (value.toDouble() * 0x01000193.toDouble()).toInt() & 0xffffffff;

const legacyLocalRoundSeedAlgorithm =
    bool.fromEnvironment('dart.library.js_interop')
    ? RoundSeedAlgorithm.legacyWeb
    : RoundSeedAlgorithm.exact32;
