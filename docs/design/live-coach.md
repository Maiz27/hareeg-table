# Live Coach (Coaching tier)

The live coach is the proactive hint layer on the Coaching strictness tier.
It reuses the Expert CPU brain (`CpuObservation`, `MeldPartitionEnumerator`,
`ExpertCpuMovePlanner`, `OpponentThreatProfile`) to classify the human
player's situation into structured, localization-free insights, and the UI
maps the selected insight to a localized callout plus card rings.

Guided practice (`guided-practice.md`) teaches mechanics statically in
lessons; the live coach points at *this board's* instance of those concepts
during real play. It never auto-plays, never sees hidden information (visible
state plus attributed pile history only), and never advises an action the
legality layer blocks.

## Pipeline

```
ClassicHareegGameController
  → ClassicHareegCoachingAdvisor.adviseFor(controller, seat)   (pure)
  → List<CoachingInsight> (priority-sorted)
  → CoachInsightFlow.select(...)                               (UI state, anti-spam)
  → CoachHintPresenter.present(...)                            (EN/AR copy, rings)
  → CoachOverlay + CoachHighlighting
```

- The **advisor** is a pure function of controller state + seat: no mutation,
  no I/O, no time, no cross-turn memory. It re-emits every applicable insight
  on every call.
- The **flow** (`CoachInsightFlow`, one instance per table screen) owns
  cross-turn surfacing policy: per-turn guidance always surfaces; stage
  banners show once per round each (see below).
- The screen memoizes the advisor on a cheap situation signature and only
  computes at all when the persistent gates hold (coaching tier, tips toggle,
  not practice, human turn). Transient gates (overlays, card flights) hide
  the display but never freeze the data (compute-then-gate, the stale-hint
  fix).

## CPU-first contract

The coach narrates the brain's decision; it never re-derives its own. Bespoke
re-detection diverged from the brain and produced the HT-40 playtest bugs.
Concretely:

- Cover advice surfaces only when the Expert plan's move IS a cover.
- The play-meld hint presents the Expert plan's exact meld when the plan melds.
- The discard floor is the Expert plan's own discard pick.
- When the brain *declines* a visible finish (`holdsNormalFinishForFifty`),
  the coach explains the hold (`fiftyHold`) instead of contradicting it with
  a bare "you can finish".
- Hold-back warnings narrate `OpponentThreatProfile.primaryThreatFor` — the
  same signals the Expert discard comparator weighs.

The coach's strategic ceiling is deliberately the CPU's ceiling. Make the
brain smarter first; the coach inherits it.

## Priority ladder

Declared (descending, test-pinned) on `CoachingInsightCategory`:

| Band | Categories |
|---|---|
| Win / window (1000–860) | finishAvailable, fiftyAvailable, takeAndFinish, fiftyHold |
| Plays (800–400) | openNow, playMeld, pickupCompletesMeld, playCover, jokerAdvice |
| Stage banners (380–360) | scorePosture, endgameStockLow, opponentCloseToFinish, benchmarkAlert, baitDiscard |
| Floors (350–200) | discardSuggestion, drawStock, openingProgress |

Only one insight is presented at a time; secondary content rides on the top
hint (opening numbers fold into the draw hint, a lay-off cover folds into the
meld hint, the hold-back warning folds into the discard hints).

## Hold-back warning (the "collecting" fix)

The old standalone `defensiveDiscard` insight fired on a round-long,
suit-broad boolean (one pickup of the 9♣ poisoned every club all round,
regardless of opponent state) and outranked opening guidance — the playtest
"fixation" complaint. It is retired. The replacement rides on the
discard-carrying hints and fires only when **it changes the decision**:

- the NAIVE throw (lowest keep-score — what a learner would likely shed) is
  materially threatened, AND
- the recommended throw is safe (when everything is threatened there is no
  warning — advice the player cannot act on is noise).

Threat signals come from the shared `OpponentThreatProfile`: recent pickups
(last 6) not since melded onto that opponent's table, from opponents still
building (unopened, or holding ≥ 4 cards), matching by rank or by suit at
adjacent rank (± 2). Run-end fits on visible opponent runs rank above
collecting tells, though on the Coaching tier such cards are cover-blocked
from plain discard, so that branch exists for brain parity rather than
day-to-day hints.

## Stage banners

Posture teaching the brain already weighs but per-turn hints never said:

- `scorePosture` — own score ≥ 25 (play safe) or an opponent ≥ 28 (pressing
  finishes them).
- `endgameStockLow` — stock ≤ 8, the Expert thin-stock threshold.
- `opponentCloseToFinish` — an opened opponent at ≤ 3 cards (also exactly the
  state whose stale pickup tells the hold-back warning now ignores).
- `benchmarkAlert` — an unopened seat facing a raised, foreign benchmark;
  re-alerts per raise.
- `baitDiscard` — a pickup that fits the hand but cannot reach the opening
  requirement.

`CoachInsightFlow` shows each at most once per round (keyed per
category/subject), for the turn it first appears in, then yields to the
guidance below it.

## Fifty teaching

- `fiftyAvailable` requires the claim to be live on the legal surface — on
  the Coaching tier the engine only advertises a claim after validating a
  full finish proof, so a surfaced claim is always genuinely claimable. The
  window object outlives its timer, so claimant-only gating used to advise
  impossible claims.
- When the window lapses, `takeAndFinish` takes over: taking the discard
  still finishes the hand for the normal −1 (the claim-vs-take distinction
  that confused real players). The screen's memo key carries a claim-liveness
  bit so the handover happens the moment the timer lapses.
- `fiftyHold` explains the Expert posture of holding a finish for a Fifty
  (deep stock, heavy hand, someone at high-risk score) — previously the coach
  silently showed a discard under a visible finish, which read as a bug.

## Known divergences (deliberate)

- `openNow` shows the max-value partition rather than Expert's 70–80
  first-opener band: "open fat as first opener" is the same defensible
  lesson, and ringing cards the copy's number does not match would confuse
  more than the band nuance teaches.
- Joker-identity choice in the picker and round-over teach-back lines are
  future candidates, not yet implemented.

## Tests

- `test/cpu/classic_hareeg/coaching/classic_hareeg_coaching_advisor_test.dart`
  — per-category behaviour, hold-back gating, ladder pinning.
- `test/ui/features/game_table/coach/coach_hint_presenter_test.dart` — copy,
  zones, rings, situation keys.
- `test/ui/features/game_table/coach/coach_insight_flow_test.dart` —
  once-per-round banner policy.
- `test/scenario/full_game_coaching_advisor_sweep_test.dart` — the advisor
  against every reachable decision state of full driven matches: never
  throws, never silent on an actionable turn, never fixated on one category.
