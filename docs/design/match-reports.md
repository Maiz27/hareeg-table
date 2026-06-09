# Match Reports

Match reports are a support/debugging export, not a public replay viewer. A
report captures enough structured state to inspect a match and — when a
transcript is present — deterministically reproduce the path that led to it.

## What a report contains

A `ClassicHareegMatchReport` serializes to versioned JSON
(`classic_hareeg_match_report`, schema v1) and carries:

- App/build metadata, platform, and a UTC timestamp.
- Setup, seed, round number, current seat, turn phase, and scores.
- The current (active) or final (completed) match snapshot.
- An optional **diagnostic log** — a capped, structured event stream.
- An optional **action transcript** — a replayable, domain-level action list.

Reports deliberately exclude preferences, locale, player names, and any other
user-entered data, so they can be attached to a bug report safely. New fields
are added additively under schema v1; older tooling ignores unknown fields and
unsupported versions fail with a clear `FormatException`.

## Diagnostic log

`MatchDiagnosticLog` is a capped ring buffer (default 200 events) of
`MatchDiagnosticEvent`s. Each event has a monotonic `order`, a `category`
(`rules`, `scoring`, `fifty`, `finish`, `persistence`, `ai`, `coach`), a stable
`type`, the seat/round/phase context, and a small JSON payload of domain ids.
When the cap is exceeded the oldest events are dropped and `droppedCount`
records how many, so tooling never mistakes a truncated log for a full one.

The controller records rules/scoring/fifty/finish/ai events at the single
`applyAction` seam; the UI records coach hints and save/load/resume boundaries
through `MatchRecorder`.

## Action transcript

`MatchActionTranscript` pairs a base snapshot (the match state before the first
recorded action) with the ordered domain actions applied from there. Player and
CPU actions use the identical entry shape — seat, round, phase, and the raw
`actionId` from the rules-engine seam. No UI gestures, coordinates, or animation
timing are recorded. The transcript spans the whole match: one `MatchRecorder`
is handed to each round's controller, and replay crosses round boundaries via
the deterministic next-round deal.

## Replaying a report

`replayMatchReport` (in `match_report_replay.dart`) restores the transcript's
base snapshot, applies every action, and diffs the reconstructed state against
the reported snapshot, returning a `matched` / `mismatch` / `noTranscript`
result with a human-readable mismatch summary.

The developer CLI loads a report file, validates it, prints the snapshot
summary, and replays the transcript when present:

```sh
dart run tools/match_report_replay.dart path/to/hareeg-match-report-*.json
```

Exit codes: `0` matched / inspected, `1` mismatch, `2` unreadable or invalid.

Committed fixtures live under `test/fixtures/reports/` and are exercised by
`match_report_fixture_test.dart`. A confirmed reproduction can graduate into a
regression fixture there.
