# Review shape

What only a **review**-shape run of [`SKILL.md`](../SKILL.md) needs: the task string
written in step 1, the guard that step 3 puts around the fan-out, and step 5's report
through `ReportFindings`.

## Task string

In **review** shape, the task string is this brief. Put step 1's `diff_cmd` where
DIFF-CMD stands, in plain words, with **no backticks**, so nothing is left for a shell to
expand (with `--wip`, add: plus the untracked files, and list step 1's `untracked`):

> Review the change from DIFF-CMD in this repository. Read the diff and any
> files you need. Report concrete findings only, for each, a one-line claim, the
> file:line, and a one-line reason. Review only; do not modify any file. Be concise.

## Keep review read-only

**Keep review read-only.** For a committed scope, dispatch each panelist with
`isolation: "worktree"` where the harness offers it, so a stray write never reaches the
user's tree; its brief first runs `git checkout --detach <step 1's head_sha>`, since the
worktree may start from another base. A worktree left with uncommitted changes means
its CLI wrote: name both. For WIP scope, or without isolation, save `git status --porcelain` and `git diff`
as the baseline before fanning out, and compare after every subagent returns. A path
the CLIs changed that was clean in the baseline: revert it (`git checkout -- <path>`,
delete new files) and name that CLI. A path that was already dirty holds the user's
unsaved work: report it and leave it as it is. This isolation or tree check (not a
per-CLI flag) is what enforces review-only.

## Report through `ReportFindings`

In review shape, where the host has `ReportFindings`, report the clusters through it
instead, in one call, most-agreed first: `summary` the claim, `file`/`line` the location,
`failure_scenario` the reason plus the CLIs in brackets, `category` the grade, `verdict`
`CONFIRMED` for Unanimous or Majority and `PLAUSIBLE` below that. Print as markdown only
what it cannot carry: `general` points and Conflicts. Otherwise print every cluster.
