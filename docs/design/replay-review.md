# Replay review and the analysis coach

How a finished match is turned back into positions you can step through, and
what the coach is allowed to tell you about them.

This is the companion document issue #118 asks for. It is authoritative for the
review-observation contract and the teach-from-evidence boundary.

## 1. One reconstruction, three callers

A saved match is stored as a base snapshot plus the ordered actions applied from
it (`MatchActionTranscript`). Turning that back into match states is done in
exactly one place, `ReplayReconstruction`, which owns:

- crossing round boundaries via the deterministic next-round deal,
- validating that each entry describes the state it is about to be applied to,
- handing the action to the rules engine,
- the Fifty expire-and-retry,
- the synthetic replay clock,
- creating frames.

Three callers drain that one machine:

| Caller | How it drains | Why |
| --- | --- | --- |
| `replayTranscript` | `MatchReplayTimeline.build`, synchronously | Archive-time verification: does this transcript really produce the state we recorded? |
| The replay viewer | `IncrementalTimelineBuild`, in bounded chunks | A full match is ~1700 frames; draining it in one go would freeze the UI |
| Branch-and-play (later) | seeds from a frame | Out of scope for this slice |

There is deliberately **one** `applyAction` call site and **one**
`nextRoundSnapshot` call site under `lib/domain/classic_hareeg/replay/`, and a
test asserts it. Two reconstruction loops would be a second match-state format
in all but name: they would drift, and the difference would only show up as a
replay that disagrees with the history entry it came from.

## 2. The frame model

A frame is a position you can stand on. There are three kinds and they are all
ordinary step positions — the viewer does not treat any of them as a marker to
skip past:

- `initial` — the transcript's base state, before any recorded action.
- `roundStart` — the deterministic deal that opened a later round.
- `actionApplied` — the state produced by applying one recorded action.

For a transcript with `N` actions crossing `K` round boundaries there are
`1 + K + N` frames. The transcript's first round "opens" at the initial frame;
later rounds open at their own round-start frame, so `startIndexOfRound` always
has an answer and round navigation never lands somewhere ambiguous.

### The clock is not the snapshot's timestamp

Replay runs on a synthetic clock starting at `2026-01-01T00:00Z` and advancing
one second per applied action. This matters for Fifty windows, which are
time-sensitive: without it, replay would depend on how fast the machine ran.

`frame.clock` is that synthetic clock. It is **not** a claim about
`snapshot.savedAt`:

- Frame 0 carries the archived snapshot **unchanged**, so it keeps whatever
  timestamp it was actually saved with — possibly years ago. Its `clock` is the
  synthetic epoch.
- Reconstructed frames were stamped by this run, so for them
  `snapshot.savedAt == frame.clock`.

A test deliberately archives a snapshot dated 2019 and asserts both halves at
once, because an implementation that re-stamped frame 0, or that read the clock
off the snapshot, would otherwise look correct.

### `effectivePreActionClock`

The Fifty retry advances the clock *during* an apply: the engine refuses the
action while the window is open, the machine expires the window, and retries.
An `actionApplied` frame therefore records `effectivePreActionClock` — the
instant actually in force immediately before the action landed — and it is null
when no adjustment was needed, which is the ordinary case.

Anything reporting "how long was left on the window when this happened" must
read that value, falling back to the previous frame's clock. Reading the
previous frame's clock alone reports a time from *before* the jump that produced
the state being described.

## 3. What can go wrong, and what the player sees

Reconstruction is all-or-nothing. A partial timeline is never handed back,
because a truncated match rendered as the match misinforms more quietly than an
honest refusal does. The failure carries a partial snapshot for diagnostics
only; nothing renders it.

| Kind | Cause |
| --- | --- |
| `actionRejected` | The rules engine refused a recorded action |
| `roundUnavailable` | The transcript expected another round but the match had ended |
| `seatMismatch` | The entry names a seat the reconstructed state was not on |
| `phaseMismatch` | The entry names a turn phase the state was not in |
| `roundRegression` | The entry names a round earlier than the reconstructed round |

### Why seat and phase are validated

Decoding a transcript validates *shape* — that `seat` is a real seat name — not
correspondence to the state it will be applied to. Without the check, a
decodable transcript could attribute a legal South action to East. The replay
would run, render the wrong actor, and hand that false attribution to the
analysis coach, which would then reason about "your" move that was not yours.

The check is strict equality on all three fields. That is safe because the
recorder captures seat, phase and round from the controller *before* applying:
a probe over 4751 entries from six completed matches found zero mismatches of
any kind. Genuine history cannot fail this check; only mutated data can.

`legalActionIdsFor` is deliberately **not** used as the predicate. The same
probe found it omits 105 of those 4751 real action ids — every `play-meld` form
— so a legality check would reject genuine matches.

### Failures repair themselves

`openReplay` returns success as soon as the stored bytes decode. A record that
decodes but cannot be reconstructed would therefore stay marked replayable
forever, and the player could open the same dead link indefinitely. Opening such
a record asks the history module to repair the summary to non-replayable, and
the entry goes inert — durably, so a fresh launch agrees.

The message attached to a failure is diagnostic text containing raw action ids
and engine wording. It is never shown. The UI maps the failure *kind* to a typed
reason and renders localized copy for it, so neither language ever shows an
action id, an enum name, or English fallback text.

