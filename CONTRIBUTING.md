# Contributing

Hareeg Table is early. The most important contribution rule is to preserve Classic Hareeg behavior as documented.

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
