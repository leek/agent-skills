---
name: panel
description: Convene a panel of agent CLIs (grok, claude, codex, agy) on a prompt or a code review, then report one consensus grouped by how much they agree.
disable-model-invocation: true
argument-hint: "A prompt, or a review scope like 'review since main'"
allowed-tools: "Bash(bash *panel/scripts/launch.sh *) Bash(grok *) Bash(claude *) Bash(codex *) Bash(agy *)"
compatibility: "Needs at least one of the grok, claude, codex, or agy CLIs on PATH"
model: sonnet
effort: medium
---

# Panel

Put one task in front of four agent CLIs (`grok`, `claude`, `codex`, `agy`) run
each in its own subagent, headless, then report a single consensus grouped by how
much the panel agrees.

Each CLI runs as its own latest/default model. **Never pass `--model` to any of
them.** The point of the panel is four independent models; pinning a model defeats it.

## Process

### 1. Read the task and pick the shape

- **Review** when the user asks to review a branch, PR, WIP, or "review since X".
  Pin the fixed point the way `code-review` does: the diff is
  `git diff <fixed-point>...HEAD` (three-dot, against the merge-base), default
  `main` when the user names none. For uncommitted work in progress, drop the `...HEAD`
  so the diff also covers staged and unsaved changes. Confirm the ref resolves
  (`git rev-parse <fixed-point>`), record `git rev-parse HEAD`, and confirm the diff is non-empty **before** fanning out, 
  a bad ref should fail here, not inside four subagents. Then read
  [`references/review-shape.md`](references/review-shape.md): it holds the review task
  string, step 3's read-only guard, and step 5's `ReportFindings` mapping.
- **Prompt** otherwise; the user's text is the task, passed word for word.

Write the one task string now. Every CLI receives the identical string, so the four
results compare cleanly. Start it with this line, so a panelist never convenes its own
panel when the task mentions panels, panelists, or other CLIs:

> You are one panelist. Answer the task below yourself, directly. Do not run a panel, launch another agent CLI, or start subagents.

`$SCRATCH` is the session's scratchpad directory where the harness has one, otherwise
one `mktemp -d`; hand subagents its absolute path, since they do not share your shell.
Save the string to `$SCRATCH/panel-task.txt` with the file-write tool (where the harness
has none, a quoted heredoc: `cat > "$SCRATCH/panel-task.txt" <<'PANEL_EOF'`). The launcher
reads the file, so no launch command contains the task's words, and a guard hook that
reads the command (task text that names `git commit`, say) cannot block the launch.

### 2. Check who is on the panel

Run `command -v` for each of `grok`, `claude`, `codex`, `agy`. Drop any that is
absent and record it for the final report. If fewer than two remain, there is no
consensus to form: say which are missing and stop.

### 3. Fan out: one subagent per CLI, in parallel

Spawn one subagent per present CLI, all in a single message so they run at once (in
Claude Code with this plugin installed, `subagent_type=leek-skills:panelist`: a small,
cheap wrapper, since the thinking happens inside the CLI it runs; in other harnesses, dispatch
and wait per [harness-tools](../harness-tools/SKILL.md), one per CLI, all at once). Give each subagent
the path of the **same** task file and, in full, the brief in
[`references/panelist-brief.md`](references/panelist-brief.md), read on every run: launch
once through [`scripts/launch.sh`](scripts/launch.sh) with literal absolute paths, run it
detached, wait with one call and never poll, distill, return `{ cli, status, points[] }`.

In **review** shape, apply **Keep review read-only** from
[`references/review-shape.md`](references/review-shape.md): worktree isolation or a working-tree
baseline before the fan-out, a check for stray writes after every subagent returns.

Per-CLI notes: why each flag in `scripts/launch.sh` is there, read-only options and their
traps, structured-output flags, absent-vs-errored, auth: live in
[`references/cli-invocations.md`](references/cli-invocations.md). Read it only when a CLI
misbehaves or the panel roster changes.

### 4. Cluster into consensus

First check the panel had a quorum: at least two CLIs must have **responded**, not just
been present. With fewer, there is no consensus: report the single result plainly and
say the panel was short, with the step 5 ping.

Collect the results. Only a returned `{ cli, status, points[] }` object is a result: a
panelist pauses while its CLI runs, and a notification without that object is interim,
so end the turn with no reply and wait for the next one. Match points that make the same claim, even when worded differently
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

In review shape, where the host has `ReportFindings`, report the clusters through it
instead, per [`references/review-shape.md`](references/review-shape.md). Otherwise print every cluster.

Then a one-line summary: how many points at each grade, the responder count `N`, and any
CLI that was absent or errored. Ping the user that it is ready (`PushNotification`
where available, otherwise the report itself is the signal).

Close with a **Recommended next steps** block:

1. **Fix list**: every point at every grade, Unanimous through Lone, as one checklist. Do not
   curate: a Lone finding is a real finding until verified otherwise. For a Conflict, list both
   sides and say which one the code supports. After `ReportFindings`, the reported
   findings are the list; name their count instead of repeating them.
2. **Offer the shortcut**: ask whether to verify and apply the whole list as one commit, naming
   the count, e.g. "Reply *fix all* to verify and apply all 11 points."

On *fix all*, work every point: verify each against the code, apply the ones that hold, and
report the ones that do not with a one-line reason. Never apply only the confident subset and
hand the rest back as "weigh individually"; the user asked for the panel so they would not have
to re-adjudicate it. Ask only about a point that conflicts with a recorded decision.

## Safety

Headless mode auto-approves every tool, so each CLI *could* write files even though the
brief says review only. Two guards, in order: run the panel on a clean working tree, and
in review shape isolate or revert stray writes per step 3. Per-CLI read-only flags exist
but behave inconsistently (see [`references/cli-invocations.md`](references/cli-invocations.md)),
so step 3, not a flag, is what enforces read-only.
