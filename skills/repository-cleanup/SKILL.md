---
name: repository-cleanup
description: "Audit and clean Git repository state: branches, PRs, stashes, worktrees, and the local databases old worktrees left behind."
disable-model-invocation: true
---

# Repository Cleanup

## Goal

Inspect local and remote branches, pull requests, commits, stashes, worktrees, and the local databases left behind by old worktrees. Recover valuable work, then remove the proven stale state the user selects, until the repository is current and organized. Nothing is removed that the user did not select by name.

## Loop Prompt

```text
Inspect local and remote branches, pull requests, commits, stashes, and worktrees. Recover valuable work, list everything stale, and remove only the items the user selects, until the repository is current and organized.
```

Stop when valuable work is recovered and remaining repository state is intentional.

## When To Use

Use this when abandoned branches, old worktrees, unclear pull requests, unmerged commits, or forgotten stashes make it difficult to know which repository state still matters.

This loop cleans Git repository state. It is not a source-code housekeeping pass; use `housekeeper` for dead code, stale files, duplicated logic, broken links, unused dependencies, and project-structure cleanup.

## Workflow

1. Inspect the current working tree before changing anything: current branch, uncommitted changes, stashes, remotes, upstreams, and registered worktrees.
2. Fetch current remote state without pruning. List the stale remote-tracking refs instead (`git remote prune --dry-run <remote>`); they are removal candidates like any other.
3. Inventory local branches, remote branches, open and recently closed pull requests, unmerged commits, stashes, worktrees, and orphaned databases (see Databases).
4. Classify each item as current, valuable but unfinished, superseded, merged, abandoned, or uncertain.
5. Record evidence for each classification: upstream status, merge base, PR state, commit reachability, stash contents, worktree dirtiness, owner, and recent activity.
6. Recover valuable work before cleanup. Move useful commits or stashed changes to the appropriate current branch, preserve patches, or keep a clearly named branch.
7. Ask before removing anything. Put every removal candidate of the batch (merged branches, stale remote-tracking refs, stashes, worktrees, databases, remote branches, PRs to close) in one list: each item's exact name, the step 5 evidence, its size where known, and `cannot recover` when nothing else holds a copy. Ask the user to pick the items to remove (`AskUserQuestion` with `multiSelect: true` where available, nothing pre-ticked; otherwise a numbered list they answer with numbers). An answer that names no item ("ok", "go ahead") picks nothing.
8. Remove only the selected items, by their exact names. Everything unselected stays, and the report names it.
9. Rerun the inventory after cleanup until every remaining branch, pull request, commit, stash, worktree, and database is intentional.

## Inventory Commands

Use the repository's existing tools and hosting provider first. Common Git and GitHub CLI checks:

```bash
git status --short --branch
git stash list
git stash show --stat stash@{0}
git remote -v
git fetch --all
git remote prune --dry-run origin
git worktree list --porcelain
git branch --format='%(refname:short) %(upstream:short) %(committerdate:relative)'
git branch --merged
git branch --no-merged
git log --all --decorate --oneline --graph --date-order -n 80
gh pr list --state open --json number,title,headRefName,baseRefName,author,updatedAt,url
gh pr list --state closed --limit 30 --json number,title,headRefName,baseRefName,author,updatedAt,closedAt,mergedAt,url
```

Worktrees whose PR merged, and the databases left behind, come from one script. With no arguments it changes nothing and prints the candidates as JSON. It removes only the names you pass, after the user selected them, and it refuses the whole run, changing nothing, if one name is not a candidate:

```bash
bash scripts/prune-merged-worktrees.sh    # list: merged clean worktrees, their databases, orphans
bash scripts/prune-merged-worktrees.sh --remove <worktree path> --drop pgsql:<database>   # selected items only
```

A worktree's database can be dropped only in the same run that removes that worktree. Never pass a name the user did not select, and never build the arguments from the whole list.

If `gh` is unavailable or the repository is not on GitHub, use the equivalent provider CLI, web UI, or local Git evidence and report the PR visibility gap.

## Databases

Worktrees and one-off test runs leave local databases behind: a per-worktree `DB_DATABASE`, throwaway test databases (`<app>_pr42`, `<app>_triage_<date>`), and Laravel parallel testing's `<db>_test_N` copies of each. The script's `databases` list holds, with sizes, each candidate database by exact name, a parallel-testing copy as an item of its own. Its `source` says why: `worktree` (registered for, or named by, a candidate worktree), `registry` (a registered database whose worktree is gone), or `orphan` (named `<app db>_*` and named by no `.env`, `.env.testing`, or `phpunit.xml` of the main checkout or a remaining worktree). It never lists a database in use, or a parallel-testing copy of one.

Classify each listed database by its name: a PR number, branch, worktree, or date that maps to merged or removed work is **abandoned**; a name that reads as a deliberate copy (`_backup`, `_snapshot`, `_pre_migration`) or maps to nothing is **uncertain**. Show the list grouped that way, with sizes, in the step 7 selection, and drop only the selected names, through the script's `--drop`. Each drop is irreversible: offer a `pg_dump`/`mysqldump` first for anything uncertain.

## Classification Guide

- **Current:** actively used branch, active pull request, current worktree, release branch, or protected branch.
- **Valuable but unfinished:** contains unmerged commits, unpushed commits, or stashed changes that appear relevant, even if old.
- **Superseded:** replaced by a newer branch, merged through a different branch, or made irrelevant by a later implementation.
- **Merged:** fully integrated into the target branch or corresponding pull request is merged.
- **Abandoned:** old, ownerless, no useful unique commits or stash contents, no active pull request, and no dirty worktree.
- **Uncertain:** insufficient evidence, unclear ownership, dirty worktree, ambiguous unmerged commits, unclear stash contents, or possible external dependency.

Uncertain items are not cleanup candidates until more evidence or user approval resolves them.

## Cleanup Rules

- Every removal is one the user selected by name in step 7. Proof that an item is stale makes it a candidate, never a removal; no repository policy or earlier approval replaces the selection.
- Use `git branch -d` for selected local branches proven merged. Use `git branch -D` only after explicit approval and only after preserving any useful commits.
- Do not drop stashes until their contents have been inspected and the user has approved the exact stash to drop.
- Before removing a worktree, verify it has no uncommitted changes and its branch/commits have been classified.
- Drop a database only when the user selected that exact name. Never drop one the main checkout or a remaining worktree uses.
- Before deleting a branch with unique commits, preserve the work by merging, cherry-picking, tagging, renaming, or exporting patches.
- Before dropping a valuable stash, recover it onto the appropriate branch or preserve it as a patch with enough context to reapply.
- Prefer small batches. Re-inventory after each batch so the next decision uses current evidence.

## Report

End with:

- Repository state inventoried.
- Branches, pull requests, commits, stashes, worktrees, and databases classified.
- Valuable work recovered or preserved.
- Cleanup actions taken, with evidence for each.
- Verification commands run after cleanup.
- Remaining intentional repository state, including any kept stashes.
- Deferred or uncertain items and what approval or evidence is needed.

## Guardrails

- Do not discard uncommitted changes, stashes, unpushed commits, or dirty worktrees.
- Do not use `git reset --hard`, `git checkout --`, `git clean`, or force-delete branches unless the user explicitly asked for that exact destructive action.
- Do not close someone else's pull request or delete a remote branch without confirmation.
- Do not treat old age alone as proof that work is stale.
- Preserve evidence for every destructive cleanup action.
