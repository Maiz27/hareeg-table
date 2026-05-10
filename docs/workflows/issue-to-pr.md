# Issue To PR

This workflow keeps HT implementation issues, pull requests, labels, milestones, and the parent PRD checklist aligned.

## Starting Work

1. Pick the lowest unblocked `[HT-##]` issue from the project board or parent PRD checklist.
2. Confirm the issue's `Blocked by` section is clear.
3. Assign the issue to yourself.
4. Update labels:
   - remove `🧭 needs triage` when the issue is accepted for active work
   - add `🚧 in progress` when work starts
   - add `⛔ blocked` if a dependency or decision prevents progress
   - keep `🙋 hitl` when human judgment is required
5. Create a branch named with only the issue code:

```text
HT-01
HT-07
HT-16
```

No kickoff comment is required. Assignment and labels are enough.

## During Work

- Keep scope tied to the issue acceptance criteria.
- Do not hide rule questions inside implementation. Create a `❓ question` issue for unclear Classic Hareeg behavior.
- If rule behavior changes, update tests and relevant docs.
- If UI changes, capture screenshots or video for the PR.
- If scope expands, prefer creating a follow-up issue over growing the current one.

## Pull Requests

Open a PR from the issue branch and use the PR template.

Required:

- Link the issue with `Closes #<issue-number>`.
- Summarize the behavior changed.
- List tests run.
- Include UI evidence when screens, cards, animations, or layouts change.
- Note rule behavior changes and docs/tests updated.

Recommended labels:

- `👀 needs review` when ready for review
- relevant type/area labels
- keep `🙋 hitl` for human review items

## After Merge

When the PR merges:

1. The child issue should close automatically through `Closes #...`.
2. Check the matching item in the parent PRD issue checklist.
3. Remove active status labels from the closed issue if they remain.
4. If the completed issue unlocks another issue, update the next issue:
   - remove `⛔ blocked` if no longer blocked
   - add `✅ ready` when it is ready to start
5. Keep the parent PRD issue open until the first complete Classic Hareeg release scope is accepted.

## Definition Of Ready

An issue is ready when:

- Acceptance criteria are clear.
- Blockers are resolved or not applicable.
- Required human decisions are complete, unless the issue itself is labeled `🙋 hitl`.
- The issue has the right type, area, status, priority, and milestone labels.

## Definition Of Done

An issue is done when:

- Acceptance criteria are met.
- `flutter analyze` passes.
- Relevant tests pass.
- Rule changes are covered by tests.
- Rule/product behavior changes are reflected in docs when needed.
- UI changes include screenshot or video evidence.
- The PR is merged.
- The parent PRD checklist is updated.

## Parent PRD Issue

The parent PRD issue tracks the full release scope and child checklist. It should retain the full PRD context, user stories, implementation decisions, testing decisions, and issue tracker checklist.

Do not replace the parent PRD body with a short tracker-only summary.
