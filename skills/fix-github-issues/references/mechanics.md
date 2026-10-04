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

- Clean tree: `git switch -c fix/issues-<run> origin/<default>`.
- Dirty tree: `git worktree add -b fix/issues-<run> .claude/worktrees/issues-<run> origin/<default>`,
  always at that path, never a sibling directory. Work there, after you make it runnable with `laravel-herd-worktrees`' **Bootstrap a bare worktree** section before running anything in it.

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

- Push: `git push origin HEAD:<default>` (no `--force`). If it is refused because
  `origin/<default>` moved, rebase onto it, re-run the tests, and push again.
- Pull request: `git push -u origin fix/issues-<run>`, then `gh pr create` with one
  `fixes #NNN` line per issue in the body. The issues close when it merges.

## Disposition and close

```bash
gh issue comment N --body-file <file>
gh issue close N          # only when nothing in it was legit
gh issue view N --json state
```

## Clean up

On the user's yes: `git worktree remove .claude/worktrees/issues-<run>` (no `--force`;
if git refuses, the tree holds unsaved work, so report it instead). Then drop each
database and its parallel-testing copies (`<database>_test_<N>`) with the repo's client
(`DROP DATABASE IF EXISTS`), and delete its line from the `scratch-databases` file.
