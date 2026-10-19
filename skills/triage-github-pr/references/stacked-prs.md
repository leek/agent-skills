# Stacked PRs

A PR is **stacked** when its base is another open PR's head branch. The PRs chained
that way, down to the one whose base is the **trunk** (the default branch, or a deploy
branch the project context names), are one **stack**. Each branch carries the commits
of every PR below it, so a stack lands **bottom-up, one PR at a time, with merge
commits**, and each merge is followed by a **retarget** of the PR above it.

## Build the stack

```bash
gh pr view N --json number,baseRefName,headRefName,headRefOid,isCrossRepository
gh pr list --head <baseRefName> --state open --json number,headRefName,baseRefName,isCrossRepository   # the PR whose head is that base
gh repo view --json defaultBranchRef --jq .defaultBranchRef.name
```

Walk down from each named PR: while its `baseRefName` is the head of an open PR with
`isCrossRepository` false, step to that PR. A fork's branch can share the name (a fork
PR from its own `main`), but a base is always a branch of this repo, so a cross-repo PR
is never a parent. Stop on the PR whose base is the trunk: the **bottom**. A base that
is neither the trunk nor an open PR's head (its PR closed, or a stray branch) is a
blocker for every PR above it: report it, never merge into it. Walk up the same way for
PRs based on a named PR's head (`gh pr list --base <head> --state open`).

- **An unnamed PR below a named one** gates it: the named PR cannot land before it. Ask
  once, as a merge question, whether to take the whole chain from the bottom; otherwise
  stop that PR with the unmerged base as its blocker. A PR the user includes is worked
  like a named one, steps 1–7 with its own fix budget, never merged unreviewed.
- **An unnamed PR above a named one** is not yours to merge or push to, but it is
  retargeted after the merge below it (step 3), so it stays open on the right base.

A **native GitHub stack** (made with `gh stack`, generally available since
[2026-10-06](https://github.blog/changelog/2026-10-06-stacked-pull-requests-generally-available))
is different: `gh stack merge` lands every PR up to the chosen one in one atomic
operation. Check each PR's timeline for a stack event before the first merge:

```bash
gh api --paginate repos/{owner}/{repo}/issues/N/timeline --jq '[.[] | select(.event // "" | test("stack"))] | length'
```

A non-zero count means the PR is in a native stack. The per-PR flow below is not
checked against one, so ask once, as a merge question, whether to land the stack with
`gh stack merge <top named PR>` (the user's command to run) or to hold.

Completion criterion: every named PR sits in an ordered chain from the trunk upward,
with each unnamed PR in it either included by the user or named as a blocker, and no
PR is in a native stack the user has not decided on.

## Merge method

Every PR in a stack merges with **`--merge`** (a merge commit), whatever the repo's
`## Merge method` says for lone PRs. A squash or rebase merge writes new commits on the
trunk, so the branch above still carries the originals: its diff grows by everything
below it, or conflicts. A method the user named in the request (`squash`, `rebase`)
does not apply silently to a stack: ask once, as a merge question, whether to merge
the stack with merge commits or hold it.

Check the repo allows it before the first merge:

```bash
gh repo view --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed,deleteBranchOnMerge
```

When `mergeCommitAllowed` is false, the stack cannot land through this skill: changing
the repo setting and restacking each PR above with a force push are both the user's to
do. Stop the stack before merging anything, name those two ways forward in the report,
and continue only after the user says which one they took (re-read
`mergeCommitAllowed` if they enabled it).

## Merge in order

The merge approval in step 6 covers the stack as one decision: ask it once, naming the
order (`#101 → #102 → #103`). Then, for each PR from the bottom up:

1. **It merges only while its base is the trunk.** A PR whose base is still another
   PR's head is never merged: merging it would land its changes on that branch, not the
   trunk.
2. **Merge** with the pinned head and a merge commit, per
   [Merge](gh-mechanics.md#merge): `gh pr merge N --merge --match-head-commit <sha>`.
   When required checks are pending, `--auto` queues it; the PRs above wait for that
   merge to land, so stop the stack there and report it queued, naming the retarget
   each PR above still needs once it lands (step 3's `gh pr edit`), unless
   `deleteBranchOnMerge` is true and GitHub retargets them itself.
3. **Retarget** each PR based on its head to the merged PR's base. GitHub does this by
   itself only when the merged head branch is deleted; this skill deletes nothing, so
   retarget explicitly and skip a PR whose base already reads the trunk. First record
   the commits the PR carries on top of the merged head, so step 4 has something to
   compare against:

   ```bash
   git fetch origin
   git rev-list <merged PR's head sha>..<M head sha> > <scratch file for M>   # before the retarget
   gh pr view M --json baseRefName --jq .baseRefName
   gh pr edit M --base <trunk>
   ```

4. **Re-check the retargeted PR** before its own merge, as step 6 does. Its commits on
   top of the trunk must be the ones recorded in step 3: `git fetch origin <trunk>`,
   then `git rev-list origin/<trunk>..<M head sha>` must match that recorded list. An extra
   commit means the history below M is not what landed (a lower commit was rewritten):
   stop and report it rather than merging the extra change. The retarget does not move
   the head, so the review of that head still covers it and `--match-head-commit` pins
   the same sha, unless the repo requires up-to-date branches: then M reads `BEHIND`,
   because the trunk now has the merge commit M lacks. Update it as
   [Merge gates](gh-mechanics.md#merge-gates) says, inside M's push budget and combined
   with its batch, then review and pin the new head; with no push left it is a blocker.
   `mergeable` reads `UNKNOWN` for a moment after a retarget; re-poll as Merge gates
   says.

Completion criterion: every PR in the chain is merged in order (or the run stopped on a
named one), and every open PR that was based on a merged head now targets the trunk or
is named in the report with the retarget it still needs.

## Fixes inside a stack

A fix pushed to a lower PR reaches the PRs above it through the trunk: it lands in the
lower PR's merge commit, and the retarget puts each upper PR on that trunk. So no
merge-up is needed by default, and none costs an upper PR a push.

Merge a lower branch into an upper one only when that upper PR's own fixes need the
lower fix (they build on it, or its tests fail without it), and only on a PR the user
named or included: an unnamed PR's branch is not yours to push to. Do it inside that
PR's batch, with a plain merge commit and a plain push (never a rebase or a force
push), so it adds no push to its budget. A conflict that changes intent is a stop case.

The merged-in commits were reviewed on their own PR. On the upper PR, review its own
fixes plus the merge commit's conflict resolution: `git show --remerge-diff <merge
commit>` shows only what the resolution changed (`git diff <merge commit>^1 <merge
commit>` would show the whole lower PR).

## Report

Per PR: its merge commit SHA (or "queued"), each PR it retargeted, and for a queued
merge each PR above with the retarget it still needs.
