# ADR 0001: Rules Engine Boundary

## Status

Accepted

## Context

Hareeg Table depends on rule authenticity. Classic Hareeg has table-specific behavior around opening benchmarks, covers, jokers, Fifty, scoring, elimination, and mistake presets. These rules must be testable without Flutter UI or CPU strategy interfering with correctness.

## Decision

The Classic Hareeg rules engine will be implemented as pure Dart domain code with no Flutter widget dependency.

The Flutter app consumes game state and legal action descriptions from the rules engine. UI code may present choices, animations, and feedback, but it must not duplicate rule decisions.

CPU strategy consumes visible game state and legal action options, then emits move intents. The rules engine remains responsible for validating and applying those intents.

## Consequences

- Rule behavior can be tested with fast unit tests.
- CPU difficulty cannot bypass legality.
- UI can change without rewriting rule logic.
- Online play can reuse the same rule model later.
- More upfront modeling is required before building polished UI.
