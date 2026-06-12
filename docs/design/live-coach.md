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

```text
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
- The **flow** (`CoachInsightFlow`, one instance per match — replaced on
  rematch, since its once-per-round keys embed the restarting round number)
  owns cross-turn surfacing policy: per-turn guidance always surfaces; stage
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

- Cover advice surfaces only when the Expert plan's move IS a cover. The
  pipeline tries every legal cover and skips only the held ones (keying the
  branch off the first advertised cover made the move order-dependent — a
  guarded joker cover listed first blinded the seat to a freshly drawn
  lay-off for a full turn).
- When the brain deliberately HOLDS a legal cover (joker guard, Fifty
  development, own-run end — `ExpertCpuMovePlanner.coverHoldReasonFor`), the
  discard hint NARRATES the hold: the cover and its target meld ring as a
  keep group with "you could lay that off, but hold it because…" copy.
  Silence about a visibly coverable card reads as coach blindness, not
  strategy.
- The play-meld hint presents the Expert plan's exact meld when the plan
  melds, and only folds a lay-off cover in when the brain is not holding it
  for Fifty development.
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
| Plays (800–550) | openNow, jokerAdvice, playMeld, pickupCompletesMeld, playCover |
| Stage banners (380–360) | scorePosture, endgameStockLow, opponentCloseToFinish, benchmarkAlert, baitDiscard |
| Floors (350–200) | discardSuggestion, drawStock, openingProgress |

`jokerAdvice` sits ABOVE `playMeld` deliberately: a joker swap is a free
action that must come first — the meld may consume the very card the swap
needs (melding three natural 8s burns the 8♣ that could reclaim a table
joker), while swapping first keeps the same meld playable via the freed
joker. When the swap card anchors a playable meld, that meld rides on the
swap hint as a ring group with "swap first" copy. The CPU pipeline plays in
the same order (replacement before melds), and every tier now swaps eagerly —
the old Expert delay-until-finish lost the swap whenever the natural card got
consumed, and a multi-deck twin holder could steal it.

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
  (deep stock, heavy hand, a worthwhile payoff) — previously the coach
  silently showed a discard under a visible finish, which read as a bug. The
  payoff is aimable at exactly one seat: a Fifty's +3 lands on whoever's
  discard the claim takes, i.e. the active seat immediately BEFORE the
  claimant (`ExpertCpuMovePlanner.fiftyPunishTarget`). The hold fires when
  the claimant or that seat is at high-risk score — never for a high scorer
  elsewhere at the table (a playtest hint implied the wrong seat would pay) —
  and the hint names that seat plus the hold-sustaining throw, taken from the
  Expert plan's legal discard so a cover-blocked card is never recommended.

## Finish detection (engine-plan based)

`finishAvailable` runs on the engine's own `ClassicHareegFinishPlanner` (the
same exact-cover search behind Fifty proofs), not a melds-only partition
scan. The coach therefore sees every finish the rules accept:

- cover-routed wins (hand cards laid onto existing table melds), including
  the playtest gap: a 3-card set + a cover + the final discard read as "you
  can lay down a meld" before;
- the final-discard exemption — the closing throw may be a card that is
  cover-blocked as a plain discard;
- unopened-seat routes: the melds-only perfect hand (exempt from the opening
  requirement) and the cover-routed opening-finish whose fresh melds clear
  it. Both set `bypassesOpening` so the copy teaches the bypass.

The hint names the plan's final discard (rung warm) and rings each fresh
meld and each cover-with-its-target-meld as its own group.

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
