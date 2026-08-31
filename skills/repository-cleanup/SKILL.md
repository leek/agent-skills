---
name: repository-cleanup
description: "Audit and clean Git repository state: branches, PRs, stashes, and worktrees."
disable-model-invocation: true
---

# Repository Cleanup

## Goal

Inspect local and remote branches, pull requests, commits, stashes, and worktrees. Recover valuable work and clean proven stale state until the repository is current and organized.

## Loop Prompt

```text
Inspect local and remote branches, pull requests, commits, stashes, and worktrees. Recover valuable work and clean everything stale until the repository is current and organized.
```

Stop when valuable work is recovered and remaining repository state is intentional.

## When To Use

Use this when abandoned branches, old worktrees, unclear pull requests, unmerged commits, or forgotten stashes make it difficult to know which repository state still matters.

This loop cleans Git repository state. It is not a source-code housekeeping pass; use `housekeeper` for dead code, stale files, duplicated logic, broken links, unused dependencies, and project-structure cleanup.

## Workflow

1. Inspect the current working tree before changing anything: current branch, uncommitted changes, stashes, remotes, upstreams, and registered worktrees.
2. Fetch current remote state safely, pruning stale remote-tracking refs when appropriate.
3. Inventory local branches, remote branches, open and recently closed pull requests, unmerged commits, stashes, and worktrees.
4. Classify each item as current, valuable but unfinished, superseded, merged, abandoned, or uncertain.
5. Record evidence for each classification: upstream status, merge base, PR state, commit reachability, stash contents, worktree dirtiness, owner, and recent activity.
6. Recover valuable work before cleanup. Move useful commits or stashed changes to the appropriate current branch, preserve patches, or keep a clearly named branch.
7. Clean only proven stale state: delete merged local branches, prune stale remote-tracking refs, drop only explicitly approved stale stashes, remove clean obsolete worktrees, and close or delete remote state only with approval.
8. Rerun the inventory after cleanup until every remaining branch, pull request, commit, stash, and worktree is intentional.

## Inventory Commands

Use the repository's existing tools and hosting provider first. Common Git and GitHub CLI checks:

```bash
git status --short --branch
git stash list
git stash show --stat stash@{0}
git remote -v
git fetch --all --prune
git worktree list --porcelain
git branch --format='%(refname:short) %(upstream:short) %(committerdate:relative)'
git branch --merged
git branch --no-merged
git log --all --decorate --oneline --graph --date-order -n 80
gh pr list --state open --json number,title,headRefName,baseRefName,author,updatedAt,url
gh pr list --state closed --limit 30 --json number,title,headRefName,baseRefName,author,updatedAt,closedAt,mergedAt,url
```

If `gh` is unavailable or the repository is not on GitHub, use the equivalent provider CLI, web UI, or local Git evidence and report the PR visibility gap.

## Classification Guide

- **Current:** actively used branch, active pull request, current worktree, release branch, or protected branch.
- **Valuable but unfinished:** contains unmerged commits, unpushed commits, or stashed changes that appear relevant, even if old.
- **Superseded:** replaced by a newer branch, merged through a different branch, or made irrelevant by a later implementation.
- **Merged:** fully integrated into the target branch or corresponding pull request is merged.
- **Abandoned:** old, ownerless, no useful unique commits or stash contents, no active pull request, and no dirty worktree.
- **Uncertain:** insufficient evidence, unclear ownership, dirty worktree, ambiguous unmerged commits, unclear stash contents, or possible external dependency.

Uncertain items are not cleanup candidates until more evidence or user approval resolves them.

## Cleanup Rules

- Use `git branch -d` for local branches proven merged. Use `git branch -D` only after explicit approval and only after preserving any useful commits.
- Do not delete remote branches, close pull requests, remove worktrees, or discard patches unless the user approved the exact action or the stale state is already proven safe by repository policy.
- Do not drop stashes until their contents have been inspected and the user has approved the exact stash to drop.
- Before removing a worktree, verify it has no uncommitted changes and its branch/commits have been classified.
- Before deleting a branch with unique commits, preserve the work by merging, cherry-picking, tagging, renaming, or exporting patches.
- Before dropping a valuable stash, recover it onto the appropriate branch or preserve it as a patch with enough context to reapply.
- Prefer small batches. Re-inventory after each batch so the next decision uses current evidence.

## Report

End with:

- Repository state inventoried.
- Branches, pull requests, commits, stashes, and worktrees classified.
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
