# End-of-Match Screen Design

Status: Proposed. Phase D of `synthesis.md`. Independent of Phases A-C.

Reads:
- `direction.md` — Warm Sudanese Lounge visual language.
- `table-strictness.md` — `TableStrictness` axis referenced in §7.
- `lib/ui/features/round_summary/views/round_summary_screen.dart` — the dead screen.
- `lib/ui/features/game_table/views/game_table_screen.dart` — `_RoundResultOverlay`, `_MatchWinnerLine`, `_persistAndMaybeFinish`, `_showRoundResultOverlay`.
- `lib/ui/features/game_table/table_persistence_planner.dart` — `abandonActiveMatch` path on match end.
- `lib/domain/classic_hareeg/rules/match_progression_rules.dart` — `MatchProgressState.matchWinner`.
- `lib/app/hareeg_table_app.dart` — `/table` and `/round-summary` routes.

## 1. Promote vs new screen

**Decision: build a new `MatchOverScreen`. Delete `RoundSummaryScreen` and its route in the same PR.**

`RoundSummaryScreen` was designed as a hybrid — its `_NextStepLine` toggles between "Match winner" and "Next starter" headers, and its action area swaps between *Continue* and *Return to menu*. That hybrid only made sense when both round-end *and* match-end were going to land on a full-screen route. Today the live table renders round-end inline via `_RoundResultOverlay`, and the user has explicitly preferred that for round-end (no pull-out, no orientation change, fast turnover). The round-summary route is dead and is not coming back; keeping its co-tenancy with match-end forces both surfaces to compromise.

A dedicated `MatchOverScreen` is a small file (~250 LOC, similar mass to the dead screen). It owns one job: deliver closure when the match ends. It can lean into the visual hierarchy (winner reveal at full display weight, scoreboard secondary, actions tertiary) without juggling the round-end shape. The `_ScoreSection` / `_ScoreLine` widget pattern from the dead screen is reusable — extract `_FinalStandingsTable` from it, not the whole screen.

Net: replace 369 LOC of dead code + dead route plumbing with ~250 LOC of one-purpose screen. Less coupling, clearer surface, no premature reuse.

## 2. Layout sketch

Portrait, single scrollable column, centered medallion motif behind content. Landscape table-screen transitions to this on `Navigator.pushReplacement`, which lets the portrait lock take effect (see §4).

```
+----------------------------------------------------+
|                                                    |
|        [ medallion motif, sandLine, opacity .06 ]  |   <- _BackdropMotif (scaled 320dp)
|                                                    |
|                                                    |
|                MATCH OVER                          |   <- titleSmall, goldAccent, letter-spaced
|                                                    |
|                                                    |
|             ###  YOU WIN  ###                      |   <- display style, scale 1.4x, goldAccent
|         ( or: CPU East wins the match )            |      animated entry (see §3)
|                                                    |
|         _____________________________              |   <- thin sand-line divider, opacity .24
|                                                    |
|        FINAL STANDINGS                             |   <- titleSmall, mutedText
|                                                    |
|  1.  You              -3                           |   <- winner row: goldAccent text, trophy icon
|     -------------------------------                |
|  2.  CPU North        +31    eliminated R5         |   <- losers: offWhiteText, mutedText footnote
|     -------------------------------                |
|  3.  CPU West         +34    eliminated R4         |
|     -------------------------------                |
|  4.  CPU East         +38    eliminated R3         |
|                                                    |
|         _____________________________              |
|                                                    |
|        7 rounds played                             |   <- bodyMuted
|                                                    |
|                                                    |
|     [  Return to menu  ]   <- FilledButton (gold)  |
|     [  New match, same setup  ] <- OutlinedButton  |
|                                                    |
|        [ thin border motif, bottom ]               |
+----------------------------------------------------+
```

Hierarchy beats:

- **Beat 1, headline**: `MATCH OVER` eyebrow + winner name in `display` weight scaled to ~38pt. South-wins variant uses the localized "You" personalization (`strings.youWinTheMatch`). CPU-wins uses `strings.seatLabel(winner)` (`CPU East`, `CPU North`, `CPU West`).
- **Beat 2, standings**: a four-row table sorted by final score ascending (lower is better). Winner row has the trophy icon, `goldAccent` text, and a soft `selectedGlow` background tint. Each eliminated row shows the round it was eliminated in as muted footnote text. Final score uses `numericChip` style with a `+` prefix on positives.
- **Beat 3, match meta**: round count, derived from `presentation.progress.scores`'s underlying snapshot `roundNumber`. Single muted line.
- **Beat 4, actions**: gold `FilledButton` for *Return to menu* (primary), outlined `New match, same setup` (secondary). No "Resume" button — match is abandoned.

Background uses the same `_SummaryBackdrop` pattern from the dead screen (top-right medallion at 0.052 opacity, bottom border motif at 0.08 opacity), preserving the lounge frame.

## 3. Motion

All durations are at `TableMotion` normal speed and scale via `MotionScope.of(context).scale(...)`:

