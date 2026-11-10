# Repository cleanup mechanics

Material only some runs need. Every rule about what may be removed is in [`SKILL.md`](../SKILL.md); nothing here widens it.

## Database candidates

Worktrees and one-off test runs leave local databases behind: a per-worktree `DB_DATABASE`, throwaway test databases (`<app>_pr42`, `<app>_triage_<date>`), and Laravel parallel testing's `<db>_test_N` copies of each. The `databases` list of `prune-merged-worktrees.sh` holds, with sizes, each candidate database by exact name, a parallel-testing copy as an item of its own. Its `source` says why: `worktree` (registered for, or named by, a candidate worktree), `registry` (a registered database whose worktree is gone), or `orphan` (named `<app db>_*` and named by no `.env`, `.env.testing`, or `phpunit.xml` of the main checkout or a remaining worktree). It never lists a database in use, or a parallel-testing copy of one.

## Dropping pr-assets folders

```bash
bash <this-skill-dir>/scripts/prune-pr-assets.sh --tip <plan tip> --drop <folder>...    # selected folders only
```

A kept folder's `…/blob/pr-assets/…` links keep working; links pinned to a commit (`…/blob/<sha>/…`, from older uploads) point at unreachable commits that GitHub may stop serving once it garbage-collects them. A tip that moved since the plan refuses the run; list again.
