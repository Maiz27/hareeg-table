# Brand Assets

Source brand artwork for Hareeg Table.

## Identity: the Lit card

The mark is a single playing card whose top edge is a flame, with a diamond
pip cut from the card. Masters, lockups (Latin and Arabic), colour versions,
test sheets and the usage guide live in `explorations/identity-2026-10/`
(see its README and `GUIDELINES.md`).

Colour is a system of pairings rather than one tile:

| Where | Ground | Card | Flame |
|---|---|---|---|
| Launcher icon, web icons, store art | Ember `#E4522B` | Ivory `#F8F0DD` | Charcoal `#15110E` |
| Splash, in-app surfaces, README on dark | Charcoal | Ivory | Ember |
| Light surfaces | Ivory | Charcoal | Ember |

## Launcher, splash and web sources (`launcher/`)

Rendered from the masters by `explorations/identity-2026-10/make_launcher.py`
(SVG next to each PNG):

| File | Used by |
|---|---|
| `lit_card_foreground.png`, `lit_card_monochrome.png` | `flutter_launcher_icons` adaptive foreground / themed icon; background is the ember colour in `pubspec.yaml` |
| `lit_card_composite.png` / `.webp` | Legacy and iOS launcher image; the in-app `AppBrandMark` |
| `lit_card_splash.png` | `flutter_native_splash` stamp on charcoal |
| `lit_card_web_icon.png`, `lit_card_web_maskable.png`, `lit_card_favicon.png` | `web/icons/*` and `web/favicon.png` |

Regenerate the platform assets after changing a source:

```powershell
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

## Superseded

`app-icon-concept-v2.png` is the earlier painted concept (felt, fanned cards,
flame, Fifty token). Kept for history; it is no longer the direction.
