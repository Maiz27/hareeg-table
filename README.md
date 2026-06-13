# Hareeg Table

Hareeg Table is an open-source Flutter card game for offline Classic Hareeg: one human player against three CPU players, with no ads, no locked cosmetics, and a rule engine built around Sudanese table play.

The project is early, but the first playable Classic Hareeg slice is now in place: menu, setup, table deal, core rules modules, CPU move intents, settings, resume storage, and in-app rules help. UI polish and animation treatment are still intentionally light.

## Play in your browser

Want to try it without installing anything? Play the latest build right in your browser:

**▶ [maiz27.github.io/hareeg-table](https://maiz27.github.io/hareeg-table/)**

No install, no sign-up — it runs offline once loaded. On a phone, turn it sideways (landscape) for the table. The web build saves your progress locally in that browser; for the full experience, grab the Android APK from [Releases](https://github.com/Maiz27/hareeg-table/releases).

## Why this exists

I built Hareeg Table because I got tired of a Hareeg app that didn't respect the person playing it.

It had ads. I put up with them. Then one match, while I was offline, it threw a blank white box onto the screen and made me sit there waiting to "watch" an ad that was never going to load. No internet, no ad, nothing actually there. It paused my game to show me a void, and they didn't even get paid for the interruption.

That was the moment. If an app will break a game you're enjoying to show a loading screen for nothing, the bar is on the floor. So I wrote my own.

Hareeg Table is offline-first and ad-free. It doesn't interrupt your hand to entertain itself. The only thing it ever sends is a bug report, and only if you tap the button or hit a crash. Never your name, never your data, never mid-game.

## Product Direction

- App display name: Hareeg Table
- Repo name: hareeg-table
- Primary launch language: English
- Planned localization: Arabic
- Default mode: Classic Hareeg, human + 3 CPUs
- Design direction: warm Sudanese lounge
- Signature mechanic: Fifty / Khamsin
- Mobile orientation: portrait for menu/setup/help/settings, landscape for the table screen

## Getting Started

### Prerequisites

- Flutter with the Dart SDK constraint `^3.10.8` (see `environment: sdk:` in `pubspec.yaml`).

### Build and run

```sh
flutter pub get
flutter run
```

### Test

```sh
flutter test
```

## Project structure

Rule logic is pure Dart in the domain layer; the Flutter app presents state and input. See [ADR 0001](docs/adr/0001-rules-engine-boundary.md).

- `lib/app` — app shell, routing, and top-level wiring.
- `lib/cpu` — CPU strategy and move planners (consume visible state, emit intents).
- `lib/data` — repositories and persistence storage.
- `lib/domain` — pure-Dart game rules and models. The Classic Hareeg engine lives in `lib/domain/classic_hareeg/{game,models,rules,persistence}`.
- `lib/l10n` — localization.
- `lib/ui` — Flutter widgets, screens, and themes.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full development workflow.

## Docs

- [Classic Hareeg rules](docs/rules/classic-hareeg.md)
- [Design direction](docs/design/direction.md)
- [Product PRD](docs/product/prd.md)
- [Future ideas](docs/roadmap/future-ideas.md)
- [Release workflow](docs/workflows/release.md)

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for setup and
the pull-request flow, [SECURITY.md](SECURITY.md) for reporting vulnerabilities,
and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for community expectations.

## License

The **source code** in this repository is licensed under the
[MIT License](LICENSE).

The **Hareeg Table name, logos, and brand assets** (including everything under
`assets/brand/`) are **not** covered by the MIT license and remain reserved. You
may build, modify, and redistribute the code, but please do not ship a derivative
under the Hareeg Table name or use its logos in a way that implies endorsement.

Bundled audio in `assets/sounds/kenney_casino/` is by
[Kenney](https://kenney.nl) under CC0.
