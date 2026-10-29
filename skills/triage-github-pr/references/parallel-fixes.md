# Parallel fix batch

Step 5's fixes run one after another by default. A batch with at least 6 findings that
split into at least 2 **fix groups** is written in parallel instead: one **fixer**
sub-agent per group, each in its own worktree, merged back into the PR worktree before
the batch's one test run, one pre-push review and one push. A stack's integration PR
batch is the usual case; a lone PR with a long findings list qualifies the same way.
`implement-spec` runs its whole-branch fix batch through steps 1–3 too, with its own
worktree and database names.

You stay the orchestrator. Fixers write code and tests only: verification, every
GitHub write (replies, resolves, the disposition, the push), the pre-push review and
every question to the user stay with you. A harness with no sub-agents runs the batch
inline, as step 5 does.

## 1. Group the findings

For each finding, list the files its fix will touch: the file at its `file:line`, the
test file its regression test goes in, and any call site its verification evidence
names. Findings sharing any file are one group (union-find over the lists), so no two
fixers edit one file. While there are more than 4 groups, merge the two smallest.
Fewer than 2 groups means inline.

Completion criterion: every finding in the batch sits in exactly one group, each group
names its files, and no file appears in two groups.

## 2. Dispatch the fixers

Per group `k`, in the main checkout's `.claude/worktrees/`, never one inside the PR
worktree:

```bash
git worktree add --detach <main checkout>/.claude/worktrees/pr-<N>--fix-<k> <PR worktree HEAD>
```

Make it runnable the way step 5's worktree was. When its tests need a database of their
own, name it `<app db>_pr<N>_fix<k>` and register it per
[Scratch databases](gh-mechanics.md#scratch-databases). Then start one fixer per group
in one message, in the background (Claude Code: `Agent`, `run_in_background: true`,
`name: pr-<N>--fix-<k>`; Codex: `spawn_agent` with `fork_turns: "none"` per group, keeping each id, then
`wait_agent`; elsewhere, any sub-agent the harness offers). Its brief gives the worktree
path, its findings' step 4 lines with links, its file list, the repo's `AGENTS.md` /
`CLAUDE.md`, and these rules:

- Work only in that worktree. Call the Skill tool with `tdd` (otherwise follow
  `skills/tdd/SKILL.md`) and give each logic, auth or data fix a regression test that
  fails without it. Make the minimal change.
- Run focused tests in the foreground and wait for the result; an idle fixer may not
  wake when a background run ends. End with them green.
- Touch a file outside the list only when the fix cannot land without it, and name it in
  the report.
- Format the touched paths with the repo's formatter, and commit each finding on its
  own, by explicit path, its subject naming the finding.
- Never push, never write to GitHub, never touch `.scratch/`.
- Report in at most ten lines: each finding's commit SHA, the touched paths, the focused
  test command and result, and anything that blocks a finding.

Then end the turn and let the completion notifications wake you; never poll. An idle
notification with no report and no new commit is a stall: message that fixer at once
(`SendMessage` to its name, `followup_task` in Codex) to finish or say what blocks it.

Completion criterion: every group has a fixer running or a report back.

## 3. Merge back as each fixer reports

In the PR worktree, `git merge --no-ff <fixer tip>`: the worktrees share one object
store, so the SHA is enough, and the fixer's commits keep their SHAs. Its files are its
own, so a conflict means a fixer touched a file beyond its list: call the Skill tool
with `resolving-merge-conflicts`, and the pre-push review covers the resolution with
`git show --remerge-diff`. A finding the fixer reports blocked goes back to step 4 as a
QUESTION or is carried, per the shipping budget.

Completion criterion: every fixer's commits are in the PR worktree, or its findings are
dispositioned as blocked.

## 4. Validate once, then push

Run the union of the fixers' focused test commands once on the merged tree, then step
5's pre-push review over the whole fix range. A failure or review defect goes back to
the fixer that owns the file, with the output (`SendMessage` to its name, `followup_task`
in Codex), and its new commits are merged as in step 3. Fix inline only what no
fixer owns. Then reply on each finding with its commit's SHA, `validated; push pending`,
record the batch and push, as step 5 says.

The fix worktrees and their databases are step 5 worktrees: step 7 removes them with
the PR's own.

Completion criterion: the merged tree's tests are green, the pre-push review is clean,
and the batch is pushed.
