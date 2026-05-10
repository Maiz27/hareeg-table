# Post Merge Cleanup

This workflow runs after an HT implementation PR merges. It keeps child issues,
the parent PRD checklist, project board state, labels, milestones, and local git
state aligned.

## When To Run

Run this only after the PR is merged into the target branch.

Do not check parent PRD checklist items before merge. A child issue is not done
until its PR has merged and the issue closure has been confirmed.

## Inputs

- Merged PR number.
- Child issue number closed by the PR.
- Parent PRD issue number.
- Branch name used for the PR.

## Confirm Merge State

1. Confirm the PR is merged.
2. Confirm the merge target was the intended base branch.
3. Confirm the PR body includes `Closes #<issue-number>`.
4. Confirm the child issue closed automatically.
5. If the child issue did not close, close it manually with a note linking the
   merged PR.

## Child Issue Cleanup

1. Confirm acceptance criteria were satisfied by the merged PR.
2. Remove stale active labels from the closed child issue if present:
   - `🚧 in progress`
   - `👀 needs review`
   - `⛔ blocked`
   - `✅ ready`
3. Keep useful type, area, priority, and milestone labels on the closed issue.
4. Leave `🙋 hitl` only if there is still a post-merge human follow-up.
5. Confirm milestone state is still correct.

## Parent PRD Checklist

1. Open the parent PRD issue.
2. Find the matching implementation tracker item:
   - `#<issue-number> [HT-##]: <title>`
3. Change that item from unchecked to checked.
4. Do not replace the parent PRD body with a short tracker-only summary.
5. Keep the parent PRD issue open until the first complete Classic Hareeg
   release scope is accepted.

## Project Board

If the repository uses a GitHub Project board:

1. Confirm the merged PR is in the expected project state, if PRs are tracked.
2. Confirm the closed child issue moved to a completed/done state.
3. If automation did not move it, update the project item manually.
4. Confirm the parent PRD project item remains open/in-progress as appropriate.

## Unlock Follow-Up Issues

1. Review the completed issue and parent PRD tracker for issues that were blocked
   by this work.
2. For each newly unblocked issue:
   - confirm its `Blocked by` section is now clear
   - remove `⛔ blocked`
   - add `✅ ready`
   - keep `🙋 hitl` if a human decision is still required
3. Do not mark an issue ready if acceptance criteria or required decisions are
   still unclear.
4. If the completed work revealed new scope, create a follow-up issue instead of
   expanding a closed issue.

## Branch And Local Git Cleanup

1. Confirm all desired commits are on the merged PR.
2. Delete the remote branch if GitHub did not delete it automatically and the
   branch is no longer needed.
3. Switch local checkout back to the default branch.
4. Pull the latest default branch.
5. Delete the merged local branch.
6. Prune stale remote branches.

Example commands:

```text
git switch main
git pull --ff-only
git branch -d HT-##
git fetch --prune
```

## Choose Next Work

1. Return to [Issue To PR](issue-to-pr.md).
2. Pick the lowest unblocked `[HT-##]` issue from the project board or parent PRD
   checklist.
3. Confirm it satisfies the definition of ready before starting.

## Completion Checklist

- [ ] PR merged.
- [ ] Child issue closed.
- [ ] Child issue active labels removed.
- [ ] Parent PRD checklist item checked.
- [ ] Project board state updated.
- [ ] Newly unblocked issues marked ready.
- [ ] Branch cleanup completed or intentionally deferred.
- [ ] Next lowest unblocked issue identified.