## 4. The review observation contract

`ReviewObservation` is the evidence boundary, and it is a boundary by
construction rather than by discipline.

It carries exactly: the perspective seat and the acting seat, the round, the
current seat and turn phase, **the perspective seat's own hand**, the discard
pile, all visible melds, per-seat hand *counts*, the stock *count*, scores,
active and removed seats, opened seats, the pending discard, the Fifty window,
the attributed discard/pickup history, the deck copy count, the strictness tier,
and the opening requirement.

It has **no field capable of holding**:

- another seat's hand contents,
- the stock's contents or order,
- the deal seed,
- any future transcript entry.

That is the whole point. An analysis built from this value cannot leak hidden
information even by accident, because there is nothing to leak from. A test
inventories the field names and fails when one is added without a decision.

The perspective seat's own hand *is* present. The rule is "no **other** seat's
hand", not "no hand at all" — your own cards were always observable to you.

### Actor attribution

`entry.seat` is documented in the transcript as "the seat that acted", but the
recorder writes the controller's **pre-action current seat**. For an out-of-turn
claim those differ. The review treats it as what it is: the seat whose turn it
was. The boundary is unaffected either way — when the entry names South, citing
South's own hand is legitimate however the claim was made.

## 5. Teach from evidence

The live coach reads the whole controller, because coaching a live player may
use that player's own full state. Review is the inverse problem: someone wants
to learn what was *knowable at the time*.

> **Good:** "East picked up two sevens from the discard pile, so this seven may
> feed their set."
>
> **Bad:** "East has two sevens" — when that fact comes from a hidden hand.

Both sentences might be true. Only the first is teachable, because only the
first rests on something the player could have seen and can learn to notice.

Three mechanisms enforce this, none of which is a promise to be careful:

1. **The signature.** `ReplayAnalysisCoach.review` accepts an observation, an
   action and the player's settings. There is no parameter for a controller, a
   snapshot, a transcript or a timeline. Hidden state cannot be passed in.
2. **The imports.** A test asserts the coach's source file imports none of the
   controller, snapshot, transcript or timeline types, so it cannot reach them
   another way.
3. **The evidence requirement.** `ReviewInsight` refuses to be constructed with
   an empty evidence list. "No observable evidence means no claim" is a type
   error, not a review comment.

The consequence is a property worth stating plainly: **two positions with the
same observable history produce identical advice**, because the coach cannot
tell them apart. It is not that it declines to use hidden state — it has no
access to any.

Every card an insight names, including cards nested inside evidence, must come
from the perspective hand, the discard pile, the pending discard, a visible
meld, or the observable pickup history. That last one matters: a card an
opponent publicly took has left the pile, but everyone saw it, so a tell may
name it.

## 6. When each insight fires

All conditions are functions of the **pre-action observation and the action
alone**. Nothing consults a post-action observation, because for actions like
`drawStock` the post-action state depends on the hidden stock — using it would
quietly reintroduce exactly the dependency section 5 exists to prevent.

| Category | Actions | Actor | Fires when | Does **not** fire when |
| --- | --- | --- | --- | --- |
| `deadDevelopmentKept` | discards | South | a kept group's every completion is dead | one completion is still live |
| `deadPickup` | pickups | South | the taken card joins a group that can no longer complete | the group still has a live completion |
| `feedRiskDiscard` | discards | South | public evidence says the card serves the next seat | no such evidence |
| `safeDiscard` | discards | South | no such evidence, and a next seat exists | there is no seat to feed |
| `missedCover` | discards | South | South had opened and held a card the real cover rule accepts | the card is merely rank-adjacent; or South had not opened |
| `opponentCollectingTell` | pickups | opponent | the pickup fits their prior public pickups or extends a visible meld | it fits neither |
| `opponentOpened` | meld plays | opponent | the actor was not in `openedSeats` | they had already opened |
| `fiftyWindowOpen` | anything but a claim | any | a Fifty window was open | no window, or the action was the claim |

`safeDiscard` and `feedRiskDiscard` are one judgement about one discard:
exactly one of them fires, unless there is no seat to feed at all.

`opponentOpened` reads the transition from the pre-action state because, by the
rules, an unopened seat that plays a meld is opening with it.

### A category that was cut

An earlier design had `fiftyWindowLapsed` — narrating a Fifty window that
expired unclaimed. Measurement killed it: across 8229 actions from eight
completed matches the condition occurred **zero** times, while an open window
occurred 3722 times. The timer defaults to four seconds and the replay clock
advances one second per action, so a window open longer than four actions would
lapse on its own; none did. The expire-and-retry path exists for matches
recorded against a wall clock, which a CPU-driven match never reproduces.

Shipping it would have meant a feature that provably never appears. It was
replaced with `fiftyWindowOpen`, which describes the same situation on data that
actually exists.

## 7. Verbosity

Three levels — narrate everything, key moments, clear mistakes only — plus an
independent switch for dead-card warnings, so a player who finds that particular
talk noisy can silence it without going quiet everywhere.

Filtering happens **after** generation, never instead of it. The same position
produces the same analysis whatever the player has chosen to be shown; settings
change what is displayed, not what the coach concluded. A test asserts the
unfiltered generation is identical across settings.

The persisted default lives in the existing preferences record. A replay may
override it on the fly, and that override is never written back — a test counts
save calls and requires zero across an entire review session.
