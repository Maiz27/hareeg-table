import '../../domain/classic_hareeg/models/classic_hareeg_setup.dart';

/// CPU timing and miss-chance profile.
class CpuDifficultyProfile {
  /// Creates a CPU difficulty profile.
  const CpuDifficultyProfile({
    required this.difficulty,
    required this.fiftyReactionMillis,
    required this.fiftyMissChance,
  }) : assert(fiftyReactionMillis >= 0, 'fiftyReactionMillis must be >= 0'),
       assert(
         fiftyMissChance >= 0 && fiftyMissChance <= 1,
         'fiftyMissChance must be in [0, 1]',
       );

  /// Difficulty represented by this profile.
  final CpuDifficulty difficulty;

  /// Approximate Fifty reaction delay for later UI timing.
  final int fiftyReactionMillis;

  /// Chance that a CPU misses a valid Fifty opportunity.
  final double fiftyMissChance;

  /// Returns the profile for a difficulty.
  static CpuDifficultyProfile forDifficulty(CpuDifficulty difficulty) {
    return switch (difficulty) {
      CpuDifficulty.beginner => const CpuDifficultyProfile(
        difficulty: CpuDifficulty.beginner,
        fiftyReactionMillis: 2500,
        fiftyMissChance: 0.45,
      ),
      CpuDifficulty.casual => const CpuDifficultyProfile(
        difficulty: CpuDifficulty.casual,
        fiftyReactionMillis: 1800,
        fiftyMissChance: 0.25,
      ),
      CpuDifficulty.skilled => const CpuDifficultyProfile(
        difficulty: CpuDifficulty.skilled,
        fiftyReactionMillis: 1100,
        fiftyMissChance: 0.10,
      ),
      CpuDifficulty.expert => const CpuDifficultyProfile(
        difficulty: CpuDifficulty.expert,
        fiftyReactionMillis: 650,
        fiftyMissChance: 0.03,
      ),
    };
  }
}
