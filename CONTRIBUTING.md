# Contributing

Hareeg Table is early. The most important contribution rule is to preserve Classic Hareeg behavior as documented.

By contributing, you agree that your contributions are licensed under the
repository's [MIT License](LICENSE). There is no CLA to sign. Please also review
the [Code of Conduct](CODE_OF_CONDUCT.md).

## Contributing from outside

You do **not** need to be part of the internal issue process to help:

1. Open an issue first (bug or feature request) so we can agree on scope. For
   rule-behavior questions, check the [Classic Hareeg rules](docs/rules/classic-hareeg.md) first.
2. Fork the repo and create a branch off `main`.
3. Make your change with tests, run `flutter analyze` and `flutter test`.
4. Open a pull request against `main` using the PR template, link the issue, and
   list the tests you ran. Include screenshots or video for UI changes.

That's it. CI must pass and a maintainer will review.

> The `HT-##` branch names, PRD parent checklists, and `🙋 hitl` / triage labels
> described below are the maintainer's internal tracking flow. Outside
> contributors can ignore them — a normal issue and PR is all you need.

## Local Setup

```powershell
flutter pub get
flutter analyze
flutter test
```

## Branches

Use issue-prefixed branch names:

```text
HT-01
HT-07
```

## Commits

Use concise conventional-style commits:

```text
feat: add opening benchmark state
fix: block joker discard outside final finish
docs: clarify Fifty scoring
test: cover ace opening values
```

## Pull Requests

Every PR should link an issue and list tests run. UI changes should include screenshots or video. Rule behavior changes should update tests and documentation when needed.

## Rule Accuracy

Do not put game-rule decisions directly in widgets. Rule behavior belongs in the pure Dart rules engine and should be covered by tests.

## Workflows

See [Issue To PR](docs/workflows/issue-to-pr.md) for how to pick up an HT issue, branch, open a PR, and update the parent PRD checklist.

Agent skills are optional workflow aids. See [Agent Skill Use](docs/workflows/agent-skill-use.md) for how agents should decide when Dart or Flutter skills apply to the current task.
