# Branch-and-play sandbox

A player reviewing a finished match can take the south seat from the frame they
are looking at and play it out against live CPUs. Nothing that happens there is
saved. This document is the contract for that: what a sandbox is, why it cannot
write, and which parts of it are rendering rather than rules.

## The one guarantee

**A branch sandbox holds no durable storage, so it cannot write.**

Not "does not write". Not "checks a flag before writing". It has nothing to
write to.

The mechanism is `TableSessionConfig` (`lib/ui/features/game_table/table_session_config.dart`).
It has a private constructor and exactly three factories, each of which derives
both the mode and the persistence:

| Factory | Mode | Persistence |
| --- | --- | --- |
| `TableSessionConfig.live` | `live` | `DurableTablePersistence` (both repositories) |
| `TableSessionConfig.practice` | `practice` | `EphemeralTablePersistence` |
| `TableSessionConfig.branch` | `branchSandboxBlind` / `branchSandboxStudy` | `EphemeralTablePersistence` |

Neither is a parameter. There is no route by which a caller pairs a branch with
a repository, so `branch + durable` is not a value that exists.

`EphemeralTablePersistence` is deliberately **fieldless**. A caller holding one
cannot reach a store, which is what turns "must not write" from a rule someone
has to remember into a thing the type system will not express.

`GameTableScreen._applyDurableEffect` switches over the two variants with no
`default`. The durable arm receives its repositories **as arguments** and passes
them down to `_checkpointFor` and `_archiveCompletedMatch`; the ephemeral arm
has none in scope. The write methods are not callable there.

## Progression is not persistence

They used to be one method, which is why "does this table cross rounds?" and
"does this table save?" were the same question. A sandbox needs the first
without the second: it deals the next round, eliminates seats and reaches a
winner exactly as a real match does.

`TableModeCapabilities.runsMatchProgression` says which surfaces progress:

| Mode | Progression | Durable writes |
| --- | --- | --- |
| `live` | yes | yes |
| `practice` | no | no |
| `replayReview` | no | no |
| `branchSandboxBlind` | **yes** | no |
| `branchSandboxStudy` | **yes** | no |

Practice is the opposite case from a sandbox: it drives the table from a lesson
script and owns its own completion overlay, so the round-result pipeline would
fight it.

`GameTableScreen._advanceProgression()` computes the round result, the
next-round snapshot and the presentation, and touches no storage.
`_applyDurableEffect(plan)` is the only thing that does.

## Seeding and the branch clock

`ReplayBranchSeed` (`lib/domain/classic_hareeg/replay/replay_branch_seed.dart`)
is pure Dart: no Flutter, no repositories, no wall clock. It rebases the
archived frame onto the instant the sandbox starts.

**The Fifty window is rebased by preserving elapsed time, not remaining time.**
The two look equivalent and are not. Every instant inside the two-second
post-expiry grace reports `remaining == 0`, so reconstructing the origin from
the remaining seconds would hand the window a fresh, full grace period — a
window one second from vanishing would come back with two. Shifting the
original elapsed duration keeps remaining time, grace position and the
past-grace case all correct without special-casing any of them.

The rebase round-trips through the snapshot's own codec rather than re-listing
its constructor fields by hand, so a field added later cannot be silently
dropped.

`ReplayBranchSession` holds the run: the seed, the archived coach eligibility,
the session-only coach state, and whether anything has actually been applied.
`restart` returns a **new** session from the same frame against a fresh clock,
so "restart resets divergence and the coach" is a property of the type rather
than a checklist the host has to remember.

## Refusal

Branching is unavailable on a frame the match was already decided at:
`ReplayBranchSeed.refusalFor` returns `matchAlreadyComplete`, and
`fromFrame` returns null. The replay screen asks the domain rather than
deciding for itself, so the affordance and the seed builder cannot disagree
about which frames are playable. A refused frame keeps its control, disabled,
with a label that says why.

## Divergence and exit

**Divergence is armed by an applied action, by any seat.** Not by pointer
activity: opening a sandbox, looking at it and leaving changes nothing and is
not worth a confirmation. A CPU turn that ran on mount arms it just as a south
move does — the sandbox has left its historical line either way.

