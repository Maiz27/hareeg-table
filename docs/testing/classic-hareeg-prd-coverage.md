# Classic Hareeg PRD Test Coverage

This map ties the Classic Hareeg rule flow back to the parent PRD and local
rule spec. It should be updated when rule behavior changes or when new
regressions expose a missing game-flow case.

Sources:

- Parent PRD: `docs/product/prd.md` links to GitHub issue #1.
- Local rule spec: `docs/rules/classic-hareeg.md`.

## Core Game Flow

| PRD area | Primary regression tests |
| --- | --- |
| Setup, deck count, jokers, starter hand size | `test/domain/classic_hareeg/classic_hareeg_round_test.dart`, `test/domain/classic_hareeg/classic_hareeg_setup_test.dart` |
| Physical card identity and duplicate visual-card rules | `test/domain/classic_hareeg/playing_card_test.dart`, `test/domain/classic_hareeg/meld_validator_test.dart`, `test/domain/classic_hareeg/cover_rules_test.dart` |
| Set, sequence, ace, and opening values | `test/domain/classic_hareeg/meld_validator_test.dart`, `test/domain/classic_hareeg/opening_rules_test.dart` |
| Opening requirement and benchmark raise/lock flow | `test/domain/classic_hareeg/opening_rules_test.dart`, `test/domain/classic_hareeg/classic_hareeg_meld_play_eligibility_test.dart`, `test/domain/classic_hareeg/classic_hareeg_game_controller_test.dart` |
| Covers, chained covers, cover discard restrictions | `test/domain/classic_hareeg/cover_rules_test.dart`, `test/domain/classic_hareeg/classic_hareeg_game_controller_test.dart` |
| Joker identity, replacement, and joker discard restrictions | `test/domain/classic_hareeg/joker_rules_test.dart`, `test/domain/classic_hareeg/classic_hareeg_game_controller_test.dart` |
| Mixed cover/replacement/discard game-flow regressions | `test/domain/classic_hareeg/classic_hareeg_discard_eligibility_test.dart`, `test/domain/classic_hareeg/classic_hareeg_game_controller_test.dart` |
| Turn flow, pending discard use-or-return, immediate next pickup | `test/domain/classic_hareeg/turn_flow_rules_test.dart`, `test/domain/classic_hareeg/classic_hareeg_draw_decision_planner_test.dart`, `test/domain/classic_hareeg/classic_hareeg_turn_exit_planner_test.dart`, `test/domain/classic_hareeg/classic_hareeg_table_play_retraction_planner_test.dart`, `test/domain/classic_hareeg/classic_hareeg_game_controller_test.dart` |
| Final discard, perfect hand, and round end | `test/domain/classic_hareeg/finish_rules_test.dart`, `test/domain/classic_hareeg/classic_hareeg_game_controller_test.dart` |
| Fifty claim validity, expiry, and mistake modes | `test/domain/classic_hareeg/fifty_rules_test.dart`, `test/domain/classic_hareeg/classic_hareeg_fifty_claim_planner_test.dart`, `test/domain/classic_hareeg/classic_hareeg_game_controller_test.dart` |
| Scoring, penalties, elimination, removed seats, next-round starter | `test/domain/classic_hareeg/classic_hareeg_score_ledger_test.dart`, `test/domain/classic_hareeg/match_progression_rules_test.dart`, `test/domain/classic_hareeg/classic_hareeg_game_controller_test.dart` |
| Stock exhaustion and empty-stock finish caveat | `test/domain/classic_hareeg/classic_hareeg_game_controller_test.dart` |
| CPU legality and strategy action surface | `test/cpu/classic_hareeg/cpu_strategy_test.dart`, `test/domain/classic_hareeg/meld_candidate_search_test.dart`, `test/domain/classic_hareeg/classic_hareeg_game_controller_test.dart` |
| Critical UI rule states | `test/ui/features/game_table/game_table_widget_test.dart` |

## Current Regression Anchors

- A duplicate visual card already present in a set with a represented joker is
  discardable. Example: table has Joker-as-JC, JH, JS; a second JH in hand is
  not a cover.
- The missing suit in that same set is still a blocked cover, and the represented
  joker identity is still a blocked replacement discard in Assisted mode.
- In one action phase, the controller keeps sequence covers, represented-joker
  replacements, and ordinary duplicate-card discards distinct.
- Discard eligibility resolves normal, final, joker, cover, replacement, and
  cover-plus-replacement scenarios through one rule result before action ids are
  advertised or applied.
- Human ambiguous set melds with one joker surface explicit represented-identity
  choices in the UI instead of auto-choosing the first legal identity.
- Selected melds with more than two unresolved jokers still resolve explicit
  represented-identity choices; setup can allow several jokers in one game.
- CPU meld search also considers legal meld shapes that need multiple unresolved
  jokers instead of assuming a one-joker candidate bound.
- Turn exits centralize discard continuation, Fifty window ownership, stock
  exhaustion, and hard-table removal transitions so seat movement stays one
  module decision.
- Draw decision planning centralizes Fifty claim visibility, stock draw,
  previous-discard pickup, and stock-exhausted pickup-finish gating before
  legal, CPU, and control actions are advertised.
- Opening and finish meld play eligibility centralizes pending-discard use,
  final-discard requirements, staged opening melds, opening completion, and
  finish-candidate advertisement before controller mutation.
- Table-play retraction planning centralizes bulk undo, specific meld
  affordances, hard-table blocking, and staged-opening/current-turn cover/meld
  distinctions before controller mutation.
- Fifty claim planning centralizes claim visibility, timer expiry, active
  discard checks, finish proof, and preset-specific wrong-claim penalties before
  controller mutation.
- Score reads use the current score view after a completed round, while the
  round-result overlay still keeps the before-round baseline explicit.
- Human ambiguous sequence melds with one joker do the same; JH-QH-joker
  offers 10H/KH, while mixed-suit JD-QH-joker has no meld action.
- Sequence cover rules evaluate ace as both low and high, so ace can extend
  J-Q-K / 10-J-Q-K as the high-end cover.
- Retracting a specific current-turn meld returns only that meld, while the
  bottom meld undo can still return all current-turn table plays.
- The Fifty timer ring is visible for the human claim window even when Assisted
  mode disables tapping because the claim is not legal.
