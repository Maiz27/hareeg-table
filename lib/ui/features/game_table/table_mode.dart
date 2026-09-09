/// Which coach, if any, a table surface shows.
///
/// One field rather than two booleans, so "the live coach and the analysis
/// coach are both on screen" is not a state this app can represent. Issue #118
/// requires those two to be mode-exclusive; making it unrepresentable is a
/// stronger guarantee than remembering to check.
enum TableCoachSurface {
  /// No coach at all.
  none,

  /// The live coaching advisor, which reads the player's full current state.
  live,

  /// The replay analysis coach, which reads only table-observable evidence.
  analysis,
}

/// What a table surface is allowed to do.
///
/// There is no public constructor. The only instances are the constants below,
/// reached through [TableMode.capabilities], so a caller cannot invent a
/// combination — a passive surface that runs CPU turns, or a review that writes
/// to history, are not values anyone can build.
///
/// `final` as well as private-constructed: without it an outside library could
/// `implements TableModeCapabilities` and invent exactly the combination the
/// private constructor exists to prevent.
final class TableModeCapabilities {
  const TableModeCapabilities._({
    required this.acceptsHumanInput,
    required this.runsCpuTurns,
    required this.coachSurface,
    required this.writesDurableMatchState,
    required this.revealsAllHands,
    required this.runsMatchProgression,
  });

  /// Whether the player can act on this surface.
  final bool acceptsHumanInput;

  /// Whether CPU seats take their turns automatically.
  final bool runsCpuTurns;

  /// Which coach this surface shows.
  final TableCoachSurface coachSurface;

  /// Whether play here reaches durable match storage.
  ///
  /// False is enforced structurally, by the surface having no repository to
  /// write to — not by a guard at each write site.
  final bool writesDurableMatchState;

  /// Whether opponent hands are rendered face up.
  final bool revealsAllHands;

  /// Whether this surface runs normal round and match progression.
  ///
  /// Separate from [writesDurableMatchState] because progression and durable
  /// effects are different things, and a branch sandbox needs the first
  /// without the second: it must cross rounds, handle elimination and reach a
  /// winner entirely in memory. Practice is the opposite case — it drives the
  /// table from a lesson script and has its own completion overlay, so the
  /// round-result pipeline would fight it.
  final bool runsMatchProgression;
}

/// The distinct kinds of table surface in the app.
///
/// The two branch rows differ in exactly one field, [
/// TableModeCapabilities.revealsAllHands]. They are separate constants rather
/// than one constant with a mutable visibility flag because visibility is a
/// capability: making it settable would reopen the representable-invalid-state
/// hole this class exists to close.
enum TableMode {
  /// A real match: the player acts, CPUs answer, progress is saved.
  live(
    TableModeCapabilities._(
      acceptsHumanInput: true,
      runsCpuTurns: true,
      coachSurface: TableCoachSurface.live,
      writesDurableMatchState: true,
      revealsAllHands: false,
      runsMatchProgression: true,
    ),
  ),

  /// A guided lesson: the player acts, but the script drives the table and
  /// nothing is written to match history.
  practice(
    TableModeCapabilities._(
      acceptsHumanInput: true,
      runsCpuTurns: false,
      coachSurface: TableCoachSurface.none,
      writesDurableMatchState: false,
      revealsAllHands: false,
      runsMatchProgression: false,
    ),
  ),

  /// Reviewing a finished match: nothing is playable, nothing advances by
  /// itself, and the only coach is the evidence-bound analysis one.
  replayReview(
    TableModeCapabilities._(
      acceptsHumanInput: false,
      runsCpuTurns: false,
      coachSurface: TableCoachSurface.analysis,
      writesDurableMatchState: false,
      revealsAllHands: false,
      runsMatchProgression: false,
    ),
  ),

  /// A branched sandbox with opponent hands hidden, exactly as in a real match.
  ///
  /// Live play in every respect that matters to the rules — the player acts,
  /// CPUs answer, rounds cross, a seat can win — but nothing durable is
  /// written, because the surface has no repository to write to.
  branchSandboxBlind(
    TableModeCapabilities._(
      acceptsHumanInput: true,
      runsCpuTurns: true,
      coachSurface: TableCoachSurface.live,
      writesDurableMatchState: false,
      revealsAllHands: false,
      runsMatchProgression: true,
    ),
  ),

  /// A branched sandbox in full-visibility study mode.
  ///
  /// Identical to [branchSandboxBlind] in every capability except that
  /// opponent hands render face up. Visibility changes rendering only: it must
  /// never reach the rules or the CPU policies.
  branchSandboxStudy(
    TableModeCapabilities._(
      acceptsHumanInput: true,
      runsCpuTurns: true,
      coachSurface: TableCoachSurface.live,
      writesDurableMatchState: false,
      revealsAllHands: true,
      runsMatchProgression: true,
    ),
  );

  const TableMode(this.capabilities);

  /// What this mode permits.
  final TableModeCapabilities capabilities;

  /// Whether this surface hosts a guided lesson.
  bool get isPractice => this == TableMode.practice;

  /// Whether this surface is a passive review.
  bool get isReview => this == TableMode.replayReview;

  /// Whether this surface is a branched sandbox, in either visibility.
  bool get isBranch =>
      this == TableMode.branchSandboxBlind ||
      this == TableMode.branchSandboxStudy;
}
