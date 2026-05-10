# Agent Skill Use

Agent skills are optional workflow aids. They should be used when the current task matches the skill's purpose, not because an issue has a specific `[HT-##]` number.

## Principle

Use skills to improve correctness and repeatability for the task at hand. Do not turn skill use into ceremony. A small rules-engine change may need only focused unit tests; a UI layout issue may benefit from Flutter layout or widget-test skills.

Project rules still take precedence:

- Classic Hareeg rule behavior belongs in pure Dart domain code.
- Flutter UI consumes state and legal actions from the rules engine.
- CPU strategy emits move intents and must not bypass legality.
- Rule changes need tests and documentation updates when behavior changes.

## Dart Skills

Consider Dart skills for pure Dart code, rule-engine work, package problems, and test coverage.

Recommended task matches:

- Adding or changing rules-engine behavior.
- Writing unit tests for Dart classes, functions, or value objects.
- Fixing analyzer warnings or mechanical lint issues.
- Resolving `pub get` or package version conflicts.
- Collecting coverage when evaluating rule/test completeness.
- Using modern Dart pattern matching where it improves clarity.

Useful skills from `dart-lang/skills`:

- `dart-add-unit-test`
- `dart-run-static-analysis`
- `dart-collect-coverage`
- `dart-resolve-package-conflicts`
- `dart-use-pattern-matching`

## Flutter Skills

Consider Flutter skills for UI structure, widgets, layout, localization, integration tests, and app architecture.

Recommended task matches:

- Creating or changing Flutter widgets.
- Adding widget tests.
- Adding integration tests for user flows.
- Fixing layout overflow or constraint issues.
- Building responsive phone/tablet layouts.
- Setting up localization.
- Reviewing Flutter architecture against project boundaries.
- Creating widget previews when useful for design review.

Useful skills from `flutter/skills`:

- `flutter-apply-architecture-best-practices`
- `flutter-add-widget-test`
- `flutter-add-integration-test`
- `flutter-build-responsive-layout`
- `flutter-fix-layout-issues`
- `flutter-setup-localization`
- `flutter-add-widget-preview`

## When Not To Use A Skill

Do not use a skill when:

- The task is a small docs-only update.
- The skill's workflow would add more overhead than value.
- The skill's advice conflicts with the project ADR or Classic Hareeg rules.
- The task is blocked by a product/rule decision rather than implementation.

## Updating Installed Skills

If Dart or Flutter skills are installed into the repo, update them with:

```powershell
npx skills update
```

Review any changes before committing updated skill files.
