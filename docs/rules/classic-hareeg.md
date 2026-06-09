# Classic Hareeg Rules

This document captures the working rule spec for Hareeg Table's default Classic Hareeg mode. It is based on player knowledge and should be treated as the canonical implementation target unless later corrected.

## Setup

- Default table: 4 players, one human and three CPU players.
- Turn order: anti-clockwise.
- Default deck: two standard 52-card decks plus two jokers. A one-deck setup does not contain enough cards for four 14-card seats plus the starter's extra card.
- Customization: multiple decks and up to four jokers.
- Default first starter: human player.
- Optional first starter setting: random.
- Each player receives 14 cards.
- Starter receives 15 cards and skips the first draw.
- Active matches are saved locally at safe table changes so the player can resume or abandon from the main menu.

## Melds

Valid melds have at least three cards:

- Set: same rank, different suits.
- Sequence: same suit, consecutive ranks.

With multiple decks enabled:

- Duplicate visual cards cannot exist in the same meld.
- Example invalid set: 9C, 9C, 9D.
- Example invalid sequence: 6C, 7C, 7C, 8C.
- Separate melds may contain duplicate visual cards if they use different physical deck copies.

## Ace Rules

Ace may be used at either end of a sequence, but never as a wrap connector.

Valid:

- A-2-3
- A-2-3-4
- A-2-3-4-5
- 10-J-Q-K-A
- J-Q-K-A
- Q-K-A

Invalid:

- K-A-2
- J-Q-K-A-2

Ace scoring for opening value:

- Ace normally counts as 10.
- A-2-3 counts as 15.
- A-2-3-4 counts as 19.
- A-2-3-4-5 counts as 15 because ace becomes 1 when 5 is included in the initially placed meld.
- If A-2-3-4 is placed first and a 5 is added later as cover, the original ace value remains 10. The later 5 adds its own value and does not recalculate the original meld.

## Opening Requirement

- Default opening requirement: 51.
- Custom opening requirements are allowed, including 75.
- An unopened player may open with one or more newly placed valid melds.
- The combined value of those opening melds must meet or exceed the current opening requirement.
- Covers cannot be used to satisfy opening.
- Once a player opens, they may immediately continue with legal post-opening actions in the same turn.

### Benchmark Raising

- The first player to open becomes the opening benchmark owner.
- If their opening value exceeds the base requirement, that value becomes the requirement for other unopened players.
- Until another player opens, the benchmark owner can keep increasing the requirement across turns.
- Any new table value contributed by the benchmark owner increases the benchmark before it locks:
  - new melds
  - covers
  - jokers placed as represented cards
- Joker replacement does not increase the benchmark, because the represented value already counted.
- Once any second player opens, the benchmark locks permanently.
- Later players cannot raise it.

## Covers

A cover is any card that can legally extend an existing table meld right now.

For sequence 6C-7C-8C:

- 5C and 9C are covers.
- 4C and 10C are not covers yet.

Players may place chained covers during the same turn. For example, after placing 9C on 6C-7C-8C, 10C becomes a legal cover and may also be placed.

Cover discard restriction:

- Any player, opened or unopened, cannot normally discard a card that is currently a cover.
- Opened players may play or keep it.
- Unopened players must keep it until they open or the table state changes.
- Final discard is an exception.

## Jokers

- Jokers may be used in opening melds, new melds, and covers.
- A joker's represented identity is assigned at placement.
- If multiple identities are legal, the human player must choose.
- Joker value equals the represented card value.
- Any opened player with the represented card may replace a table joker and take the joker into hand.
- Replacing a joker does not increase meld value or opening benchmark.
- The freed joker does not have to be played immediately.
- Jokers cannot be discarded during normal play in any mode.
- A joker may be used as the final discard that ends a round.

## Turn Flow

Starter's first turn:

- Starts with 15 cards.
- Skips draw.
- Enters action phase directly.
- Must end by discarding one card unless the round ends in a valid finish.

Normal turn:

