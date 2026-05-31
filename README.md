# Hareeg Table

Hareeg Table is an open-source Flutter card game for offline Classic Hareeg: one human player against three CPU players, with no ads, no locked cosmetics, and a rule engine built around Sudanese table play.

The project is early, but the first playable Classic Hareeg slice is now in place: menu, setup, table deal, core rules modules, CPU move intents, settings, resume storage, and in-app rules help. UI polish and animation treatment are still intentionally light.

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
