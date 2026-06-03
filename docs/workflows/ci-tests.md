# CI Test Runs

How the `Flutter CI` workflow (`.github/workflows/flutter-ci.yml`) runs the test
suite, and what coverage a pull request gets versus `main` and the nightly run.

There is one job — `flutter analyze` then `flutter test` — on a GitHub-hosted
`ubuntu-latest` runner. The same step runs on every trigger; two things change
its behaviour: the **concurrency** flag and the **`HAREEG_FULL_SWEEP`** env var.

## Triggers

The workflow runs on three events:

- `pull_request` — every push to a branch with an open PR.
- `push` to `main` — merges and direct pushes.
- `schedule` — nightly at `03:00 UTC`.

A scheduled run always uses the workflow file on the default branch, so the
nightly run only reflects changes once they are merged to `main`.

## Concurrency

The test step runs `flutter test --concurrency=$(nproc)`.

`flutter test` defaults its suite concurrency to `numberOfProcessors ~/ 2`
(so **2** on a 4-vCPU runner), which leaves half the cores idle and serialises
the heavy full-game invariant sweep. Pinning `--concurrency=$(nproc)` uses every
vCPU, and `$(nproc)` auto-adapts if the runner spec changes. The win is bounded
by *physical* cores — the runner's four "vCPUs" are ~two hyperthreaded cores —
so concurrency alone is a modest speedup; the seed tiering below does the rest.

## Invariant-sweep seed tiering

The Family A invariant sweep (see
[Classic Hareeg PRD coverage](../testing/classic-hareeg-prd-coverage.md)) is the
suite's long pole. Its **seed** axis is tiered by the `HAREEG_FULL_SWEEP` env
var, which the workflow sets for `push` and `schedule` events but leaves unset
for `pull_request`:

```yaml
env:
  HAREEG_FULL_SWEEP: ${{ (github.event_name == 'push' || github.event_name == 'schedule') && '1' || '' }}
```

| Event | `HAREEG_FULL_SWEEP` | Sweep seeds |
| --- | --- | --- |
| Pull request | unset | reduced: casual `[1, 3]`, strategic `[1]` |
| Push to `main` | `1` | full: casual `[1, 2, 3, 5, 7]`, strategic `[1, 2, 3]` |
| Nightly schedule | `1` | full (same as push) |

Only the **seed** axis is reduced on PRs. Every other dimension — strictness
tier, joker count `[0, 2, 4]`, and CPU difficulty — runs in full on every PR, so
structural regressions still surface there. Seeds are loop iterations inside the
eight sweep `test()` blocks, not separate test cases, so the reported test count
is identical (**913**) in both modes; only the per-test work changes.

The toggle lives in `test/scenario/full_game_invariant_sweep.dart`
(`fullSweepSeeds`).

## Coverage guarantee and the tradeoff

Reducing PR seed coverage is a deliberate speed/coverage tradeoff. This harness
has caught seed-specific engine bugs, so the **full** seed matrix is preserved
off the PR path:

- it runs on **every push to `main`** (i.e. at merge), and
- again **every night** at `03:00 UTC`.

So a seed-specific regression that a PR's reduced set misses is caught at merge
or within ~24h — not lost. If a full run goes red, the invariant checker's
failure message names the exact combination, e.g.
`[seed=5 strictness=table difficulty=expert decks=1 jokers=2]` plus the round and
action, so it reproduces directly.

## Running it locally

A plain `flutter test` locally matches **PR mode** (reduced seeds — fast). To
reproduce a full run:

```bash
HAREEG_FULL_SWEEP=1 flutter test            # bash
$env:HAREEG_FULL_SWEEP = "1"; flutter test  # PowerShell
```

You can pass `--concurrency=$(nproc)` (or a fixed value) to mirror CI, though it
matters less on a developer machine with more cores.

## Reading the timings

The `Test` step on a PR runs materially faster than a full run, but GitHub
runners carry roughly ±50s of run-to-run noise (shared hardware, cache warmth).
Compare durations over a few runs rather than trusting any single number, and
expect push-to-`main`/nightly runs to be slower than PRs by design.
