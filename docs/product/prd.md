# PRD: Hareeg Table Offline Card Game

## Problem Statement

Sudanese Hareeg players do not have a free, offline-first mobile Hareeg game that respects the way Classic Hareeg is played at the table. Existing options may include ads, locked cosmetics, online-first assumptions, or rule behavior that does not match common Sudanese play. The user wants an open-source Android-first game that preserves Classic Hareeg's pressure, timing, card-management, Fifty, joker, cover, and elimination rules while still feeling polished and approachable on a phone.

The core product risk is rule authenticity. If the game treats Hareeg like generic rummy, the experience will be wrong. The app must therefore build around a precise Classic Hareeg rules engine before expanding into Hareeg 14, a dedicated Fifties mode, online play, or richer cosmetics.

## Solution

Build Hareeg Table as a Flutter mobile game with an Android-first launch and future cross-platform support. The default experience is a four-seat offline Classic Hareeg table: one human player against three CPU players, anti-clockwise turn order, 14-card hands with a 15-card starter, opening benchmark pressure, cover restrictions, joker replacement, timed Fifty claims, Classic scoring, and elimination at 31.

The game should be free and open source, with no ads and no paid cosmetic locks. The presentation should feel like a warm Sudanese lounge: readable dark table, ivory cards, restrained cultural accents, and special flame/heat treatment for Fifty moments. English is the launch language, but localization architecture must be present from the beginning so Arabic support can be added cleanly.

The implementation should center on a deep, pure-Dart Classic Hareeg rules module that can be tested independently from Flutter UI. The app layer should consume this engine through explicit game state and legal move interfaces, while CPU strategy should sit in its own module and produce legal move intents rather than directly mutating state.

## User Stories

