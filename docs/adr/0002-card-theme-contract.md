# ADR 0002: Card Theme Contract

## Status

Accepted

## Context

HT-16 moves the app from placeholder card rendering to a reusable table visual system. The table needs readable cards across compact Android landscape layouts, multiple visual themes, represented joker identities, memory-oriented joker display, state overlays, and bundled asset attribution without tying the rules engine to Flutter painting details.

## Decision

Card visuals are rendered through `HareegCardTheme`, `CardRenderRequest`, and `HareegCardView`.

Each card theme owns its face/back artwork for full, compact, picker, and back variants. The shared `HareegCardView` applies visual states such as selected, pending discard, and cover target. Joker identity display is controlled by `JokerDisplay`, with table-wide preference inheritance through `JokerDisplayScope` and explicit overrides for isolated previews.

Themes can be code-rendered or backed by bundled assets. Asset-backed themes must expose attribution through the theme contract so Settings/About can surface licensing.

## Consequences

- The rules engine stays independent from UI and asset concerns.
- Table widgets can switch themes without duplicating card-state overlay logic.
- Represented joker display and memory-mode behavior are consistent across hand, discard, meld, and animation surfaces.
- New themes must implement the full contract and prove compact readability before being exposed to players.
- Themes must pass `test/ui/core/cards/card_face_asset_consistency_test.dart` — for every (rank, suit) the theme's returned asset path must contain both the rank slug and the suit slug, OR be `null` (deferring to the code-rendered painter). Added in HT-33 after a `sandline_lounge/jack_diamonds.webp` slot was found holding J♥ artwork; the test prevents the asset map and the artwork from drifting silently again.

## Update — 2026-05-25

"Each theme owns its face/back artwork" is now expressed via a value-object data shape, not via subclassing. `HareegCardTheme` is a concrete `const`-constructible class carrying its palette, asset manifest, identity (`id`, `label`, `description`), provenance (`source`, `licenseAttribution`, `sourceUrl`), the `readableOnCompactLayouts` claim, and an optional `paintExtras` callback for the rare theme that needs a flourish on top of the shared `CardPainting` helpers (currently Kenney Classic's mid-line sand stroke). The bundled themes are now `const` literals in `lib/ui/core/cards/themes/bundled_themes.dart`; the per-theme subclass files are gone.

The contract surface seen by callers (`HareegCardTheme`, `CardRenderRequest`, `HareegCardView`, `CardThemeRegistry.byId`, the persisted `id` strings — `sandline_lounge`, `iron_rose`, `minimal_symbols`, `kenney_classic`, `wikimedia_english_pattern`) is unchanged. What changed is that the contract is implemented by data, not by inheritance.

`test/ui/core/cards/card_face_asset_consistency_test.dart` remains the durability mechanism that prevents asset drift across this refactor and any future theme additions: every bundled theme's asset manifest is still exercised against every (rank, suit) pair, and any newly introduced theme — literal or otherwise — must pass the same gate before being added to the registry.
