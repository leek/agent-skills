---
name: commit
description: Commit the work done in this session, skipping files a parallel session also touched.
disable-model-invocation: true
---

# Commit

Commit **only what you changed in this session**. Other sessions may be working in the same
repo at the same time — that is expected, and none of their work is yours to commit.

## Process

1. **List your files.** From this conversation, write down every file *you* created, edited, or
   deleted. If you touched nothing, say so and stop.
2. **Check the tree.** Run `git status --porcelain`. Anything not on your list belongs to someone
   else — ignore it completely.
3. **Drop the overlaps.** For each of your files, `git diff -- <path>` (`git diff --cached` too if
   it is already staged). If it contains changes you did not make, leave that file out — the other
   session will commit it. Note which files you skipped.
4. **Stage explicitly.** `git add -- <path> <path> …` with your remaining files, by exact path.
   Never `git add -A` or `git add .`. Re-run `git status --porcelain` and unstage anything foreign.
5. **Commit.** Conventional Commits subject: `type(scope): summary` — imperative mood, lowercase,
   no trailing period, under 72 chars. Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`,
   `perf`, `build`, `ci`. Scope optional. Add a short body only when *why* is not obvious from the
   diff. No attribution or co-author trailers.
6. **Report.** One line: the commit subject, the short SHA, and any files you deliberately left out
   and why. Do not push unless asked.

## Guardrails

- **Commit to the current branch, whatever it is.** Never switch, create, or suggest a branch —
  not even when the current branch is `main`/`master`. No `git checkout`, `git switch`, `git branch`.
- One session's work, one commit. Do not amend, rebase, or touch existing history.
- If the changes are genuinely two unrelated things, make two commits — still your files only.
- Never `git stash`, `git checkout --`, or `git reset` — a parallel session's uncommitted work is
  unrecoverable if you discard it.
