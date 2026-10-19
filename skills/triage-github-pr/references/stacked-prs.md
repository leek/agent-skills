# Stacked PRs

A PR is **stacked** when its base is another open PR's head branch. The PRs chained
that way, down to the one whose base is the **trunk** (the default branch, or a deploy
branch the project context names), are one **stack**. Each branch carries the commits
of every PR below it, so a stack lands **bottom-up, one PR at a time, with merge
commits**, and each merge is followed by a **retarget** of the PR above it.

## Build the stack

```bash
gh pr view N --json number,baseRefName,headRefName,headRefOid
gh pr list --state open --json number,headRefName,baseRefName --limit 200   # find each base's PR
```

Walk down from each named PR: while its `baseRefName` is the head of an open PR, step to
that PR. The PR you stop on has the trunk as its base: the **bottom**. Walk up the same
way for PRs based on a named PR's head (`gh pr list --base <head> --state open`).

- **An unnamed PR below a named one** gates it: the named PR cannot land before it. Ask
  once, as a merge question, whether to take the whole chain from the bottom; otherwise
  stop that PR with the unmerged base as its blocker.
- **An unnamed PR above a named one** is not yours to merge, but it is retargeted after
  the merge below it (step 3), so it stays open on the right base.

Completion criterion: every named PR sits in an ordered chain from the trunk upward,
with each unnamed PR in it either included by the user or named as a blocker.

## Merge method

Every PR in a stack merges with **`--merge`** (a merge commit), whatever the repo's
`## Merge method` says for lone PRs. A squash or rebase merge writes new commits on the
trunk, so the branch above still carries the originals: its diff grows by everything
below it, or conflicts.

Check the repo allows it before the first merge:

```bash
gh repo view --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed,deleteBranchOnMerge
```

When `mergeCommitAllowed` is false, ask once before merging anything, as a merge
question: allow merge commits for the run, or squash and **restack** each PR above
(rebase it onto the new trunk, which needs a force push this skill never makes, so the
restack is the user's to run). The answer covers the whole stack.

## Merge in order

The merge approval in step 6 covers the stack as one decision: ask it once, naming the
order (`#101 → #102 → #103`). Then, for each PR from the bottom up:

1. **It merges only while its base is the trunk.** A PR whose base is still another
   PR's head is never merged: merging it would land its changes on that branch, not the
   trunk.
2. **Merge** with the pinned head and a merge commit, per
   [Merge](gh-mechanics.md#merge): `gh pr merge N --merge --match-head-commit <sha>`.
   When required checks are pending, `--auto` queues it; the PRs above wait for that
   merge to land, so stop the stack there and report it queued.
3. **Retarget** each PR based on its head to the merged PR's base. GitHub does this by
   itself only when the merged head branch is deleted; this skill deletes nothing, so
   retarget explicitly and skip a PR whose base already reads the trunk:

   ```bash
   gh pr view M --json baseRefName --jq .baseRefName
   gh pr edit M --base <trunk>
   ```

4. **Re-check the retargeted PR** before its own merge, as step 6 does. Its head did
   not move, so the review of that head still covers it and `--match-head-commit` pins
   the same sha. Its diff against the trunk should name the same files it did against
   its old base (`gh pr view M --json files`). A file it did not carry before means a
   commit below was rewritten: stop and report it rather than merging the extra change.
   `mergeable` reads `UNKNOWN` for a moment after a retarget; re-poll as
   [Merge gates](gh-mechanics.md#merge-gates) says.

Completion criterion: every PR in the chain is merged in order (or the run stopped on a
named one), and every open PR that was based on a merged head now targets the trunk.

## Fixes inside a stack

A fix pushed to a lower PR must reach the PRs above it. After the lower PR's batch is
pushed, merge its branch into the next branch up, then that one into the next, with
plain merge commits and plain pushes (never a rebase or a force push). Each such push
is a batch for that PR: combine it with the fixes that PR needs, so it costs one push,
not two. A conflict that changes intent is a stop case.

The merged-in commits were reviewed on their own PR. On each upper PR, review its own
fixes plus any conflict resolution in the merge commit
(`git diff <merge commit>^1 <merge commit>` shows what the merge changed there).

## Report

Per PR: its merge commit SHA (or "queued"), and each PR it retargeted.