| Beat | Animation | Base duration | Reduced-motion behavior |
|---|---|---|---|
| Mount | Backdrop fade-in | 320ms | Same duration, no offset |
| Headline | "MATCH OVER" eyebrow fades in | 220ms after 80ms | Skip the stagger, just fade |
| Headline | Winner name scales 0.92 → 1.0, fade-in | 360ms after 220ms | Fade only, no scale |
| Headline | Medallion behind name pulses opacity 0.06 → 0.12 → 0.06, **once** | 1200ms | Skip pulse entirely |
| Standings | Rows stagger-fade in top-to-bottom | 100ms each, total ~500ms | Single 220ms fade for the whole block |
| Actions | Buttons fade in last | 200ms after 720ms | Same |

**No confetti, no particles, no flame burst.** Per `direction.md`: "Avoid casino neon, childish cartooning, and constant flame decoration." Flame is reserved for Fifty. The match-end celebration is a quiet medallion pulse + the gold-accent winner row glow. The Sudanese lounge feels solemn-warm at the close, not loud.

Audio: one new cue `TableSoundEvent.matchEnd` — a single sustained chime or oud-string-pluck (asset choice deferred to audio direction). Fires once on first frame. Respects `audio.enabled`. No looped victory bed.

Haptic: one `TableHapticEvent.matchEnd` heavy-impact on first frame, only if winner is south. CPU wins skip the haptic — the human doesn't want congratulatory haptics for losing.

## 4. Navigation flow

```
[live table, landscape]
   |
   | round ends, _persistAndMaybeFinish runs
   v
[planner returns matchComplete scenario]
   |
   | abandonActiveMatch() succeeds
   v
[_showRoundResultOverlay still shows _RoundResultOverlay briefly]   <- hold ~1400ms
   |                                                                   so the player reads
   | new auto-transition: when winner != null and overlay has        the final round score
   | been visible for `_matchEndOverlayDwell` (1400ms), call
   | Navigator.pushReplacementNamed(AppRoutes.matchOver, args)
   v
[GameTableScreen.dispose runs]
   |
   | dispose calls AppOrientation.usePortrait()  <- already exists
   v
[MatchOverScreen mounts, portrait, plays motion]
   |
   | user taps "Return to menu"
   v       OR
[Navigator.pushNamedAndRemoveUntil(AppRoutes.home, (r) => false)]
   |
   | user taps "New match, same setup"
   v
[Navigator.pushReplacementNamed(AppRoutes.table, arguments: setup)]
   |
   | GameTableScreen mounts with the same ClassicHareegSetup,
   | initialSnapshot null, deals fresh round 1
```

