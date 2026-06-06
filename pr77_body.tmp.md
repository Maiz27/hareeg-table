## Linked Issue

Closes #66

> Stacked on #76 (HT-44); base auto-retargets to `main` when that merges.

## Summary

- **Deterministic scenario harness**: `PracticeLessonScript` declares a seeded mini-hand board plus ordered teaching steps; `PracticeSession` drives a private `ClassicHareegGameController`, so every practice move is validated by the real rules engine. Steps only narrow which legal actions the surface offers and decide when the mechanic is demonstrated.
- **`PracticeBoard`**: deals a seeded full deck around the lesson's named cards (exact south hand, optional top discard, optional pre-placed melds) so card conservation holds — every physical card exists exactly once.
- **Minimal teaching surface** (`/practice-lesson`): portrait screen showing only the active step's prompt, a compact stock/discard strip, the focused hand, and buttons for the exact legal engine actions the step allows. Hand selection maps onto legal action payloads — a button only appears when the selection matches a real engine action. Engine rejections surface via the existing localized game-message catalog.
- **Turn-rhythm proving lesson** ships now to prove the pipeline end to end (draw → discard); the rest of the core pack lands in HT-46 (#67) on this pattern.
- **Checklist integration**: scripted lessons launch from the hub; unscripted lessons keep the coming-soon notice. Completion persists checklist progress; replay restarts the identical board.
- Practice runs entirely on its own controller — the active-match store is never read or written, so exiting practice cannot corrupt a saved match.

## Rule Behavior Changed

- [x] No rule behavior changed. (Practice consumes the engine through the existing controller seam; no rules were modified.)
- [ ] Rule behavior changed and is covered by tests/docs.

## Tests Run

- [x] `flutter analyze`
- [x] `flutter test` (full suite, 963 passing)

New coverage:

- Session layer (public scenario API): deterministic board replay, 106-card conservation, step-filtered action surface, wrong-action (`notAllowed`) path, real engine-rejection path with rules message.
- Widget flows: launch from checklist, draw→select→discard to completion, progress persisted + hub refresh, replay restarts identical board, saved-match isolation on mid-lesson exit, selection hint, coming-soon notice for unscripted lessons.
- Compact layout: full lesson walk-through at 360×690 logical; also locked in a checklist-tile overflow fix this test exposed.

## Project Tracking

- [x] Issue labels/status are up to date.
- [x] Parent PRD checklist is updated, or this PR does not close an HT issue. (PRD #64 tracker item gets checked post-merge.)

## UI Evidence

New practice lesson surface (prompt card, stock/discard strip, selectable hand, action buttons, completion panel). No screenshots attached yet — pending owner on-device validation (deploy with `adb install -r -d` to keep the live match).

## Follow-ups

- HT-46 (#67): remaining core turn pack lessons (pending discard, meld picker, opening to 51) + "optionally play" copy beat on turn rhythm.
- HT-47 (#68): joker-identity buttons need identity-disambiguated labels (currently both candidates would read "Play Meld").
- HT-48 (#69): Fifty lesson needs a visible claim timer on the surface; strictness-tier explainer may use a dedicated panel instead of a scripted hand.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

<!-- This is an auto-generated comment: release notes by coderabbit.ai -->

## Summary by CodeRabbit

## Release Notes

* **New Features**
  * Added guided practice lessons to teach gameplay mechanics through interactive, step-by-step tutorials
  * Players can replay completed lessons and navigate back from lessons at any time
  * Localized lesson content in English and Arabic

<!-- end of auto-generated comment: release notes by coderabbit.ai -->
