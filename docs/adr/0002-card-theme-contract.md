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
