# Git and GitHub mechanics for fixing issues

`<default>` is the default branch, `<run>` is `date +%Y%m%d-%H%M` taken once per run,
and `N` is an issue number.

## List the working set

```bash
gh repo view --json defaultBranchRef -q .defaultBranchRef.name    # <default>
gh issue list --label <label> --state open --limit 500 --json number,title,createdAt
```

If the list holds exactly as many issues as the limit, raise the limit and list again.

## Branch or worktree

Every run works in a worktree. Record the main checkout, then leave it there, clean tree included:

```bash
git branch --show-current    # <start>; empty when detached, then use: git rev-parse HEAD
git worktree add -b fix/issues-<run> .claude/worktrees/issues-<run> origin/<default>
```

That path is the only place the fix is checked out, never a sibling directory. In a Laravel repo, make it runnable with `laravel-herd-worktrees`' **Bootstrap a bare worktree** section before running anything in it. Git commands for the fix run in the worktree (`git -C .claude/worktrees/issues-<run>`, or from inside it).

## Scratch databases

Run tests against the repo's configured test database when you can. When the run needs
its own (a worktree `.env`, a throwaway test database), name it `<app db>_issues_<run>`,
never a name the main checkout's `.env`, `.env.testing`, or `phpunit.xml` uses, and
register it the moment you create it:

```bash
printf '%s\t%s\t%s\t%s\n' "$(date +%s)" <pgsql|mysql> <database> "<worktree path, or ->" \
  >> "$(git rev-parse --path-format=absolute --git-common-dir)/scratch-databases"
```

## Land

Run these git commands in the worktree. Push unless the repo's rules require pull requests. A push refused as a protected
branch (`GH006`, or "changes must be made through a pull request") means open one
instead; a refusal is not a reason to retry with `--force`.

- Push: `git push origin HEAD:<default>` (no `--force`). If it is refused because
  `origin/<default>` moved, rebase onto it, re-run the tests, and push again.
- Pull request: `git push -u origin fix/issues-<run>`, then `gh pr create` with a body
  in the `pr` skill's template (screenshots per its **Screenshots** section), plus one `fixes #NNN` line per issue. The issues close when it merges.

## The checkout stays

The main checkout is still `<start>` at the end, because the run worked in the worktree. If a command moved it, switch it back before the report:

```bash
git switch <start>              # a branch name
git switch --detach <start>     # a sha, when the run started detached
```

The `fix/issues-<run>` branch stays in the worktree; it backs the pull request or the local commits.

## Disposition and close

```bash
gh issue comment N --body-file <file>
gh issue close N          # only when nothing in it was legit
gh issue view N --json state
```

## Clean up

At step 6, for each item it removes: `git worktree remove .claude/worktrees/issues-<run>` (no `--force`;
if git refuses, the tree holds unsaved work, so report it instead). Then drop each
database and its parallel-testing copies (`<database>_test_<N>`) with the repo's client
(`DROP DATABASE IF EXISTS`), and delete its line from the `scratch-databases` file.