The 1400ms overlay dwell preserves the existing round-score reading affordance (today the round-result overlay is the only place the human sees the final round's per-seat scoring math). Without it, the user is thrown into the celebration screen before they've read why they won. The dwell is `MotionScope.scale`-d like everything else.

`_RoundResultOverlay` keeps its current `_MatchWinnerLine` row as a fallback in case the navigation fails (defense-in-depth — the `Menu` button there still works).

## 5. Persistence interaction

Today `ClassicHareegTablePersistencePlanner.plan` returns `scenario: matchComplete` with `action: abandonActiveMatch` when `nextRoundSnapshot == null`. No persistence change needed for this feature. The end screen reads only from `ClassicHareegRoundResultPresentation` — the same payload the overlay already gets — plus the `ClassicHareegSetup` (passed for rematch). Both are in-memory; no repository call from `MatchOverScreen` itself.

Route arguments shape:

```dart
class MatchOverArguments {
  final MatchProgressState progress;      // for matchWinner, final scores, activeSeats
  final Map<PlayerSeat, int> previousScores;
  final RoundProgressResult finalRound;   // for "won by Fifty" / "won by finish" subline
  final int roundsPlayed;                 // from controller snapshot roundNumber
  final ClassicHareegSetup setup;         // for the rematch button
  final Map<PlayerSeat, int> eliminatedRound;  // seat -> round it was eliminated
}
```

`eliminatedRound` is the one new piece of state. The controller already knows when each seat crosses the elimination score (it happens inside `applyRoundResult`). Track it on the controller as `Map<PlayerSeat, int> _seatEliminatedRound` keyed by the round number at the time, populated alongside each `MatchProgressState` apply. Read at match end. **This is purely additive controller state, no rules-engine change.** Eliminations happen in `MatchProgressState`; the controller wraps the rules call and is allowed to memo what it sees.

## 6. Localization strings

All new strings in both `_en` and `_ar`. Voice follows existing tone: terse, neutral, no exclamation marks. RTL handled by `AppStrings.isRtl` like the rest.

| Key | English | Arabic |
|---|---|---|
| `matchOver` | `Match over` | `انتهت المباراة` |
| `youWinTheMatch` | `You win the match` | `فزت بالمباراة` |
| `matchWinnerSouth` (helper, reuses `playerWinsMatch` for CPU) | n/a | n/a |
| `finalStandings` | `Final standings` | `الترتيب النهائي` |
| `eliminatedInRound(int round)` | `Eliminated in round N` | `خرج في الجولة N` |
| `roundsPlayed(int rounds)` | `N rounds played` (singular: `1 round played`) | `لُعبت N جولة` (دلال العدد: `لُعبت جولة واحدة`) |
| `newMatchSameSetup` | `New match, same setup` | `مباراة جديدة، نفس الإعدادات` |
| `wonByFifty` | `Won by Fifty` | `فاز بالخمسين` |
| `wonByFinish` | `Won by finish` | `فاز بإنهاء الجولة` |

`returnToMenu`, `seatLabel`, `playerWinsMatch`, `matchWinner` already exist and are reused. Drop `roundSummary` and `continueNextRound` only if the round-summary route is deleted in the same PR (recommend yes — otherwise leave them for now).

Arabic plural for round count: simplified two-form (1 vs N) — Hareeg matches rarely exceed 12 rounds so the exact dual/plural distinction is not worth the wiring. Match the existing `decksValue` / `fiftySecondsValue` precedent.

## 7. TableStrictness tier interaction

**Decision: tier-independent. One end screen for all four tiers.**

The arguments for a stripped `Table`-tier end screen (real-table feel, no celebration) don't survive scrutiny. Even at a real table, the *end of a match* is when you stop and acknowledge the winner — quiet, but not invisible. The Table tier already strips hints *during play* where the immersion matters; the end-of-match screen is a natural break in the game where chrome and closure are expected.

What the Table tier *does* skip: the haptic celebration when south wins (already CPU-only above), and the optional medallion pulse (treat the pulse as `motionSpeed.reduced` does — skip it). Implement that as a single `strictness.isTableTier` check that gates the same code as `reduced`.

## 8. Rematch flow

`New match, same setup` calls:

```dart
Navigator.of(context).pushNamedAndRemoveUntil(
  AppRoutes.table,
  (route) => false,
  arguments: args.setup,  // the original ClassicHareegSetup
);
```

`/table` already accepts a `ClassicHareegSetup` argument and treats it as a fresh start (no `initialSnapshot`). The setup carries `cpuDifficulty`, `tableStrictness` (post-A1), `deckCount`, `jokerCount`, `fiftyTimerSeconds`, `openingRequirement`, `starterMode` — every house-rule axis. `removeUntil(false)` clears the back-stack so the player can't navigate back into the dead match-over screen.

If the user instead taps *Return to menu*, the same `pushNamedAndRemoveUntil(AppRoutes.home, ...)` pattern from `_returnToMainMenu` is reused.

## 9. Test surface

Widget tests in `test/ui/features/match_over/match_over_screen_test.dart`:

1. `south win — shows "You win the match" headline, gold trophy on row 1, no haptic-CPU branch invoked` (CPU wins assertion in test 2).
2. `east win — shows "CPU East wins the match", row 1 highlights east, south appears as eliminated`.
3. `final standings — sorted by score ascending, all four seats listed with final score and elimination round`.
4. `Fifty-finish ending — final-round subline reads "Won by Fifty"`.
5. `normal-finish ending — final-round subline reads "Won by finish"`.
6. `round count — shows correct "N rounds played" for roundsPlayed = 1, 5, 12`.
7. `return-to-menu button calls Navigator.pushNamedAndRemoveUntil with AppRoutes.home`.
8. `rematch button calls Navigator.pushNamedAndRemoveUntil with AppRoutes.table and the same setup`.
9. `Arabic locale — all labels render RTL, "خارج" eliminated marker visible, action button order mirrored`.
10. `reduced motion — medallion pulse and row stagger are suppressed, headline still readable`.
11. `Table strictness tier — medallion pulse suppressed, no celebratory haptic`.

Integration test in `test/ui/features/game_table/game_table_match_end_test.dart`:

12. `live table → final round → 1400ms dwell on overlay → auto-navigates to MatchOverScreen → match repository abandonActiveMatch was called exactly once`.

## 10. Open questions

1. **Match-end audio cue source.** Need an oud pluck or chime asset that fits the lounge palette. Defer to whoever owns `audio_cue_registry.dart` additions.
2. **Per-seat highlights (most Fiftys claimed, biggest single-round swing).** Requires new per-match tracking (`_seatFiftyClaimCount`, `_seatLargestRoundDelta`). Genuinely nice but ~3 days of work and risks adding stats-grind feel to a game that's meant to feel like a table. **Defer to v2** unless the user explicitly asks.
3. **Overlay dwell duration.** `_matchEndOverlayDwell = 1400ms` is a guess based on average player reading speed for the four-seat round result. If playtesting shows it's too long (impatient) or too short (missed score math), tune in one place.
4. **Back-button behavior on MatchOverScreen.** Hardware back from the end screen — go to home, or trap and force the user to pick an action? Recommend: trap, since both visible actions (menu, rematch) clear the stack anyway. `WillPopScope` returning `false` while showing a `SnackBar` reminding the player to pick.
5. **Animated entry while OS reduced-motion is on but app `motionSpeed.normal`.** `MotionScope` already collapses these correctly via `effectiveSpeed`. No new logic needed.
6. **Rematch and the seed.** `ClassicHareegSetup` doesn't currently carry a deal seed — a rematch will re-shuffle. Confirmed-acceptable: rematch is "same rules, fresh deal," not "replay this exact deal."
