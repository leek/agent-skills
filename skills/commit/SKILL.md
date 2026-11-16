---
name: commit
description: Commit the work done in this session, skipping files a parallel session also touched.
disable-model-invocation: true
allowed-tools: "Bash(git status *) Bash(git diff *) Bash(git add *) Bash(git commit *) Bash(git show *) Bash(git log *) Bash(git apply --cached *)"
model: sonnet
effort: medium
---

# Commit

Commit **only what you changed in this session**. Other sessions may be working in the same
repo at the same time; that is expected, and none of their work is yours to commit.

## Process

1. **List your files.** From this conversation, write down every file *you* created, edited, or
   deleted. If you touched nothing and `git status --porcelain -- .claude/agent-memory` is empty,
   say so and stop.
2. **Stage and commit** them per [Staging](#staging), with a subject per [Subject](#subject).
3. **Report.** One line: the commit subject, the short SHA, and any files you deliberately left out
   and why. Do not push unless asked.

Guardrails for this skill:

- **Commit to the current branch, whatever it is.** Never switch, create, or suggest a branch,
  not even when the current branch is `main`/`master`. No `git checkout`, `git switch`, `git branch`.
- One session's work, one commit. Do not amend, rebase, or touch existing history.
- If the changes are genuinely two unrelated things, make two commits, still your files only.

## Staging

Every skill that commits stages this way, so a parallel session's work never rides along.

1. **Check the tree.** Your list is every file this session or task created, edited, or deleted
   (under `/commit`, Process step 1 wrote it down; a calling skill knows its own paths). Run
   `git status --porcelain`. Anything not on your list belongs to someone else, ignore it
   completely. Changes under `.claude/agent-memory/` are always yours, whoever wrote them: they are
   the notes of agents with `memory: project`, not a parallel session's work in progress, so they
   ride along in your commit: `git add -- .claude/agent-memory`, then name `.claude/agent-memory`
   in step 3's path list. Leave them out of a commit the caller restricts to named files (release's
   version bump) and of a commit in an `implement-spec` ticket worktree, whose cleanup carries the
   notes to the main checkout.
2. **Drop the overlaps.** For each of your files, `git diff -- <path>` (`git diff --cached` too if
   it is already staged). If it contains changes you did not make, leave that file out, the other
   session will commit it. If a file mixes your hunks with foreign hunks, stage only yours: `git add -p -- <path>`
   needs an interactive terminal, so where the shell has none (Claude Code's Bash, most agent
   harnesses), write your hunks to a patch (`git diff -- <path> > "$TMPDIR/mine.patch"`, then
   delete the foreign hunks from it) and `git apply --cached "$TMPDIR/mine.patch"`. Never include a
   foreign hunk because it is small. Note which files you skipped.
3. **Commit by path, without touching the index.** Use
   `git commit --only -m "<subject>" -- <path> <path> …` (options before the `--`). `--only` commits exactly the named paths
   and ignores whatever another session has already staged, so a foreign `git add` can never ride
   along. Stage by explicit path only: never `git add -A`, `git add .`, or `commit -a`.
   **New files are one exception:** `--only` silently skips untracked paths, so `git add -- <new-path>`
   each file you created first, then include it in the same `--only` list. Check
   `git status --porcelain` afterwards; a `??` line for one of your files means it was skipped.
   **A file whose hunks you staged in step 2 is the other:** `--only`, and any
   `git commit -- <path>` (paths make `--only` the default), commits the whole working-tree copy,
   foreign hunks included. Commit from the index instead: `git add -- <path> …` your other files,
   check that `git diff --cached --name-only` lists only your paths, then `git commit -m "<subject>"`
   with no paths. When it lists a path you did not stage (another session's `git add`), leave the
   mixed file out and name it.
4. **Leave the rest of the tree alone.** Never `git stash`, `git checkout --`, or `git reset`: a
   parallel session's uncommitted work is unrecoverable if you discard it. Need a pre-change
   baseline of a file? Copy it aside and `git show HEAD:<path> > <path>`, run what you need, then
   restore the copy. A scoped stash plus immediate pop is still a stash.

## Subject

Conventional Commits: `type(scope): summary`: imperative mood, lowercase, no trailing period,
under 72 chars. Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `build`, `ci`.
Scope optional. Add a short body only when *why* is not obvious from the diff. No attribution or
co-author trailers.