There is **one exit policy**, reached by four routes:

| Route | Where it enters |
| --- | --- |
| Pause → leave | `_BranchPauseOverlay` |
| In-app exit control | the `branch-exit` chrome button |
| Android system Back | `PopScope` |
| Browser Back | `PopScope` |

All four call `GameTableScreen.onSandboxExit`, and `BranchSandboxHost` decides
once: no divergence, leave immediately; divergence, raise a localized
confirmation first. The two runtime substrates each execute the route they can
— Android system Back on the device, browser Back on the web — and neither is
asked to prove the other.

## What a sandbox does not offer

At every point, not only at completion, a sandbox has no archive, no export or
report, no share, no normal rematch, and no persistent-preference control.

This is structural rather than guarded. A sandbox does not build the live pause
overlay at all — every settings row on it is an `onPreferencesChanged` call —
and it does not build `MatchOverOverlay`, whose rematch would deal a fresh real
match and whose export would hand out a report for a game that never happened.
It builds `_BranchPauseOverlay` and `_BranchCompletionOverlay` instead, which
offer what a sandbox actually has:

- **Paused:** resume, the session-only coach toggle, restart from branch point,
  leave.
- **Completed:** return to replay, restart from branch point. Nothing else.

## The coach

`summary.coachWasEnabled` is the **only** eligibility source. A sandbox cannot
grant coaching the archived match never had, and the way that is guaranteed is
that an ineligible sandbox has no toggle at all — absent, not present-and-off.

An eligible sandbox starts with the coach on and exposes a session-only toggle.
Toggling changes local state and nothing else: the sandbox has no preferences
repository, so there is no path from that switch to a stored value. A restart
returns the coach to the archived state, not the toggled one.

Analysis and live coaching are mode-exclusive by construction:
`TableCoachSurface` is one field, so "both coaches on screen" is not a state
this app can represent. A branch is never `analysis`; review is never `live`.

## Visibility is rendering, and only rendering

Blind and study differ in exactly one capability, `revealsAllHands`. They are
separate enum constants rather than one constant with a settable flag, because
a settable flag would reopen the representable-invalid-state hole the
capability table exists to close.

Opponent cards are drawn in one place — `_CardBackStack` in
`opponent_seat_rails.dart`, which both the north rail and the two side rails
funnel through — so study rendering is a single additive, default-empty
`faceUpCards` parameter rather than three parallel changes that could disagree.
Left empty, the real identities never enter the widget tree at all: not the
painter, not semantics, not a key.

Study mode also offers a **read-only** expansion of one hand. It opens a sheet
of card views with no action affordance of any kind, and the seat it shows is
not South, so there is no route by which viewing a hand acts on it.

The rendering-only claim is tested by playing the same scripted South actions
in both visibilities, across a round crossing, and comparing the board after
every step. If visibility reached the rules or a CPU policy, the two runs would
diverge at the first step where a hidden hand mattered.

## South only

North, east and west are never controllable and never actionable, in either
visibility. The table publishes no per-seat action handler for them; its whole
action surface is south's hand, the discard and the meld affordances. A
CPU-current seed auto-runs the CPU seats until South can act, and South input
stays locked while they do.

## Where the code lives

| Concern | File |
| --- | --- |
| Session identity and persistence | `lib/ui/features/game_table/table_session_config.dart` |
| Mode capabilities | `lib/ui/features/game_table/table_mode.dart` |
| Seeding and clock rebasing | `lib/domain/classic_hareeg/replay/replay_branch_seed.dart` |
| Run state: divergence, coach, restart | `lib/domain/classic_hareeg/replay/replay_branch_session.dart` |
| Visibility chooser | `lib/ui/features/replay/widgets/branch_entry_sheet.dart` |
| Host: exit policy, restart, confirmation | `lib/ui/features/replay/views/branch_sandbox_host.dart` |
| Progression / durable-effect split, sandbox chrome | `lib/ui/features/game_table/views/game_table_screen.dart` |
| Face-up rendering | `lib/ui/features/game_table/widgets/opponent_seat_rails.dart` |
