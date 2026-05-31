# Opponents tier ladder — full behavior contract

Status: Shipped (Skilled/Expert planners implemented in
`lib/cpu/classic_hareeg/skilled_cpu_move_planner.dart` and
`expert_cpu_move_planner.dart`; Beginner/Casual columns in
`priority_cpu_move_planner.dart`). This is the complete contract for what each `CpuDifficulty`
tier (Beginner / Casual / Skilled / Expert) means at runtime. Rows 1-9 are from
the Hareeg CPU research pass; rows 10-11 (Fifty offensive posture, Score-aware
risk) were added after the user flagged the missing Fifty-as-offense dimension.

All behaviors are implementable against the `CpuObservation` interface
(`docs/design/cpu-observation.md`), with discard memory coming from
`DiscardHistoryView` and meld choices from `MeldPartitionView`.

## Tier behaviors

| Decision | Beginner | Casual | Skilled | Expert |
|---|---|---|---|---|
| **1. Meld composition** | First legal partition | First legal partition; prefer 3-4 card melds on ties | Enumerate up to N partitions via `MeldPartitionEnumerator`; split runs of 5+ into 3+3 / 3+4 / 4+3 | All partitions; score by cover-surface count + future-replace-immunity − pips left in hand |
| **2. Opening fatness** | Open at first legal value | Open at first legal value; never push past `requirement + 5` | Min-open unless already benchmark owner; otherwise +0-10 over requirement | Push benchmark to 70-80 when first opener with fresh stock; min-open when 2nd/3rd opener |
| **3. Joker identity choice** | `options.first` (sorted, deterministic) | `options.first` | Pick identity whose real twin is already discarded (`DiscardHistoryView.cardSeenAt`) if available | Plus interior-slot preference in sequences; lowest cover-surface count where ambiguous |
| **4. Cover timing** | Cover whenever legal | Cover whenever legal | Hold cover if it's a sequence-end card AND own hand has 2+ adjacent ranks | Plus refuse to cover own meld if doing so opens an opposite-end cover for opponents |
| **5. Discard pick** | First legal discard | Highest-pip first | Track last 5 discards by (rank, suit) via `DiscardHistoryView`; avoid any rank an opponent took from discard in their last 3 turns | Track full pile attribution; per-opponent rank/suit "hot lists"; never discard adjacent to visible opponent run end |
| **6. Take discard vs draw stock** | Always draw stock | Take if directly forms a meld now | Plus take if it forms a 4th-card set extension or shortens hand below 8 | Plus take when stock thinning to deny pickup to next seat (anti-Fifty defence) |
| **7. Joker replacement** | Never | Replace when frees joker into a new immediate meld | Plus replace when opponent is opening-locked (denies them cover surface) | Plus delay replacement until before own finish turn to keep joker as discard-blocker |
| **8. Fifty reaction (timing)** | 45% miss chance, ~2.5s reaction | 25% miss, ~1.8s | 10% miss, ~1.1s; declines marginal Fifty in first-dealt round | 3% miss, ~0.65s; weights claim by own pip count + opponents' proximity to 31 |
| **9. Endgame mode** | None | None | When `stockCount ≤ 8`, switch to highest-pip-first discard mode | Plus stop expanding melds; greedily dump pips into existing partitions even at value loss |
| **10. Fifty offensive posture** | Reactive only; finishes round at first legal opportunity | Reactive only; will finish normally if available | Holds 2-3 discard cycles for Fifty when: hand value > 30, stock has ≥10 cards remaining, opponents have visible Fifty-eligible discards in `DiscardHistoryView`. Otherwise finishes normally. | Plans Fifty setups from round 1. Structures meld plays to keep Fifty-eligible cards in hand. Holds 5+ discard cycles. Targets opponents with high score for cumulative damage (their hand value + 3 to their score). Considers opponent elimination potential: hitting a player at 27 with Fifty may push them past 31. |
| **11. Score-aware risk** | Plays the same regardless of any score | Plays the same regardless of any score | When `ownScore ≥ 25`: prefers normal finish (-1) over risky Fifty hold; avoids high-pip discards that could land in opponent finishes; avoids meld plays leaving hand vulnerable to draw | All of Skilled, plus: when `ownScore ≥ 25` AND Fifty hold is plausible (heavy hand + Fifty-eligible cards), still attempts Fifty because -3 swing is worth the risk. When opponents are at `score ≥ 25`: refuses to discard cards that could enable Fifty against a third party (denies the bonus). When opponents are at `score ≥ 28` (within 3 of 31 bust): actively sets up Fifty attempts to push them over. |
| **12. Mistake permission** | Governed by `TableStrictness`, not by tier (see `table-strictness.md §7`) | — | — | — |

## Notes on rows 10-11

**Fifty offensive posture** depends on:
- `CpuObservation.ownHand` to compute hand pip value
- `CpuObservation.stockCount` to gauge round time pressure
- `CpuObservation.discardHistory` to identify Fifty-eligible opponents
- `CpuObservation.scoreFor(opponent)` for opponent elimination targeting (Expert only)
- `CpuObservation.openingState` to know whether the opener is locked (affects setup window)

**Score-aware risk** depends on:
- `CpuObservation.ownScore` and `CpuObservation.eliminationThreshold`
- `CpuObservation.scoreFor(opponent)` for each opponent
- `CpuObservation.discardHistory` joined with `tableMeldsFor(seat)` to detect "live" cards in opponents' hands

Both behaviors are testable in isolation against `FakeCpuObservation` per the
CpuObservation test surface design.

## Implementation slotting

Rows 1-9: split across `PriorityCpuMovePlanner` (Beginner/Casual columns) and
`SkilledCpuMovePlanner` / `ExpertCpuMovePlanner` (right two columns).

Rows 10-11: implemented in the Skilled and Expert planners. No new
infrastructure was needed beyond what `CpuObservation` already exposes.

Row 12: enforced through `TableStrictness` (`cpuMistakesAllowed` on
`StrictnessRuleProfile`), not the difficulty tier.