1. As a Hareeg player, I want the game to use Classic Hareeg rules, so that it feels like the table game I know.
2. As a solo player, I want to play against three CPU players, so that I can enjoy a full four-player table without online multiplayer.
3. As a new player, I want the default mode to block illegal actions, so that I can learn without accidentally ruining a round.
4. As an experienced player, I want stricter table-style penalty modes, so that the game can reward memory and attention.
5. As a player, I want the starter to receive 15 cards and skip drawing, so that the first turn matches Classic Hareeg.
6. As a player, I want normal turns to require drawing from stock or taking the previous discard, so that turn flow is authentic.
7. As a player, I want taking the previous discard to force immediate use, so that discard pickup cannot be abused.
8. As a player, I want a taken discard to be visually marked as pending, so that I understand I must use or return it.
9. As a player, I want to open with one or more melds, so that I can combine valid meld values to meet the opening requirement.
10. As a player, I want the opening requirement to start at 51 by default, so that the standard Classic Hareeg flow is supported.
11. As a rules customizer, I want to set other opening requirements such as 75, so that different house rules are playable.
12. As a player, I want the first opener to raise the benchmark when their opening value is higher, so that early strong openings create pressure.
13. As a player, I want the first opener to keep raising the benchmark until another player opens, so that the pressure mechanic is preserved.
14. As a player, I want the benchmark to lock after a second player opens, so that the opening target stabilizes for the rest of the round.
15. As a player, I want covers to be blocked from discard for all players, so that opening first creates real hand pressure.
16. As an unopened player, I want cover cards to remain stuck in my hand, so that the app reflects the strategic cost of not opening.
17. As a player, I want sequence covers to be direct adjacent cards only, so that the app does not over-mark distant cards as covers.
18. As a player, I want set covers to work across missing suits, so that rank-set extension is supported.
19. As a player, I want chained covers to be playable in one turn, so that I can extend a meld multiple times when legal.
20. As a player, I want jokers to work in opening melds, normal melds, and covers, so that they match table play.
21. As a player, I want to choose a joker identity when multiple identities are legal, so that ambiguous joker placement is explicit.
22. As a player, I want joker identity to be represented visually, so that replacement opportunities are understandable.
23. As an advanced player, I want memory-oriented joker display options, so that joker identity tracking can become part of the challenge.
24. As a player, I want joker replacement to give me the joker without requiring immediate play, so that the table rule is respected.
25. As a player, I want joker replacement not to increase the opening benchmark, so that equivalent swaps do not double-count value.
26. As a player, I want normal joker discards to be blocked, so that the app enforces a hard Hareeg rule.
27. As a player, I want a joker to be valid as the final discard, so that legal finishes are not incorrectly blocked.
28. As a player, I want a cover card to be valid as the final discard, so that finish exceptions work correctly.
29. As a player, I want every finish to require a final discard, so that players cannot end by placing all cards.
30. As a player, I want perfect-hand finishes to bypass the opening requirement, so that high opening benchmarks can still be beaten.
31. As a player, I want stock draws that complete a perfect hand to score normally, so that only discard-based timed finishes become Fifty.
32. As a player, I want a timed Fifty claim after the previous player discards, so that the special move preserves its physical-game urgency.
33. As a player, I want Assisted mode to show Fifty only when it is valid, so that the default experience is fair and learnable.
34. As an advanced player, I want penalty modes to expose Fifty claims even when invalid, so that wrong Fifty calls can be punished.
35. As a player, I want the Fifty timer to be configurable, so that tables can feel more relaxed or more intense.
36. As a player, I want missing the Fifty timer to still allow normal discard pickup if legal, so that the move becomes a missed bonus rather than blocked play.
37. As a player, I want the Fifty winner to receive the correct score reduction, so that the reward is meaningful.
38. As a player, I want the discarder hit by Fifty to receive the extra penalty, so that risky discards matter.
39. As a player, I want first-round Fifty scoring to use the clearer app default, so that the opening round does not create confusing score jumps.
40. As a player, I want normal wins to reduce the winner score by one, so that repeated wins can create comebacks.
41. As a player near elimination, I want winning rounds to lower my score, so that survival remains possible.
42. As a player, I want all non-winners to score by remaining card count in Classic mode, so that Classic scoring is preserved.
43. As a player, I want players at 31 or higher to be eliminated after scoring, so that the match progresses to a last-player-standing result.
44. As a player, I want eliminated seats to be skipped while preserving table order, so that remaining play stays natural.
45. As a player, I want the previous round winner to start the next round, so that the 15-card starter rule follows the winner.
46. As a player, I want stock exhaustion to create a draw with no score changes, so that rounds do not recycle indefinitely.
47. As a player, I want empty-stock play to continue only when the previous discard can end the game, so that the final discard opportunity is handled correctly.
48. As a rules customizer, I want to configure deck count, so that different table setups are possible.
49. As a rules customizer, I want to configure joker count up to four, so that different house preferences are supported.
50. As a player, I want duplicate deck copies to be legal across separate melds but not inside the same meld, so that multiple-deck play remains coherent.
51. As a player, I want low-ace and high-ace sequences to be legal without wraparound, so that ace behavior matches Hareeg.
52. As a player, I want ace scoring to follow Hareeg placement rules, so that opening values are accurate.
53. As a player, I want later covers not to retroactively change an already placed ace value, so that opening values stay stable.
54. As a player, I want clear invalid-action feedback, so that I understand why a card cannot be discarded or played.
55. As a player, I want CPU players to respect the same default legality rules, so that the table feels fair.
56. As a player, I want CPU difficulty to affect decisions and reaction time, so that higher levels feel more skillful.
57. As a player, I want easier CPUs to miss some opportunities, so that beginner games are approachable.
58. As a player, I want stronger CPUs to track visible cards and avoid feeding opponents, so that expert games remain interesting.
59. As a player, I want CPU Fifty reactions to vary by difficulty and personality, so that CPU turns feel human rather than instant.
60. As a player, I want rule presets for assisted play and penalty play, so that I can choose how close the app feels to a physical table.
61. As a player, I want normal mistake penalties to add three points, so that common live-table mistakes have meaningful cost.
62. As a hardcore player, I want a 17-point mistake preset that removes the mistaken player from the round, so that harsh table rules are available.
63. As a player, I want a player removed by a 17-point mistake to return next round if not eliminated, so that the penalty matches the described table behavior.
64. As a player, I want removed players' table melds to remain available for covers, so that the current round state stays useful.
65. As a player, I want no ads, so that play is not interrupted.
66. As a player, I want themes and cosmetics not to be locked behind payment, so that the app feels generous.
67. As a mobile user, I want the game to avoid unnecessary animation loops, so that battery use remains reasonable.
68. As a mobile user, I want smooth dealing, card movement, and Fifty moments, so that the game feels polished.
69. As a player, I want auto-sort controls available during play and from settings, so that hand management is comfortable.
70. As a future Arabic-speaking player, I want the app to be localization-ready, so that Arabic support can be added without rewriting UI.
71. As an open-source contributor, I want the rules documented clearly, so that implementation and review can be aligned.
72. As an open-source contributor, I want a testable rules engine, so that rule changes can be made safely.
73. As a maintainer, I want the PRD tracked as a parent issue, so that implementation issues can be linked back to product intent.
74. As a maintainer, I want future modes kept out of the first release, so that Classic Hareeg quality is not diluted.
75. As a future player, I want Hareeg 14 and a dedicated Fifties mode to be planned, so that the app can grow after Classic is stable.

## Implementation Decisions

