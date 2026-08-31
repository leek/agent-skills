---
name: panel
description: Convene a panel of agent CLIs (grok, claude, codex, agy) on a prompt or a code review, then report one consensus grouped by how much they agree.
disable-model-invocation: true
argument-hint: "A prompt, or a review scope like 'review since main'"
---

# Panel

Put one task in front of four agent CLIs (`grok`, `claude`, `codex`, `agy`) run
each in its own subagent, headless, then report a single consensus grouped by how
much the panel agrees.

Each CLI runs as its own latest/default model. **Never pass `--model` to any of
them.** The point of the panel is four independent models; pinning a model defeats it.

Two task shapes:

- **Prompt**: the user's text goes to all four, unchanged.
- **Review**: pin one diff scope and tell all four to review it, read-only, same scope each.

## Process

### 1. Read the task and pick the shape

- **Review** when the user asks to review a branch, PR, WIP, or "review since X".
  Pin the fixed point the way `code-review` does: the diff is
  `git diff <fixed-point>...HEAD` (three-dot, against the merge-base), default
  `main` when the user names none. For uncommitted work in progress, drop the `...HEAD`
  so the diff also covers staged and unsaved changes. Confirm the ref resolves
  (`git rev-parse <fixed-point>`) and the diff is non-empty **before** fanning out, 
  a bad ref should fail here, not inside four subagents.
- **Prompt** otherwise; the user's text is the task, passed word for word.

Write the one task string now. Every CLI receives the identical string, so the four
results compare cleanly.

### 2. Check who is on the panel

Run `command -v` for each of `grok`, `claude`, `codex`, `agy`. Drop any that is
absent and record it for the final report. If fewer than two remain, there is no
consensus to form: say which are missing and stop.

### 3. Fan out: one subagent per CLI, in parallel

Spawn one subagent per present CLI, all in a single message so they run at once.
Give each subagent the **same** task string and this brief:

- **Pass the task safely: never inline it.** A prompt with a backtick, `$`, or quote
  gets run by the shell if you paste it into the command. Put the task in a variable
  with a quoted heredoc, then pass `"$TASK"`:

  ```bash
  TASK=$(cat <<'PANEL_EOF'
  …the one task string…
  PANEL_EOF
  )
  ```

  The quoted `'PANEL_EOF'` delimiter and the quotes around `"$TASK"` stop every
  expansion. Then run your CLI **once**, headless, from the repo root, using its row
  below. Add no `--model`; keep the row's flags as written.
- **Run every CLI detached: never let one time out.** These agent CLIs take many
  minutes, and a slow model (codex at high reasoning is the usual culprit) will run past
  the Bash tool's 10-minute foreground ceiling and get killed mid-orientation, before it
  ever reports. Do **not** run the command in the foreground with a big timeout, 10 min
  is the hard max and it will be killed. Instead redirect the command's output to a
  scratch file and launch it with the Bash tool's `run_in_background: true`: append
  ` > "$SCRATCH/panel-<cli>.out" 2>&1` to the row's command (keep the `< /dev/null`).
  Your turn pauses and you are re-invoked automatically when the CLI exits; then read the
  scratch file and distill it. Background runs have no timeout; this is what guarantees
  nothing is cut off.
- Distill the output into a short, normalized result. For each point the CLI makes,
  capture three things: a one-line **claim**, a **location** (`file:line`, or
  `general`), and a one-line **reason**. Drop the CLI's logs, thinking, and prose.
- Return `{ cli, status, points[] }`. `status` is `responded`, or `errored` with a
  one-line cause. Return the object only, no narration.

Headless commands (`< /dev/null` stops the CLI blocking on stdin):

| CLI | Command |
|---|---|
| `claude` | `claude -p "$TASK" --dangerously-skip-permissions < /dev/null` |
| `codex` | `codex exec --dangerously-bypass-approvals-and-sandbox --cd "$PWD" "$TASK" < /dev/null` |
| `agy` | `agy --dangerously-skip-permissions -p "$TASK" < /dev/null` |
| `grok` | `grok -p "$TASK" --always-approve < /dev/null` |

In **review** shape, the task string is this brief. Name the pinned diff from step 1 in
plain words, with **no backticks**, so nothing is left for a shell to expand:

> Review the change from git diff FIXED-POINT in this repository. Read the diff and any
> files you need. Report concrete findings only, for each, a one-line claim, the
> file:line, and a one-line reason. Review only; do not modify any file. Be concise.

**Keep review read-only.** Run on a clean working tree. After every subagent returns,
run `git status --porcelain`; if a CLI changed a tracked file or added one, revert it
(`git checkout -- <path>`, delete new files) and name that CLI in the report. This tree
check (not a per-CLI flag) is what enforces review-only.

Per-CLI notes: read-only options and their traps, structured-output flags,
absent-vs-errored, auth: live in
[`references/cli-invocations.md`](references/cli-invocations.md). Read it only when a CLI
misbehaves or the panel roster changes.

### 4. Cluster into consensus

First check the panel had a quorum: at least two CLIs must have **responded**, not just
been present. With fewer, there is no consensus: report the single result plainly and
say the panel was short.

Collect the results. Match points that make the same claim, even when worded differently
or aimed at the same area. Grade each cluster by the share of the responders (`N`) that
raised it, and state `N` so a grade is never read as more agreement than it holds:

- **Unanimous**: all `N`.
- **Majority**: more than half, but not all.
- **Split**: exactly half (a tie; only when `N` is even).
- **Lone**: fewer than half.
- **Conflict**: CLIs directly disagree on the same point.

Clustering is a judgement call. When two points are plausibly the same, join them; a
borderline join that lifts a point to a higher grade is the whole value of the panel.

### 5. Report the consensus

Print the clusters, most-agreed first, under `## Unanimous`, `## Majority`, `## Split`,
`## Lone`, `## Conflict` (skip any that are empty). One line per point: the **claim**,
its **location**, the CLIs that raised it in brackets, e.g. `[claude, codex, grok]`, 
and its one-line **reason**. For a Conflict, state both sides and who holds each.

Then a one-line summary: how many points at each grade, the responder count `N`, and any
CLI that was absent or errored.

Close with a **Recommended next steps** block, ordered by confidence:

1. **Fix now**: list every Unanimous and Majority point as a checklist. These are the
   panel's confident calls.
2. **Weigh**: list the Split, Lone, and Conflict points. Decide each on its merits; do
   not batch-apply them.
3. **Offer the shortcut**: ask whether to apply the Fix-now set as one commit, naming
   the count, e.g. "Reply *fix all* to apply the 3 confident fixes."

## Safety

Headless mode auto-approves every tool, so each CLI *could* write files even though the
brief says review only. Two guards, in order: run the panel on a clean working tree, and
in review shape revert any stray write with the `git status` check in step 3. Per-CLI
read-only flags exist but behave inconsistently, `codex --sandbox read-only` works,
`agy --mode plan` hijacks the task into planning, and `grok`'s profile name is
machine-specific, so the tree check, not a flag, is what enforces read-only. See the
references file.
