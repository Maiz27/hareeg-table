# Match statistics

How the numbers on the statistics screen are computed, and the two rules that
decide what the player is allowed to be told.

Source: `lib/domain/classic_hareeg/history/match_statistics.dart` (pure) and
`lib/ui/features/history/match_statistics_format.dart` (presentation only).

## Inputs

Everything is derived from stored `MatchHistorySummary` values. No replay record
is read on either the history or statistics path — listing a hundred matches
must not read a hundred replay files. The history screen and the statistics
screen call the same `listSummaries()` and share its outcome handling.

## The two rules

### 1. Unavailable is not zero

Every rate and average is `double?`. A `null` means the figure has no
denominator, and it renders as `—`. It never renders as `0.0%`, because a
rendered zero claims a measurement that was never taken.

The distinction matters most for the Fifty success rate: a player who never
attempted a Fifty has no success rate at all, which is a different statement
from a player who attempted ten and succeeded at none.

### 2. Unknown counters are not measured zeros

`MatchHistorySummary.fiftyCountersComplete` is false for a match migrated from a
legacy save that predates Fifty counting. Its counters read as zero, and that
zero means **unknown**.

So the Fifty metrics are computed only over summaries where the flag is true.
That set is `fiftyMeasuredMatches`, and it is the denominator for both Fifty
rates. Counting legacy matches in the denominator would report the player as
measured and found never to have tried.

This is a deliberate departure from the literal wording of the PRD, which named
games played as the denominator. The departure was raised and approved rather
than assumed.

Because the denominator can differ from games played, **every displayed slice
discloses its own measured count when the two differ** — overall, and
independently inside every difficulty, strictness, and coaching group. A single
group can hold every unmeasured match while the rest of the screen is fully
measured, so a screen-level banner would attach the caveat to the wrong numbers.

## Formulas

All figures are from the human seat's perspective. None is computed for a CPU
seat.

| Metric | Numerator | Denominator | Null when |
| --- | --- | --- | --- |
| Win rate | matches whose winner is south | games played | no matches |
| Average placement | sum of valid `southPlacement` values | matches with a valid placement (`knownPlacements`) | no valid placement |
| Fifty attempt rate | measured matches with at least one south attempt | `fiftyMeasuredMatches` | nothing measured |
| Fifty success rate | south successes across measured matches | south attempts across measured matches | no attempts |
| Average scoring margin | sum of per-match margins | matches that have one | no match has one |

### Scoring margin

For one match: the **lowest** opponent final score minus south's final score.

A lower score is better in Classic Hareeg, so the lowest opponent score is the
strongest one to measure against, and a positive margin means south finished
ahead. The screen states that direction beside the number, because a signed
figure with no stated direction is not interpretable.

A summary with no opponent score contributes to games played but not to the
margin, and `marginMatches` records how many matches the average covers.

## Groupings

Three, all independent facts about a match:

- **CPU difficulty** — `setup.cpuDifficulty`, in declared enum order.
- **Table strictness** — `setup.tableStrictness`, in declared enum order.
- **Coach enabled** — `coachWasEnabled`, false before true.

Strictness and the coach flag are **not** substitutes for one another. A player
can run a Strict table with coaching on, or a Coaching-tier table with the coach
switched off, so neither grouping answers the other's question.

A group appears only when at least one match falls in it. An absent group and a
zero-filled one are different statements: a zero-filled Expert group would be
indistinguishable from having played Expert and lost every time.

Each grouping is a partition. Group counts sum to the overall count, and each
group's metrics equal the same computation run over the filtered subset — which
is what catches a summary routed to the wrong key.

## Formatting

One place turns a `double` into text, so a raw repeating decimal cannot reach a
player from anywhere else.

| Kind | Rule | Example |
| --- | --- | --- |
| Rate | `value * 100`, exactly one decimal, `%` suffix | `1/3` → `33.3%` |
| Average | exactly one decimal, no suffix | `2.0` |
| Margin | exactly one decimal, explicit sign for non-zero | `+4.5`, `-4.5`, `0.0` |
| Unavailable | the marker, never a number | `—` |

Zero carries no sign — `+0.0` would imply an edge that is not there — and a
negative value that rounds to zero renders `0.0` rather than `-0.0`, since a
rounding artefact should not read as a loss.

Non-finite values render as unavailable. They cannot arise from the domain
layer, where every metric is a ratio of ints behind a zero-denominator guard,
but `toStringAsFixed` renders `NaN` and `Infinity` literally, so the seam is
closed rather than argued about.

## Low data

Below three matches the screen shows the figures and an explicit note naming the
sample size. The numbers are real; they just move a lot, and saying so is more
useful than hiding them.

## What lives where

- Aggregation is pure Dart under `lib/domain/`, per ADR 0001, and
  `test/lint/domain_purity_test.dart` keeps it that way — no Flutter import, and
  no import that resolves into `lib/ui`, `lib/app`, or `lib/l10n`.
- Formatting is pure Dart under `lib/ui/features/history/`, unit-tested without
  widgets.
- The screens render. They perform no arithmetic, and the screen test takes its
  expected values from the domain computation so a formula that migrated into a
  widget would disagree rather than agree.
