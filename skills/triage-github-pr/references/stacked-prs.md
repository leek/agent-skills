# Stacked PRs

A PR is **stacked** when its base is another open PR's head branch. The PRs chained
that way, down to the one whose base is the **trunk** (the default branch, or a deploy
branch the project context names), are one **stack**. Each branch carries the commits
of every PR below it, so a stack lands **bottom-up, one PR at a time, with merge
commits**, and each merge is followed by a **retarget** of the PR above it.

A stack lands on its **landing branch**: the trunk, or, when the stack has an
**integration PR**, that PR's head branch. The integration PR is a stack's bottom PR
whose body has a line starting `Integration:` (as `implement`'s stacked delivery writes
it), or one the user calls the stack's integration branch. It holds no ticket of its
own: every PR above it lands into its branch, the stack's fixes go there, and it
merges into the trunk last, so the trunk receives the stack once, verified.

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
is neither the trunk nor an open PR's head normally blocks every PR above it. Before
stopping, query `gh pr list --head <baseRefName> --state merged` and inspect any
same-repository candidate's `headRefOid` and base. If its base is the landing branch and its
recorded head is an ancestor of the named PR's reviewed head, follow
[Recover a rewritten parent](#recover-a-rewritten-parent); a closed-unmerged or
unverifiable parent remains a blocker. Never merge into that old base. Walk up the same way for
PRs based on a named PR's head (`gh pr list --base <head> --state open`).

- **An unnamed PR below a named one** gates it: the named PR cannot land before it. Ask
  once, as a merge question, whether to take the whole chain from the bottom; otherwise
  stop that PR with the unmerged base as its blocker. A PR the user includes is worked
  like a named one, steps 1–7 with its own fix budget, never merged unreviewed.
- **An unnamed PR above a named one** is not yours to merge or push to, but it is
  retargeted after the merge below it (step 3), so it stays open on the right base.
- **An integration PR** counts as named when the user named every PR above it: it
  carries no code of its own until they land. Naming the integration PR alone names
  its stack as a merge question: ask once whether to land every PR above it. On no,
  it is not merged, since the trunk would receive an empty stack.

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

Apply step 6's authorization rule to the stack as one decision. If the user named
every PR or requested "all open PRs", report the order (`#101 → #102 → #103`, then
`⇒ #100` for an integration PR) and proceed without another stack-approval question.
Otherwise ask once for the missing scope. Deploy-branch approval, a conflicting
requested merge method, native stacks, and a force-pushed restack still have their own
gates above or below. Then, for each PR above the integration PR (every PR when there
is none), from the bottom up:

1. **It merges only while its base is the landing branch.** A PR whose base is still
   another PR's head is never merged: merging it would land its changes on that branch,
   not the landing branch.
2. **Merge** with the pinned head and a merge commit, per
   [Merge](gh-mechanics.md#merge): `gh pr merge N --merge --match-head-commit <sha>`.
   When required checks are pending, `--auto` queues it; the PRs above wait for that
   merge to land, so stop the stack there and report it queued, naming the retarget
   each PR above still needs once it lands (step 3's `gh pr edit`), unless
   `deleteBranchOnMerge` is true and GitHub retargets them itself.
3. **Retarget** each PR based on its head to the merged PR's base. GitHub does this by
   itself only when the merged head branch is deleted; this skill deletes nothing, so
   retarget explicitly and skip a PR whose base already reads the landing branch. First record
   the commits the PR carries on top of the merged head, so step 4 has something to
   compare against:

   ```bash
   git fetch origin
   git rev-list <merged PR's head sha>..<M head sha> > <scratch file for M>   # before the retarget
   gh pr view M --json baseRefName --jq .baseRefName
   gh pr edit M --base <landing branch>
   ```

4. **Re-check the retargeted PR** before its own merge, as step 6 does. Its commits on
   top of the landing branch must be the ones recorded in step 3: `git fetch origin
   <landing branch>`, then `git rev-list origin/<landing branch>..<M head sha>` must
   match that recorded list. An extra
   commit means the history below M is not what landed. Follow
   [Recover a rewritten parent](#recover-a-rewritten-parent) when the lower PR is
   verifiably merged; otherwise stop and report the extra change. After recovery,
   replace the recorded commit list with the reviewed restacked delta and restart
   this check using the new head. An ordinary retarget does not move
   the head, so the review of that head still covers it and `--match-head-commit` pins
   the same sha, unless the repo requires up-to-date branches: then M reads `BEHIND`,
   because the landing branch now has the merge commit M lacks. Update it as
   [Merge gates](gh-mechanics.md#merge-gates) says, inside M's push budget and combined
   with its batch, then review and pin the new head; with no push left it is a blocker.
   `mergeable` reads `UNKNOWN` for a moment after a retarget; re-poll as Merge gates
   says.

Completion criterion: every PR in the chain is merged in order (or the run stopped on a
named one), and every open PR that was based on a merged head now targets the landing
branch or is named in the report with the retarget it still needs. An integration PR
then merges as [Fixes inside a stack](#fixes-inside-a-stack) says.

## Recover a rewritten parent

For a named PR M left above a squash- or rebase-merged parent, first verify the lower
PR is `MERGED` into the landing branch, is from this repository, and its recorded head is an
ancestor of M's reviewed head. Record that lower head and M's current head as the
replay boundary and lease expectation. Inspect the commits above the boundary to
confirm they are M's own changes. Without that evidence, stop and report the blocker.

Ask once for permission to restack and force-push M, unless the user already approved
that exact action. Include any open dependents' required restacks in that decision,
retaining their pre-rewrite boundaries; never force-push an unnamed dependent. Check
M has a push left in its existing budget before rewriting. In M's isolated worktree,
use a local branch whose tip equals the recorded reviewed head, then:

```bash
git fetch origin <landing branch>
git rebase --onto origin/<landing branch> <lower-head-sha> <M-local-branch>
git range-diff <lower-head-sha>..<reviewed-M-head-sha> origin/<landing branch>..HEAD
```

The rebase drops merge commits: a conflict resolved earlier inside a merge of the parent
into M comes back here as a new conflict, so resolve it the way that merge did (`git show
<merge-sha>` shows the old resolution), and expect `range-diff` to show the merges gone.
Resolve conflicts only when intent is clear. Validate and review the resulting delta,
including conflict resolutions; the old SHA's review does not cover this new head.
Then push explicitly, with a lease pinned to the reviewed remote head:

```bash
git push --force-with-lease=refs/heads/<M-headRefName>:<reviewed-M-head-sha> origin HEAD:refs/heads/<M-headRefName>
```

A failed lease stops recovery; fetch and reassess the concurrent changes, never
override it. Re-read M's remote `headRefOid`, confirm it equals the validated local
head, retarget M to the landing branch if needed, and rerun step 6's gates with that new SHA.
Record `git rev-list origin/<landing branch>..<new-M-head-sha>` as the replacement own-commit
list. Continue only when that exact head is reviewed and validated; pin it in the merge.

## Fixes inside a stack

A fix landed on a lower PR conflicts with every PR above it that touches the same lines,
and each of those then pays a merge, a conflict resolution, a re-test and a re-review.
So a stack lands first and fixes once, wherever its shape allows.

**Fix on the integration PR** when the stack has one:

1. Finish step 4 for every PR above it, then check their hard
   [gates](gh-mechanics.md#merge-gates) and settle every QUESTION and merge question.
   A PR whose gate only a push to it can clear (a required check or `BEHIND` under the
   landing branch's protection) takes that fix in its own batch before it lands, as
   per-PR fixes below do. A standing human `CHANGES_REQUESTED` stops the stack at that
   PR, as step 6 says. Either way the trunk is untouched.
2. Land every PR above it bottom-up, unchanged, per [Merge in order](#merge-in-order).
   Each head carries the one below it, so every landing is conflict-free. Reply on each
   landed PR's current-batch findings `<severity>; verified; fixing on #<integration>`
   and leave them open. A landing queued with `--auto` stops the stack there, findings
   still open.
3. Give the integration PR its own steps 1–6 now, never in the first parallel round.
   Work it in the detached worktree `.claude/worktrees/pr-<integration>` at
   `origin/<slug>`; the local `<slug>`, when one exists, is `implement`'s build, never
   its checkout. Its starting SHA is its head after the landings. The landed PRs'
   reviews cover that head, since each reviewed its delta over the PRs below it and
   every landing is conflict-free, so its step 1 covers only what comes after: the fix
   batch (step 5's pre-push review) and any trunk merge (`git show --remerge-diff`).
   Re-anchor every landed PR's LEGIT finding to that head first: one a landed PR above
   it already fixed (the stack's closing review-fixes PR) is STALE, with that PR as its
   evidence. Its batch 1 holds the rest. The landings are not fix pushes and use none
   of its budget; count them as landings when reconciling pushes.
4. While it is a draft, push batch 1 first, then `gh pr ready <integration>`: its draft
   state is the stack's layout, not unclear intent, and the bots review the whole stack
   once, already fixed. Step 6's checkpoint after batch 1 runs here, and the merge into
   the trunk uses `--merge`, under every gate step 6 names (deploy-branch approval
   included).
5. Once batch 1 is committed, reply on each landed PR's findings `fixed in <sha> on
   #<integration>; validated` and resolve them; after the push, record the same in each
   disposition.

The trunk never sees a stack PR's known defect. If the run stops before the integration
PR merges, everything waits on its branch, its findings still open, and the report says
so.

**Fix at the top** when the stack has no integration PR, the user named every PR in it
(or "all open PRs"), and the trunk is not a deploy branch. The **top** is the
highest PR you may push to; unnamed PRs above it are only retargeted.

1. Finish step 4 for every PR in the stack, then check every PR's hard
   [gates](gh-mechanics.md#merge-gates) and settle every QUESTION and merge question
   before writing any fix.
2. In the top PR's worktree, make every PR's current-batch fixes, each commit naming the
   PR and finding it fixes. The top branch carries every lower PR's code, so each fix
   lands where its finding points.
3. Test what the fixes touched, run step 5's pre-push review on the whole fix range, and
   push once. That push is the top PR's batch 1 and the whole stack's; lower PRs push
   nothing.
4. Reply on each lower PR's threads with `fixed in <sha> on #<top>`, resolve them, and
   record the same in its disposition.
5. Land bottom-up per [Merge in order](#merge-in-order). Each lower PR merges at its
   reviewed, unchanged head, so every retarget is conflict-free. Step 6's checkpoint after
   batch 1 runs on the top PR; new findings on any PR in the stack join the top PR's
   batch 2 or are carried, per the shipping budget.

From the first merge until the top merges, the trunk carries the lower PRs' known
defects, so a deploy-branch trunk takes the per-PR path below. If the run stops before
the top merges, the fixes stay on the top PR: the report names each merged PR whose fix
is waiting there.

**Per-PR fixes** otherwise. A fix pushed to a lower PR reaches the PRs above it through
the trunk: it lands in the lower PR's merge commit, and the retarget puts each upper PR
on that trunk. So no merge-up is needed by default, and none costs an upper PR a push.
Test an upper PR for what its own fixes and its conflict resolution touched; the lower
PRs' tests already passed on their own heads. Run the tests every PR's fixes touched
once, on the top PR, before it merges.

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
merge each PR above with the retarget it still needs. For an integration PR, its merge
into the trunk last, or what still waits on its branch.
