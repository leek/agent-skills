---
name: scratch-cleanup
description: "Sweep a dusty .scratch/: file research into docs/, remove finished efforts, and report the work still open."
disable-model-invocation: true
argument-hint: "Days of inactivity before open work counts as stale (default 30)"
---

# Scratch Cleanup

`.scratch/` is an inbox, not an archive. Everything in it ends one of three ways: **filed** (research that belongs in `docs/`), **removed** (an effort whose work is all done), or **kept** (work still open, listed in the report). Nothing changes on disk until the user approves the plan.

The stale threshold is `$ARGUMENTS` days; 30 when empty.

## 1. Inventory and judge

From inside the repository, run [`../scratch-status/scripts/scratch-state.sh`](../scratch-status/scripts/scratch-state.sh) `--days <threshold>` once.

The script walks `.scratch/`, checks git tracking (`tracked` and `untracked_files`) and last-change dates (`last_change`), resolves status and blockers in both frontmatter and legacy `Status:` dialects, verifies every cited ticket commit against `default_branch` (`git merge-base --is-ancestor`, merged PRs via `gh api`, `git cherry`, and commit subject match), and sorts `.scratch/` into three buckets:

- **`efforts`**: each `.scratch/<slug>/` directory, classified as:
  - **done**: every artifact (`map`, `decisions`, `spec`, `tickets`/`issues`, `requests`) is closed or wontfix, every cited commit is on `default_branch`, and `mismatch` is `null`.
  - **mismatched**: has an unreadable status (`unreadable_efforts` or `mismatch`) or a contradiction (e.g., `spec` still `ready-for-agent` while every ticket is closed, or a closed ticket whose cited commit is missing). Goes in the plan as a question, never a removal.
  - **open**: has any open file, with `stale: true` when its newest file is older than `--days`. Any `claimed_by` in a stale effort is a stale claim to release in step 3 (the session is gone); leave its status alone.
- **`research`**: findings files under `.scratch/research/` or loose `.md` files ending in **What this unblocks**.
- **`unclassified`**: everything else outside an effort (wizards, loose notes, questionnaires, and `.DS_Store` entries marked `junk: true`, which go in the plan as deletions with no question).

Done when `scratch-state.sh` has returned the bucketed inventory and effort judgements.

## 2. Plan

Build the plan for every bucket:

- **Research**: pick a destination under `docs/`. Match an existing topic folder (`docs/<topic>/`) when one fits the subject; otherwise use `docs/research/<same-filename>`. When two folders fit, or none fits and the subject clearly belongs to a topic that does not exist yet, list the choice as a question. Find every inbound link (`rg -n --fixed-strings '<old path>'` across the repo, `.scratch/` included) so the move can rewrite each one.
- **Done effort**: read its spec, map, and closed decision tickets for **lasting decisions**: choices that are hard to reverse, still true in the code today, and whose reasons live nowhere else. List each as a one-line ADR candidate. Then list the effort for removal (separating tracked paths from `untracked_files`).
- **Mismatched effort**: state `mismatch` in one line and what would settle it.
- **Unclassified**: one line per non-junk file saying what it looks like and a proposed fate (file, remove, or keep).

Show the plan in one message, with these sections in order: **File** (research moves and link rewrites), **ADR candidates** (numbered, so the user can pick by number), **Remove** (committed paths), **Remove: cannot recover** (untracked paths, with a note that git holds no copy), **Questions** (mismatched efforts, unclear destinations, unclassified files), and **Keep** (the report table from step 4). Ask for approval with a structured question ([harness-tools](../harness-tools/SKILL.md)), otherwise in chat. The untracked removals need their own explicit yes, separate from the rest of the plan.

Done when the user has approved, trimmed, or rejected each section, and has answered every question.

## 3. Apply

Apply only what the user approved, in this order:

1. **ADRs first**, while the source files still exist: write each picked candidate as an ADR through the `domain-modeling` skill's format and location (`docs/adr/` in a single-context repo).
2. **File research**: `git mv` for tracked files, `mv` for untracked ones, creating `docs/` folders as needed. Rewrite every inbound link found in step 2 to the new path.
3. **Remove**: `git rm -r -- <path>` for committed efforts and files; `rm` for approved untracked ones and `.DS_Store`.
4. **Release stale claims** found in step 1.
5. **Stage** every changed path by explicit path (`git add -- <path> …`); the commit waits for the user's yes in step 4.

Done when `rg -n --fixed-strings` finds no reference to any moved or removed path, and `git status --short` shows only the approved changes.

## 4. Report

End with the table of everything that stayed in `.scratch/`, one row per effort or kept file:

| Effort | Open work | Blocked by | Last change | Stale | Next |
|---|---|---|---|---|---|
| `.scratch/<slug>/` | open ticket or decision files, by number | open blockers, or the question the user left open | date | yes/no | the skill that moves it forward (`/implement <ticket>`, `/wayfinder <map>`, `/to-tickets <spec>`) |

Under the table, give one line each for: files filed (old → new path), ADRs written, paths removed, claims released. Then ask whether to commit the staged changes now (a structured question ([harness-tools](../harness-tools/SKILL.md)), otherwise in chat), and on a yes make the commit yourself, following the commit skill when it is installed. Never hand the user a `/commit` to run.