- Player starts with 14 cards.
- Player must draw from stock or take the previous player's top discard.
- Player enters action phase.
- Player must end with a discard.

Taking previous discard:

- Only the immediate next player may take it.
- The taken discard must be used in a valid play during that turn.
- If the player cannot or does not use it, it returns to the discard pile and the player draws from stock.
- The app should mark a taken discard as pending until it is used or returned.

## Finishing

- A player must end the round with a final discard.
- A player cannot finish by placing every card.
- After drawing or taking a card, the finish shape is played cards plus exactly one final discard.
- The final discard may be a cover card or a joker.

Perfect-hand finish:

- If a player can finish the entire round with their own hand plus drawn/taken card, they may bypass the current opening requirement.
- This exists as a counter to very high opening benchmarks.
- If the finishing card came from stock, scoring is normal.
- If the finishing card came from the previous player's discard within the Fifty window, scoring is Fifty.

## Fifty

Fifty is a timed claim by the immediate next player after a discard.

- Only the immediate next player may claim Fifty.
- The discarded card must be used as part of a legal finishing sequence.
- It may be used in hand melds, table covers, or chained covers.
- The discarded card does not need to be immediately playable as the first action, as long as the full finishing sequence is legal.
- Default timer: 4 seconds.
- Custom timer range: 2-6 seconds.

Coaching and Standard:

- The Fifty action appears only when a valid Fifty exists.
- The player must still claim it before the timer expires.
- The app does not auto-claim.

Strict and Table:

- The Fifty action may appear during every claim window.
- Wrong Fifty claims receive the active mistake penalty.

If the timer expires:

- Fifty can no longer be claimed.
- The player may still take the discard normally if legal.
- If they finish this way, it scores as a normal finish, not Fifty.

## Stock Exhaustion

- The discard pile is not recycled.
- If stock is empty and the current player cannot draw, the round ends as a draw.
- Caveat: if the previous discard can be used to finish the game outright, play may continue for that finish.
- A non-finishing discard pickup is not enough to continue once stock is empty.
- Liveness: once stock is empty the only way a card leaves a hand is onto the table (a meld or cover), so if a full rotation of the active seats passes with no such progress — nobody can complete the finish that kept play going — the round is dead and ends as a draw. This prevents an endgame from cycling the discard pile forever.
- Drawn rounds do not change scores.
- The same starter starts the next dealt round.

## Scoring

Classic scoring uses card count, not card values.

Normal finish:

- Winner: -1.
- Every other active player: +number of remaining cards.

Fifty finish:

- Fifty winner: -3.
- First dealt round exception: Fifty winner gets -1 instead of -3.
- Discarder hit by Fifty: +remaining card count + 3.
- Other active players: +remaining card count.

Drawn round:

- No score changes.

Scores may go negative.

## Elimination

- Classic elimination threshold: 31.
- After scoring, any player with score >= 31 is eliminated.
- Eliminated players are removed from future rounds.
- Remaining players keep their relative anti-clockwise order.
- Last remaining player wins the match.
- Round winner starts the next round and receives 15 cards.
- If a round draws, the same starter starts again.

## Mistake Handling (`TableStrictness`)

How the table enforces rules is governed by `TableStrictness`, a single
four-tier ladder. Lower tiers teach by blocking; higher tiers allow mistakes
and price them with a score penalty.

- Coaching: illegal actions are blocked (no penalty). Proactive hints shown.
- Standard: illegal actions are blocked (no penalty). No proactive hints.
- Strict: selected mistakes are allowed and penalized +3, with no removal.
- Table: selected mistakes are allowed and penalized +17, and the offender is
  removed from the round.

Mistake types:

- illegal cover discard
- wrong Fifty claim
- insufficient opening meld
- wrong joker replacement

Joker normal discard is always blocked.

Table tier:

- Mistake gives +17.
- Player is immediately out of the current round.
- If score is now >= 31, they are eliminated from the match.
- Their hand is removed from play.
- Their existing table melds remain and may receive covers.
- They receive no additional score when the round ends.
