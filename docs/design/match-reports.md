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

## Delivery (Sentry)

Reports reach the developer through Sentry (`sentry_flutter`). The SDK only
lives in the UI/infra layer (`lib/ui/features/match_reports/`), beside the
share/copy gateways; the report domain stays Flutter-free (ADR-0001) and the
attachment is exactly what Share/Copy would export
(`MatchReportExporter.encode` / `fileNameFor`).

- **Build-time DSN.** Sentry is configured from
  `--dart-define=SENTRY_DSN=...`. With no DSN the SDK is never started, nothing
  is transmitted, and the UI does not mention reports: no consent notice, no
  Settings > Privacy section, and the report sheet offers only Share/Copy.
- **Consent.** Opt-out, default on, disclosed: a first-run notice on the home
  menu (shown once) and a Settings > Privacy switch, both only in builds with
  a DSN.
  Nothing is sent until the notice has been answered. Opting out closes the
  SDK, so no event of any kind leaves the device; every event also re-checks
  consent in `beforeSend`.
- **Privacy.** `sendDefaultPii: false`; `beforeSend` strips user, IP, server
  name and all breadcrumbs, and rebuilds the contexts from an allowlist
  (device model/make/screen/memory, OS name and version, app version and
  build), which drops the native installation ID, locale, timezone and every
  other context. No sessions, traces, client reports, screenshots, `print` or
  Android native breadcrumbs. Native crash capture that would bypass
  `beforeSend` is off on Android: `enableNativeCrashHandling` / `anrEnabled`
  cover the JVM handler and ANRs, and the `io.sentry.ndk.enable=false`
  manifest metadata covers NDK (C/C++ signal) crashes, which are written
  natively and never reach the Dart hook. The
  Sentry project should also enable *Prevent Storing of IP Addresses*.
- **Manual.** "Report table issue" (pause) and "Export match report" (match
  over) lead with **Send report**: a Sentry event tagged `source: user_report`
  with the report attached, confirmed by a toast that says it is queued (on
  Android and iOS the SDK writes it to a native outbox; upload is
  asynchronous and waits for a connection). Share/Copy remain beneath it
  as the offline/power-user fallback, and are offered again if a send fails.
- **Automatic.** A live match registers its in-flight report with
  `LiveMatchReportSource`. It is attached when a freeze backstop trips
  (`source: auto_backstop`; trigger `livelock_forced_draw` for the engine's
  stock-exhaustion forced draw, `cpu_safety_cap` when the CPU loop stops on its
  safety cap / auto-restart cap) and to errors (`source: uncaught_error`) from
  the zone guard in `main.dart`, the SDK's `FlutterError` / platform-dispatcher
  handlers, and a CPU turn that throws (`cpu_turn_error`). Practice, replay and
  sandbox tables never capture.

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
