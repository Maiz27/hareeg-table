# Match history archiving

How a completed Classic Hareeg match becomes two durable records, and what
happens when the process dies partway through.

## The two records

| Where | What | Why there |
| --- | --- | --- |
| `match_history_index.v1` (key-value) | every `MatchHistorySummary` | small, read on every history listing |
| `ReplayFileStore[matchId]` | one `MatchReplayRecord` | far too large for a preferences store, and only needed when a replay is opened |

Plus two transient records that exist only while a match is live or being
published:

| Where | What |
| --- | --- |
| `active_match.v1` | the one `MatchCheckpoint`, live **or** terminal |
| `match_archive_pending.v1` | `PendingMatchArchive`: `{version, matchId}` |

The checkpoint holds the recorder state, so it is the only key-value record that
ever contains transcript entries. That copy is deliberate and temporary — it is
deleted at the end of publication. Nothing else in the key-value store holds a
snapshot, a transcript, or a replay record.

## Why terminal facts exist

`ClassicHareegMatchSnapshot` records no winner, and its `activeSeats` are the
pre-progression set. `MatchProgressState`, which does hold the winner, is never
persisted.

So if the app died between marking a match complete and publishing it, recovery
would have nothing to reconstruct the completion from. It would have to stamp
its own clock — producing a match "completed" hours after it really was — and
guess a winner from board state. Both guesses would be wrong, and the resulting
history entry would look perfectly valid.

`MatchTerminalFacts` is therefore written **once**, at match-over, and never
recomputed: UTC completion time, winner, final scores, round count, elimination
rounds, and the seats that played. Recovery republishes it verbatim.

For the same reason the pending record carries only a match id. A duplicated
timestamp could disagree with the checkpoint's, and there would be no principled
way to pick a winner between them.

## Publication order

1. Mark the checkpoint terminal and save it.
2. Save the pending archive.
3. Write the replay record.
4. Write the summary into the history index.
5. Remove the pending archive.
6. Remove the terminal checkpoint.

For a verified transcript, the replay lands before its replayable summary is
published. An unverifiable transcript instead produces a non-replayable summary
without a replay file. A file lost after publication is handled by the drift
repair described below.

## What each crash point converges to

`MatchHistoryRepository.recoverPendingArchive()` runs on app start and before
starting or continuing a match. Publication recovery converges on one summary,
paired with a replay file when the transcript verifies and without one when it
does not, or reports a typed failure while preserving recoverable data.

| Died after | What recovery finds | What it does |
| --- | --- | --- |
| step 1 | terminal checkpoint, no pending record | recreates the pending record and publishes, using the **original** terminal facts |
| step 2 | terminal checkpoint and pending record | publishes |
| step 3 | replay file already written | rewrites it byte-identically; one file results |
| step 4 | summary already in the index | does not duplicate it |
| step 5 | terminal checkpoint with no pending record, summary already durable | recreates the pending record, recognizes the existing summary, then clears both markers without rewriting the replay |

A pending record without a matching terminal checkpoint is an orphan-recovery
case, not a crash point in this ordered sequence. If its summary exists,
recovery clears only the pending record. If the summary is also absent after
successful reads, recovery clears the data-less marker and reports the loss.
Read failures remain failures and never count as evidence of absence.

A terminal checkpoint is never offered as a game to continue. The home screen
filters it out, so a completed-but-unpublished match cannot be resumed as though
it were still in progress.

## Replayability is earned, not assumed

Before a summary is published as replayable, the candidate transcript is
**replayed and compared against the completed match's final state**.

This matters more than it sounds. A transcript can be entirely well-formed —
correct schema, monotonic ordering, valid entries — and still be missing an
action, because losing actions is exactly what the old resume path did. Such a
transcript replays without error and simply arrives somewhere else. Checking
scores and round counts alone is not enough either: a dropped action late in a
match often leaves those untouched while changing hands, stock, or the discard
pile. Only replaying it and diffing the whole reconstructed state catches it.

When verification fails, the summary is published with `replayable: false` and
**no replay file is written**. The match still appears in history with its full
setup, scores, winner, placement, round count, coach flag, and counters — an
honest entry rather than a button that opens nothing.

`replayIneligible` on the checkpoint is sticky: once a match is known to have an
incomplete transcript it can never become replayable again, because the missing
actions are gone for good.

## Two flags that look related and are not

`replayable` and `fiftyCountersComplete` are independent.

A match can lose its replay file long after completion — the file is deleted, or
storage is wiped — and be repaired to `replayable: false` while its Fifty
counters were measured perfectly all along. Conversely a legacy match migrated
from a pre-checkpoint save has no recorder at all: it is permanently
non-replayable *and* its counters were never tracked.

So `fiftyCountersComplete: false` means the counters are **unknown**, not
measured-zero. No consumer may read those zeros as evidence the player never
attempted a Fifty.

## Elimination rounds

A controller only knows about eliminations from its own round, and the match-wide
accumulation used to live in the game screen, so it vanished on resume — which
silently corrupted finish order, since standing is decided by who outlasted whom.

The match-wide map now lives on the checkpoint and is merged on every save. The
merge keeps the **earliest** round each seat went out in: an elimination cannot
un-happen, and raising the round would make a seat look like it lasted longer
than it did.

Once the match is terminal the map is frozen into the terminal facts and the
checkpoint delegates to it, so exactly one copy is serialized at each stage of
the match's life.

## Archiving triggers on a winner, never on "no next round"

The table stops dealing when the human is eliminated, even with CPUs still
playing. That produces a null next-round snapshot — the same signal a genuine
match completion produces.

`ClassicHareegTablePersistencePlanner` therefore keys archiving on a non-null
`matchWinner` and nothing else. South being knocked out with two CPUs alive
abandons the match without recording it, because no match was completed.

## Verification

See [replay-file-store-verification.md](replay-file-store-verification.md) for
the on-device probe covering the storage layer beneath all of this.