- Build the app in Flutter with Dart, Android-first, while retaining the generated cross-platform project structure for future iOS and desktop support.
- Create a deep pure-Dart rules module that owns all Classic Hareeg mechanics: card identity, physical deck copies, meld validation, cover detection, joker identity, opening benchmark state, discard pickup, finish validation, Fifty validation, scoring, elimination, and stock exhaustion.
- Keep the rules module independent from Flutter widgets, storage, animation, and CPU strategy.
- Represent every physical card distinctly while exposing visual identity separately, so multiple decks can be supported without allowing duplicate visual cards inside a single meld.
- Model joker identity as explicit state assigned at placement time, with support for ambiguous human choices and deterministic CPU choices.
- Model opening benchmark as a round state with owner, current value, and locked status. Contributions by the benchmark owner increase it until another player opens.
- Model taken discard as a pending state that restricts available actions until the discard is used or returned.
- Model finish validation separately from ordinary move validation, because final discard exceptions and perfect-hand bypass rules differ from normal turn rules.
- Model Fifty as a timed claim window tied to the immediate next player and the previous player's discard. The claim changes scoring, not ordinary discard pickup legality after the timer expires.
- Model mistake behavior as rules-preset configuration rather than CPU difficulty alone. Difficulty may influence CPU mistakes only when the active preset allows mistakes.
- Create a CPU strategy module that consumes legal move options and visible table state, then emits move intents. It must never bypass the rules engine.
- Implement CPU difficulties as behavior profiles covering hand evaluation, discard safety, opening pressure, joker use, Fifty awareness, and reaction timing.
- Create a Flutter app module that renders the table, hands, player seats, discard/stock areas, meld zones, Fifty timer, settings, and invalid-action feedback.
- Use a warm Sudanese lounge visual direction: clean dark table, readable ivory cards, warm accents, subtle cultural patterning, and special Fifty treatment.
- Make localization a first implementation concern. User-facing strings should not be embedded in rule logic.
- Create a persistence module for local rule presets, visual preferences, match history, and future profile data.
- Keep online multiplayer, accounts, stores, payments, and online sync outside the first implementation.

## Testing Decisions

- Tests should verify external behavior through public rule-engine APIs, not private helper implementation details.
- The rules module needs the strongest test coverage because it is the deepest module and carries the highest authenticity risk.
- Rules tests should cover deck/card identity, duplicate-deck meld constraints, set validation, sequence validation, low-ace and high-ace behavior, ace opening values, joker placement identity, joker replacement, cover detection, cover discard restrictions, opening benchmark raising and locking, discard pickup pending state, final discard exceptions, perfect-hand finish bypass, Fifty validation, scoring, elimination, stock exhaustion, and mistake penalties.
- CPU tests should verify that each difficulty emits legal move intents and respects rule-engine legality. Strategy quality should be tested through scenario outcomes rather than exact internal scoring formulas.
- UI tests should focus on critical user-visible states once the UI exists: pending discard highlight, Fifty timer visibility, invalid discard feedback, joker identity presentation, and basic table responsiveness.
- Persistence tests should be added once settings and match history exist, focusing on saved rule presets and restoration behavior.
- Golden tests may be useful for stable card/table layout states after the visual system settles, but should not block early rules-engine work.
- Existing scaffold widget tests are only placeholder prior art. They should be replaced once the first real app shell exists.

## Out of Scope

- Online multiplayer.
- User accounts.
- Chat, friends, invitations, or rooms.
- Payments, ad integration, or locked paid cosmetics.
- Full Hareeg 14 implementation.
- Full dedicated Fifties mode implementation.
- Full Arabic UI translation for the first release.
- Advanced challenge puzzles and tutorial hand packs.
- Ranked play or leaderboards.
- Production app-store release work.

## Further Notes

- The canonical Classic Hareeg rule details are documented separately and should drive implementation.
- The first GitHub parent issue should use the `needs-triage` label so implementation work can be broken down through the normal issue flow.
- Product naming is currently Hareeg Table, with the public repository named `hareeg-table`.
- The launch language is English, but Arabic terminology should be preserved where it matters, especially Fifty / Khamsin.
- The visual system should avoid copying existing Hareeg app icons while still communicating cards, fire, and the 50 mechanic.

## Implementation Issue Tracker

- [ ] #2 [HT-01]: Set up app architecture and quality gates
- [ ] #3 [HT-02]: Create main menu and app navigation shell
- [ ] #4 [HT-03]: Create game setup flow for Classic Hareeg
- [ ] #5 [HT-04]: Deal a four-seat Classic Hareeg table
- [ ] #6 [HT-05]: Implement card identity, deck copies, and basic meld validation
- [ ] #7 [HT-06]: Implement joker identity and replacement flow
- [ ] #8 [HT-07]: Implement opening requirement and benchmark pressure
- [ ] #9 [HT-08]: Implement covers and cover discard restrictions
- [ ] #10 [HT-09]: Implement draw, discard pickup, and pending discard state
- [ ] #11 [HT-10]: Implement finish validation and stock exhaustion
- [ ] #12 [HT-11]: Implement Fifty claim flow
- [ ] #13 [HT-12]: Implement scoring, elimination, and round progression
- [ ] #14 [HT-13]: Build round summary, scoreboard, and match end UI
- [ ] #15 [HT-14]: Implement first CPU strategy pass
- [ ] #16 [HT-15]: Add assisted, penalty, and hard table rule presets
- [ ] #17 [HT-16]: Design and implement warm Sudanese lounge table UI
- [ ] #18 [HT-17]: Polish card art, joker treatment, and Fifty visuals
- [ ] #19 [HT-18]: Build settings and persist local preferences
- [ ] #20 [HT-19]: Add pause, resume, and match persistence
- [ ] #21 [HT-20]: Add rules and help reference
- [ ] #22 [HT-21]: Add accessibility, responsiveness, and battery pass
- [ ] #23 [HT-22]: Sync documentation with implemented behavior
