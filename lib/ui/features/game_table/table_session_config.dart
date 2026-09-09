import '../../../data/persistence/match_history_repository.dart';
import '../../../data/persistence/match_repository.dart';
import '../../../domain/classic_hareeg/replay/replay_branch_seed.dart';
import '../learning/practice/practice_session.dart';
import 'table_mode.dart';

/// Where a table surface's durable writes go, if anywhere.
///
/// Sealed with two variants so "a surface that should not persist" is not a
/// flag someone can forget to check. The ephemeral variant holds **no
/// repository at all**, which is what makes a branch write unwritable rather
/// than merely skipped.
sealed class TableSessionPersistence {
  const TableSessionPersistence();
}

/// Durable storage for a real match.
final class DurableTablePersistence extends TableSessionPersistence {
  /// Creates durable persistence over the two real repositories.
  const DurableTablePersistence({
    required this.matchRepository,
    required this.historyRepository,
  });

  /// Active-match storage.
  final MatchRepository matchRepository;

  /// Completed-match history.
  final MatchHistoryRepository historyRepository;
}

/// No durable storage of any kind.
///
/// Deliberately fieldless. A caller holding this cannot reach a repository,
/// so the branch sandbox and guided practice cannot write even by mistake —
/// there is nothing to write to.
final class EphemeralTablePersistence extends TableSessionPersistence {
  /// Creates the no-storage variant.
  const EphemeralTablePersistence();
}

/// Which hands a branch sandbox shows.
enum BranchVisibility {
  /// Opponent hands stay hidden, exactly as in a real match.
  blind,

  /// Opponent hands are face up for study.
  study,
}

/// One valid table session: its mode and its persistence, together.
///
/// The constructor is private and the only ways in are the three factories
/// below, each of which **derives** both the mode and the persistence. A
/// caller cannot pair a branch with durable storage, or live play with no
/// storage, because no route accepts those as independent inputs. That is a
/// stronger guarantee than checking the pair after the fact, and it is the
/// property the build's architecture criterion asks for.
///
/// **`final`, not a plain class.** A private constructor stops an outside
/// library from *extending* this type, and stops nothing else: `implements
/// TableSessionConfig` was enough to hand back `branchSandboxBlind` from
/// `mode` and a `DurableTablePersistence` from `persistence`, and the analyzer
/// accepted it. `final` closes extension and implementation together, so the
/// forbidden pairing is a compile error rather than a convention.
final class TableSessionConfig {
  const TableSessionConfig._({
    required this.mode,
    required this.persistence,
    this.practiceSession,
    this.branchSeed,
    this.branchCoachEligible = false,
  });

  /// A real match, with durable storage.
  factory TableSessionConfig.live({
    required MatchRepository matchRepository,
    required MatchHistoryRepository historyRepository,
  }) {
    return TableSessionConfig._(
      mode: TableMode.live,
      persistence: DurableTablePersistence(
        matchRepository: matchRepository,
        historyRepository: historyRepository,
      ),
    );
  }

  /// A guided lesson. Nothing durable, and no match progression.
  factory TableSessionConfig.practice(PracticeSession session) {
    return TableSessionConfig._(
      mode: TableMode.practice,
      persistence: const EphemeralTablePersistence(),
      practiceSession: session,
    );
  }

  /// A branched sandbox seeded from a replay frame.
  ///
  /// [coachEligible] comes from the archived match's `coachWasEnabled` and
  /// nothing else: a branch cannot grant coaching the original match never had.
  factory TableSessionConfig.branch({
    required ReplayBranchSeed seed,
    required BranchVisibility visibility,
    required bool coachEligible,
  }) {
    return TableSessionConfig._(
      mode: switch (visibility) {
        BranchVisibility.blind => TableMode.branchSandboxBlind,
        BranchVisibility.study => TableMode.branchSandboxStudy,
      },
      persistence: const EphemeralTablePersistence(),
      branchSeed: seed,
      branchCoachEligible: coachEligible,
    );
  }

  /// What this surface is.
  final TableMode mode;

  /// Where its writes go, if anywhere.
  final TableSessionPersistence persistence;

  /// The lesson driving the table, when this is practice.
  final PracticeSession? practiceSession;

  /// The replay frame this sandbox branched from, when this is a branch.
  final ReplayBranchSeed? branchSeed;

  /// Whether the archived match had coaching available.
  final bool branchCoachEligible;

  /// Whether normal round and match progression runs.
  ///
  /// Read from [mode] rather than stored, so the enum row is the single
  /// source of truth and the two cannot drift apart.
  bool get runsMatchProgression => mode.capabilities.runsMatchProgression;

  /// Whether this surface writes durable match state.
  bool get writesDurableMatchState => mode.capabilities.writesDurableMatchState;

  /// Durable repositories, or null on an ephemeral surface.
  DurableTablePersistence? get durable => switch (persistence) {
    DurableTablePersistence(:final matchRepository, :final historyRepository) =>
      DurableTablePersistence(
        matchRepository: matchRepository,
        historyRepository: historyRepository,
      ),
    EphemeralTablePersistence() => null,
  };
}
