# `TableStrictness` Two-Axis Settings Design

Status: Proposed. Scope: collapse three independent enums plus one bool
(`CpuDifficulty` × `RulePreset` × `TableAids` × `memoryJokerDisplay`) into a
two-axis settings model: `CpuDifficulty` (renamed concept "Opponents") stays as
is; `TableStrictness` replaces the other three.

## 1. `TableStrictness` enum sketch

Add to a new file `lib/domain/classic_hareeg/models/table_strictness.dart`:

```dart
enum TableStrictness {
  coaching('Coaching',  'Blocks illegal moves and surfaces full hints.'),
  standard('Standard',  'Blocks illegal moves, no proactive hints.'),
  strict  ('Strict',    'Allows mistakes with +3 penalty, no hints.'),
  table   ('Table',     'Allows mistakes with +17 and round-out, no hints.');

  const TableStrictness(this.label, this.description);
  final String label;
  final String description;

  static TableStrictness fromName(String? name) => /* falls back to standard */;
}
```

Default = `standard` (more honest first-run than `coaching`, which previously
required two opt-ins).

## 2. Derived properties

Group into two value-object surfaces. The enum itself stays a thin tag; both
surfaces are pure getters/methods, no widget imports either side. The rules
engine must never see UI types and the UI never re-derives rule behavior.

### Rules-side (`lib/domain/classic_hareeg/rules/strictness_rule_profile.dart`)

| Property | Returns | Why |
|---|---|---|
| `blocksIllegalMoves` | `bool` | coaching/standard `true`, strict/table `false`. |
| `mistakePenaltyPoints` | `int` | 0, 0, 3, 17. |
| `removesPlayerOnMistake` | `bool` | only `table`. |
| `allowsTablePlayRetraction` | `bool` | true except for `table`. |
| `fiftyClaimNeedsFinishProofForAdvertise` | `bool` | true only when `blocksIllegalMoves`. |
| `cpuMistakesAllowed` | `bool` | true iff `!blocksIllegalMoves`. |

### UI-side (`lib/ui/core/strictness/strictness_ui_profile.dart`)

| Property | Returns | Replaces |
|---|---|---|
| `showsProactiveHints` | `bool` (only coaching) | `TableAids.showsProactiveHints` |
| `showsMeldPicker` | `bool` (only coaching) | `TableAids.showsMeldPicker` |
| `showsCardValueInInspect` | `bool` (all four) | the `aids == TableAids.tableMode` early-return |
| `inspectVerbosity` | `enum {coaching, terse}` | the two branches inside `_inspectBody` |
| `jokerDisplay` | `JokerDisplay` (coaching/standard → `assisted`, strict/table → `memoryReveal`) | the `widget.preferences.memoryJokerDisplay` ternary |
| `jokerCueDuration` | `Duration?` (null = persistent for coaching/standard, 3s for strict/table) | new |
| `longPressRevealsRepresented` | `bool` (coaching/standard true, strict/table false) | the `_jokerAidsEnabledFor` check |

**Why two profiles, not one fat enum?** ADR-0001 says rule logic must stay free
of UI types. Putting `jokerDisplay`/`jokerCueDuration` on the bare enum would
force the rules-side file to `import` `JokerDisplay` from `lib/ui/core/cards/`.
Splitting keeps the enum in `domain/` clean while the UI-side profile is free
to import any widget enum it needs.

## 3. File placement (ADR-0001 compliance)

- `TableStrictness` enum → `lib/domain/classic_hareeg/models/table_strictness.dart`.
- Rules-side derivations → `lib/domain/classic_hareeg/rules/strictness_rule_profile.dart`.
- UI-side derivations → `lib/ui/core/strictness/strictness_ui_profile.dart`.

## 4. Consumer site inventory

**Domain (rules + game):**
- `lib/domain/classic_hareeg/models/classic_hareeg_setup.dart:46-68,80,92,115,138,148,157,170` — delete `RulePreset`; add `tableStrictness` field.
- `lib/domain/classic_hareeg/rules/mistake_preset_rules.dart:51-103` — switch `preset` param to `strictness`.
- `lib/domain/classic_hareeg/game/classic_hareeg_discard_eligibility.dart:82,101,125`
- `lib/domain/classic_hareeg/game/classic_hareeg_fifty_claim_planner.dart:108,163,175,239` — line 163 `preset == assisted` → `strictness.blocksIllegalMoves`.
- `lib/domain/classic_hareeg/game/classic_hareeg_table_play_retraction_planner.dart:95,164,282,285` — `_hardTableBlock` keyed off `!strictness.allowsTablePlayRetraction`.
- `lib/domain/classic_hareeg/game/classic_hareeg_mistake_consequence_planner.dart:97,107`
- `lib/domain/classic_hareeg/game/classic_hareeg_game_controller.dart:834,847,1483,1644,2114` — every `setup.rulePreset` call site.

**CPU:**
- `lib/cpu/classic_hareeg/cpu_strategy.dart` — no direct change; `CpuDifficulty` stays. `cpuMistakesAllowed` call sites pass `strictness`.

