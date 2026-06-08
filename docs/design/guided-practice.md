# Guided Practice Design

Status: Shipped (PRD #64, stacked PRs #76–#80; close-out #82). Guided practice
is the optional teaching layer for Classic Hareeg mechanics — a checklist of
21 lessons across 4 packs that run as deterministic boards on the real table.

This doc records what shipped. It supersedes the scattered per-module CONTEXT.md
notes; CONTEXT.md keeps only the vocabulary index and points here.

Reads:
- `table-strictness.md` — the four tiers the strictness pack teaches; `completesOnPenalty` rides Strict's revert and Table's +17/round-out.
- `lib/ui/features/game_table/practice_table_run.dart` — the table↔practice seam.
- `lib/ui/features/learning/practice/practice_session.dart`, `practice_lesson_script.dart`, `practice_board.dart`, `practice_board_grammar.dart`, `practice_script_authoring.dart` — the lesson-script harness.
- `lib/ui/features/learning/practice/{core_turn,table_mechanics,finish_fifty,table_strictness}_practice_pack.dart` — the lesson content.
- `lib/ui/features/learning/models/{practice_catalog,practice_lesson_registry,practice_lesson_delivery}.dart` — lesson identity/order/delivery.
- `lib/ui/features/learning/progress/learning_progress_workflow.dart`, `lib/data/persistence/learning_progress_repository.dart` — progress command surface + storage.
- `lib/ui/features/game_table/table_interaction_planner.dart` — `TableInteractionActionGate`.
- `lib/ui/features/game_table/coach/coach_highlighting.dart` — shared ring language.
- `test/support/practice_lesson_harness.dart`, `test/support/practice_widget_harness.dart` — the two test seams.

## 1. Surface pivot

The PRD #64 amendment scrapped a bespoke practice screen: a lesson runs on the
real `GameTableScreen` in **practice mode**, so every gesture the player learns
is the literal gesture a normal match uses — tap the stock to draw, select cards
and confirm the meld chip, drag to the discard pile, tap the pile to take, run
the joker picker. Nothing is simulated and nothing transfers imperfectly.

`PracticeTableRun` (`practice_table_run.dart`) is the table-facing seam. It owns
the presentation state that follows a session mutation; `GameTableScreen` still
owns rendering, gesture plumbing, motion, audio, haptics, and shell callbacks.
Practice-mode invariants:

| Concern | Practice-mode behavior |
|---|---|
| Match chrome | Hidden (no scoreboard pressure, pause menu, round overlay). |
| CPU autonomy | None. The only non-player moves are the script's `introActionIds`, replayed visibly by the other seats. |
| Active-match store | Never written. The session owns a private controller built from the lesson snapshot. |
| Step prompts | Ride the same coach banner surface (`PracticeTableBannerState`: step index/count, prompt, hint, live reaction). |
| Highlighting | Coach-style rings, the same visual language as the live coaching tier (§3). |
| Completion | A completion panel; scoring lessons reveal the real score sheet first (`finishScoreReveal` → `isComplete`). |
| Dead-end | A timed window (Fifty) that expired strands the run; `missedNote` explains, the player restarts on a fresh board. |

`applyProgress` maps each `PracticeSubmitStatus` onto table effects: an accepted
action surfaces the step's `holdNote` reaction, a completed step surfaces its
`successNote`, a completed lesson either opens the score reveal
(`showScoresOnCompletion`) or completes, and reports `shouldPersistCompletion`
+ `lessonId` so the shell records progress.

## 2. Lesson-script harness

A lesson is a declarative `PracticeLessonScript` (`practice_lesson_script.dart`):
a deterministic board plus an ordered list of `PracticeStep`s. **All legality is
the real `ClassicHareegGameController`'s** — the script only narrows which legal
actions the surface offers and decides when the player has demonstrated the
mechanic.

`PracticeLessonScript` fields:

| Field | Role |
|---|---|
| `buildSnapshot` | Builds the deterministic starting board (rebuilt fresh per run/replay, so replay starts identically). |
| `steps` | Ordered teaching steps; the lesson completes when the last is satisfied. |
| `introActionIds` | Scripted prologue played visibly by the other seats through the real engine + normal CPU pacing; the board starts on the acting seat, the last action hands the turn to `seat`. |
| `taughtMelds` | The teaching cards in the player's hand, per group; everything else is a filler the board audit proves meld-free (§3). |
| `boardAuditSpec` | Declared board-grammar claim audited at session construction. |
| `completionNote` | Localized outcome note; receives the finished controller to cite the engine's real score impact. |
| `showScoresOnCompletion` | Opens the real score sheet over the finished board before the panel (scoring lessons). |
| `fiftyTimerPausesAtSeconds` | Freezes the lesson clock once a live Fifty window counts to N seconds, so reading the prompt is never punished. |
| `seat` | Seat the player drives (default south). |

`PracticeStep`:

| Field | Role |
|---|---|
| `allows(action)` | Filter for which legal actions the surface offers this step (defaults to all). `PracticeStep.kinds` is the action-kind shorthand. |
| `isSatisfied(context)` | Whether a successful allowed action completes the step (defaults to `isDemonstrated`, else true). |
| `isDemonstrated(controller)` | Board-state proof the step's outcome still holds; drives take-back regression and forward auto-skip. |
| `isDeadEnd(controller)` | Whether the board can no longer demonstrate the step (a timed window died). |
| `highlightCardIds` / `highlightGroups` | The cards to ring; single-group teal, or per-group hues (§3). |
| `holdNote` | Reactive banner for an allowed action that applied but left the step unsatisfied (e.g. a partial run staged below the benchmark). |
| `completesOnPenalty` | Lets a Strict-tier penalized/reverted mistake complete the step (§5). |

`PracticeSession` (`practice_session.dart`) is the runtime for one lesson. It
owns the private controller built from the snapshot, audits the board on
construction (throws if the grammar fails), and applies every move through the
real engine. `submit(actionId)` returns a `PracticeSubmitStatus`:

| Status | Meaning |
|---|---|
| `accepted` | Applied but did not finish the step (multi-action / staged play). |
| `corrected` | A take-back applied; step progress untouched (never narrated as a stall). |
| `stepCompleted` | Applied and finished the current step. |
| `lessonCompleted` | Applied and finished the final step. |
| `rejected` | The engine rejected it, or reverted it with a penalty (real rules feedback in `message`). |
| `notAllowed` | The step does not offer it; nothing applied. |

Step gating runs through `offersActionId` (the affordance membership check,
matching `submit`'s filter exactly). Two seams keep the lesson navigable:

- **Take-back corrections.** `returnOpeningMelds` / `returnTablePlay` are always
  offered (gating them would strand a mis-staged hand). An unsolicited take-back
  is a `corrected` that re-verifies completed steps and walks the prompt back to
  the first one whose board-state proof no longer holds — the prompt follows the
  player. A step whose own filter *names* the take-back kind (benchmark-pressure)
  treats the retract as the taught move and completes normally.
- **`completesOnPenalty`.** A reverted engine result (Strict's paid mistake: the
  score is charged but the card snaps back and the turn does not advance)
  collapses to a non-advancing `rejected` by default. A Strict lesson that
  teaches the penalty opts in, and the reverted throw is evaluated like an
  accepted action so the lesson finishes on the +N.

`PracticeBoard.build` (`practice_board.dart`) builds boards from a seeded full
deal, then moves the lesson's named cards into place (south hand, optional top
discard, `priorDiscards` to dress a late-round pile, pre-placed `tableMelds`,
`cpuSeedCards` for intro turns). **Card conservation is enforced**: duplicate
claims and claims outside the dealt pool throw, and unclaimed cards pad the CPU
hands and stock so every physical card exists exactly once.

## 3. Board-design rules / `PracticeBoardGrammar`

Practice boards must read like real deals. `PracticeBoardGrammar`
(`practice_board_grammar.dart`) makes that an executable claim audited against a
`PracticeBoardAuditSpec`:

- Visible openings **total what they imply** (`expectedTableValues`).
- A seat's hand + own table cards account for **one dealt 14** at turn start
  (`extraCardsInHand: 1` for mid-turn boards after a draw); `fullHandSeats`
  asserts an unopened 14.
- A dressed late-round board carries a `minimumDiscardPileSize`.

The **filler-composition audit** is the load-bearing addition: a script declares
its `taughtMelds` (the cards each step asks the player to use), and the audit
takes every hand card *not* in a teaching group and asks the real
`MeldPartitionEnumerator` to prove those fillers form no unintended meld. This is
the executable form of the old per-lesson `// Fillers: no meld` comment — a stray
meld in the hand would light a `playMeld` affordance the prompt never describes.
An empty `taughtMelds` claims the whole hand is meld-free (bait / trapped-card
lessons); a null one makes no claim. The recurring specs and step-filter shapes
live in `PracticeScriptAuthoring` (`practice_script_authoring.dart`):
`cpuHandsStayFull`, `allHandsStayFull`, `southOpened51OneDeal`,
`southOpened51MidTurn`, `southUnopenedMidTurn`, …, plus the `playsExactly`,
`playsJokerMeldExactly`, and `tableHolds` helpers.

**Highlighting** speaks the live coach's language. A step rings **one meld per
step** (ringing a whole opening at once invites mis-grouping). `highlightGroups`
flattens into `groupOf` in `PracticeTableRun.highlighting`, exactly as
`CoachHighlighting.fromHint` flattens a coach hint, and the table resolves each
group to its palette hue (`coach_highlighting.dart` →
`LoungeTokens.coachRingPalette`):

| Group | Hue | Meaning |
|---|---|---|
| group 0 | teal `0xFF2FB4A6` | the card(s) you hold / play |
| group 1 | blue `0xFF4FA8E0` | the target meld already on the table |

Single-group steps use `highlightCardIds` and ring the default teal. The
stock-draw and pile-take rings are derived from the step's allowed kinds, not
listed.

## 4. Architecture (module map and seams)

```text
checklist / table shell
        │
        ▼
PracticeLessonRegistry  ──uses──▶  PracticeCatalog (id, pack, order)
   deliveryFor / scriptFor /         + PracticeLessonDelivery
   nextScriptInPack                    (scriptedTable | readingPanel | unavailable)
        │ builds
        ▼
PracticeLessonScript  ◀── per-pack modules share PracticeScriptAuthoring:
        │                  CoreTurnPracticePack, TableMechanicsPracticePack,
        │                  FinishFiftyPracticePack, TableStrictnessPracticePack
        ▼
PracticeSession  ──owns──▶  private ClassicHareegGameController (real rules)
        ▲                    audited by PracticeBoardGrammar at construction
        │
PracticeTableRun  ──table↔practice seam──▶  GameTableScreen (practice mode)
        │                                     gates gestures through
        ▼                                     TableInteractionActionGate
LearningProgressWorkflow ──▶ LearningProgressRepository (serialized writes)
```

| Seam | Responsibility |
|---|---|
| `PracticeCatalog` | Static lesson identity, pack membership, checklist display order, stable persistence ids. |
| `PracticeLessonDelivery` | How a lesson reaches the player: `scriptedTable` (a script builder), `readingPanel` (strictness tiers), or `unavailable`. |
| `PracticeLessonRegistry` | Joins catalog id → delivery → script; owns next-in-pack chaining (`nextScriptInPack`), not the table or checklist. |
| `PracticeTableRun` | Table-facing presentation state after a session mutation. |
| `TableInteractionActionGate` | One interface every gesture affordance crosses before reaching the surface. The live table uses `AllowAll`; practice supplies a `Predicate` gate backed by the active step (`offersActionId`), or `BlockAll` off-turn / once complete. |
| `LearningProgressWorkflow` | Thin command surface for onboarding/lesson complete/skip/unskip. Write serialization lives on the repository (`SerializedLearningProgressUpdate.update`), so transient workflow instances over a shared repository never lose a write. |
| `practice_lesson_harness` | Session-level tests: build a script, run the intro at the rules seam (`runPracticeIntro`), assert board audits, walk Fifty windows with `PracticeTestClock`. |
| `practice_widget_harness` | Real-gesture widget tests: host a session on `GameTableScreen`, pump through the scripted intro, drag/tap real affordances, assert coach ring colours. |

`LearningProgress` persistence (`learning_progress_repository.dart`) is plain:
`onboardingCompleted` plus a sparse `lessonId → status` map
(`notStarted`/`skipped`/`completed`), unknown enum names fall back to
`notStarted`, and `notStarted` removes the entry so unskipping leaves no residue.

## 5. The curriculum — 4 packs, 21 lessons

Order is `PracticeCatalog.lessons`. Stable ids are persistence keys; never rename
a shipped id without a migration.

### Core turn (`CoreTurnPracticePack`) — 5

| id | Teaches |
|---|---|
| `turn-rhythm` | The draw → discard heartbeat (trimmed meld-free hand). |
| `first-meld` | A first opening from your own hand: a 6-card heart run worth 59 clears 51 in one play. |
| `discard-opening` | Taking the pile when the card opens the table; west's scripted throw completes a held set. |
| `bait-discard` | Reading a trap: the pile pairs your hand but still falls short of 51 — leave it, draw. |
| `opening-51` | Staging multiple melds within one turn to cross the benchmark. |

### Table mechanics (`TableMechanicsPracticePack`) — 7

| id | Teaches |
|---|---|
| `pending-discard` | Use-or-return: a taken card can go back before it touches the table (then can't be re-taken this turn). |
| `benchmark-pressure` | A legal meld can still miss the raised benchmark; the retract is the deliberate way out. |
| `set-cover` | Filling another seat's set with its one missing suit. |
| `sequence-cover` | Stacked covers across two melds in one turn. |
| `cover-discard-block` | A card the table can use cannot be thrown away (Standard hard-blocks it). |
| `joker-identity` | A melded joker is exactly what its owner declares. |
| `joker-replacement` | Reclaiming a table joker with the real card it stands for. |

### Finishing & Fifty (`FinishFiftyPracticePack`) — 6

| id | Teaches |
|---|---|
| `final-discard` | A finish always keeps one last card to throw; the round genuinely ends. |
| `normal-finish` | Empty the hand through melds, go out on the last discard; the real score sheet reveals the consequence. |
| `perfect-hand-finish` | Lay a whole sub-51 hand as per-set plays and finish **without ever opening** (the perfect-hand bypass); unopened seats still pay full. |
| `joker-final-discard` | A joker can't be thrown in play, but it **may be the closing throw**. |
| `fifty-claim` | Claim the previous discard before the window closes, then prove the finish by hand (timer holds at 3s). |
| `fifty-scoring` | The same claim, read through the score sheet: claimant −3, discarder's full hand +3. |

### Table strictness (`TableStrictnessPracticePack`) — 3

| id | Teaches |
|---|---|
| `strictness-tiers` | A reading panel introducing the four tiers (`readingPanel` delivery, no board). |
| `strict-penalty` | The trapped-cover throw on **Strict**: it lands as a paid mistake, reverts for **+3**, completes via `completesOnPenalty`, and the score sheet reveals the +3. |
| `table-penalty` | The same throw on **Table**: it stays, costs **+17**, and **removes south from the round**; the step completes the instant the round-out lands. |

The strictness demos reuse `coverDiscardBlock`'s board (south unopened, holding
the 10♥ that would complete west's scripted tens), changing only the table's
tier so the escalation reads as one rule turned up. Both ring the trapped ten
(group 0) beside west's set it would complete (group 1) and open the real score
sheet (`showScoresOnCompletion`) so the price is read where a match would show it.
