# Repository cleanup mechanics

Material only some runs need. Every rule about what may be removed is in [`SKILL.md`](../SKILL.md); nothing here widens it.

## Database candidates

Worktrees and one-off test runs leave local databases behind: a per-worktree `DB_DATABASE`, throwaway test databases (`<app db>_pr42`, `<app db>_sweep_<topic>`), and Laravel parallel testing's `<db>_test_N` copies of each. The `databases` list of `prune-merged-worktrees.sh` holds, with sizes, each candidate database by exact name, a parallel-testing copy as an item of its own. Its `source` says why: `worktree` (registered for, or named by, a candidate worktree), `registry` (a registered database whose worktree is gone), `orphan` (no registry line, but a name the skills give a scratch database: `<app db>_pr<N>`, `_pr<N>_fix<k>`, `_issues_<run>`, `_sweep_<topic>`, `_spec_<slug>_<NN>`, or a `_test_<N>` copy of one), or `prefix-only` (any other `<app db>_*` name with no registry line). Nothing proves a run made a `prefix-only` database: it may be a hand-made copy, a database Herd made for a branch, or another project's. Treat it as uncertain, give it its own option, and pass `--allow-prefix-only` with its `--drop` only when the user selected that exact name; without the flag the script refuses the run. It never lists a database in use, a parallel-testing copy of one, or one a registry line still names for a run or a remaining worktree.

## Dropping pr-assets folders

```bash
bash <this-skill-dir>/scripts/prune-pr-assets.sh --tip <plan tip> --drop <folder>...    # selected folders only
```

A kept folder's `…/blob/pr-assets/…` links keep working; links pinned to a commit (`…/blob/<sha>/…`, from older uploads) point at unreachable commits that GitHub may stop serving once it garbage-collects them. A tip that moved since the plan refuses the run; list again.