**UI:**
- `lib/ui/features/game_setup/views/new_game_setup_screen.dart:61-126,158,208-225` — drop `RulePreset` segmented button, add `TableStrictness` button.
- `lib/ui/features/settings/views/settings_screen.dart:184-211,343-349,696-734` — assistance accordion collapses; delete `memoryJokerDisplay` switch.
- `lib/ui/features/game_table/views/game_table_screen.dart:394-400,414,513,651-659,683,1989,2004,2731-2790` — `AidsScope` → `StrictnessScope`; joker display from `strictness.jokerDisplay`; `_jokerAidsEnabledFor` → `strictness.longPressRevealsRepresented`.
- `lib/ui/features/game_table/widgets/pause_overlay.dart:37,55,124-127,233-238`
- `lib/ui/core/aids/table_aids.dart` — delete (or keep as deprecation shim for one release).
- `lib/ui/core/scopes/app_scopes.dart:29-48` — rename `AidsScope` → `StrictnessScope`.
- `lib/app/hareeg_table_app.dart:153-154,259-260`

**Data:**
- `lib/data/persistence/preferences_repository.dart:45,51,62,68,92-93,100,122,140,159,165,173,179,191,198` — drop both `memoryJokerDisplay` and `tableAids` fields entirely. Strictness lives on `ClassicHareegSetup`.

**Localization:** `lib/l10n/app_strings.dart` — drop legacy strings; add four strictness labels in `_en` and `_ar`.

## 5. Persistence migration

Follow the `soundDefaultsVersion` pattern but use a `schemaVersion` field inside
the `setup` JSON so the setup model owns its own migration.

**New schema** (`setup` sub-map):
```json
{
  "cpuDifficulty": "casual",
  "starterMode": "human",
  "openingRequirement": 51,
  "deckCount": 2,
  "jokerCount": 2,
  "fiftyTimerSeconds": 4,
  "tableStrictness": "standard",
  "schemaVersion": 2
}
```

**Migration map:**
- `rulePreset=assisted` + `tableAids=guided` → `TableStrictness.coaching`
- `rulePreset=assisted` + `tableAids=standard` → `TableStrictness.standard`
- `rulePreset=assisted` + `tableAids=tableMode` → `TableStrictness.standard` (incoherent → normalize)
- `rulePreset=tablePenalties` + any aids → `TableStrictness.strict`
- `rulePreset=hardTable17` + any aids → `TableStrictness.table`
- `memoryJokerDisplay` is dropped (behavior is now inherent to Strict/Table)

Wrinkle: today `tableAids` lives on `GamePreferences` root JSON, not on `setup`.
So `GamePreferences.fromJson` must hand the legacy `tableAids` string down into
`ClassicHareegSetup.fromJson` for one release.

On `toJson`, write `schemaVersion: 2` inside `setup`, omit `tableAids` and
`memoryJokerDisplay` from the root.

## 6. `ClassicHareegSetup` impact — phasing

**Decision: replace `rulePreset` with `tableStrictness` in one PR, no transition field.**

Model is small, two in-memory call sites (start screen + defaults), migration
is lossless. Two transitional fields would create two sources of truth.

## 7. Mistake permission gating

**Confirm the proposed move.** Today only `ClassicHareegMistakePresetRules.cpuMistakesAllowed`
at `mistake_preset_rules.dart:91-103` reads `CpuDifficulty` for mistakes. Grep
confirms zero production call sites (test-only). After the change:
`cpuMistakesAllowed` takes only `TableStrictness`; coaching/standard block,
strict/table allow. CPU difficulty no longer gates mistake permission.

`CpuDifficultyProfile` (cpu_strategy.dart:65-107) only governs Fifty
timing/miss-chance — unrelated.

## 8. Test surface

- `migrates legacy assisted+guided to TableStrictness.coaching`
- `migrates incoherent hardTable17+guided to TableStrictness.table`
- `coaching and standard block illegal cover discards, strict applies +3, table applies +17`
- `strictness rule profile derivations match agreed ladder`
- `strictness UI profile maps strict and table to memoryReveal joker display`
- `cpuMistakesAllowed returns true only when strictness allows mistakes`

## 9. Open questions

1. **Default tier on fresh install.** Enum declares `standard` as default; doc
   recommends `coaching` for fresh install. These contradict — pick one.
2. **`hardTable17` + `guided` aids legacy combo.** Silently normalize to
   `table` (recommended), one-time toast, or promote to `strict` to preserve
   guided affordances?
3. **`memoryJokerDisplay=true` + `assisted+guided` legacy combo.** Currently
   "briefly show then quiet"; after migration lands in `coaching` and gains
   *persistent* display. Release-note worthy.
4. **`jokerCueDuration` constant.** Hard-code 3s or expose as a tunable on the
   UI-side profile?
5. **`SettingsSection.tableRules`.** After this change the rules section in
   settings shrinks to just a strictness picker. Verify the section enum / route
   stays meaningful or merge with surrounding accordion.

## 10. New files

- `lib/domain/classic_hareeg/models/table_strictness.dart`
- `lib/domain/classic_hareeg/rules/strictness_rule_profile.dart`
- `lib/ui/core/strictness/strictness_ui_profile.dart`
