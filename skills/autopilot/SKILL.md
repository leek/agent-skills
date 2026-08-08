---
name: autopilot
description: Drive an existing wayfinder map, spec, or set of tickets to completion through fresh top-level Claude Code or Codex sessions.
disable-model-invocation: true
---

# Autopilot

Run approved pipeline work until it is complete or reaches a genuine human gate. Keep `wayfinder`, `to-spec`, `to-tickets`, and `implement` authoritative; this skill adds a fresh-process loop around them.

## Start the loop

1. Require a reference to a `wayfinder` map, a spec, or a ticket. Run from the target Git repository.
2. Select the current harness as the provider: `claude` in Claude Code, `codex` in Codex. When running directly from a terminal, require the user to choose.
3. Resolve this skill's installed directory, then run the bundled script by absolute path while keeping the target repository as the working directory:

```bash
bash <autopilot-skill-dir>/scripts/autopilot.sh --provider <claude|codex> --root <ref>
```

Pass `--repo <path>` when the target is not the current repository, `--max-iterations <n>` to replace the default limit of 50, and `--log-file <path>` to mirror the per-run log to another path.

Run the script as a background task and poll its output: one iteration is a full build lifecycle and routinely outlasts a foreground shell-command timeout. Immediately report the run ID, worker session model and effort, log path, and printed observer commands. Then report worker milestones and five-minute heartbeats from stderr as they arrive; leave routine tool events in the log.

Foreground run mode prints progress to stderr and one terminal result object to stdout; completion is exit code `0` with `status: complete`. Observer modes keep their operational messages on stderr: `--status` prints one state object, `--history` prints an array of retained states, `--tmux` prints one launch object, and `--follow` streams the human-readable run log to stdout.

Use the printed commands to inspect a run independently:

```bash
bash <autopilot-skill-dir>/scripts/autopilot.sh --status --root <ref> [--repo <path>]
bash <autopilot-skill-dir>/scripts/autopilot.sh --follow --root <ref> [--repo <path>]
bash <autopilot-skill-dir>/scripts/autopilot.sh --history --root <ref> [--repo <path>]
```

`--follow` exits when the run does; `--history` returns every retained run for the root. For a detached terminal-owned run, add `--tmux`. Its stdout is a launch object rather than the eventual worker result. Report the printed `status`, `follow`, and `tmux attach` commands; continue monitoring through `--status` until the run reaches a terminal state. Read the exact terminal result from the `result_file` in status.

## Worker model and effort

Every worker session is one sub-session of the run, and every run reports which model and reasoning effort those sub-sessions use. The report appears in four places: the `worker session model <model> (<source>), effort <level> (<source>)` line at run start, the per-iteration line, each heartbeat, and `--status` (as the `model`, `model_source`, `effort`, `effort_source`, and `reported_model` state fields). A `--tmux` launch object carries the same values.

Set them explicitly to pin every sub-session:

```bash
bash <autopilot-skill-dir>/scripts/autopilot.sh --provider <claude|codex> --root <ref> --model <name> --effort <level>
```

`AUTOPILOT_MODEL` and `AUTOPILOT_EFFORT` are the environment equivalents. Valid effort levels are `low|medium|high|xhigh|max` for `claude` and `none|minimal|low|medium|high|xhigh|max` for `codex`; the runner rejects anything else before starting a worker.

The `source` names where each value came from: `requested` for a flag or environment variable, `settings` for the resolved Claude Code settings chain (`model` and `effortLevel`, honoring `CLAUDE_CONFIG_DIR`), `config` for `$CODEX_HOME/config.toml` (`model` and `model_reasoning_effort`), and `provider default` when neither is set and the provider chooses. Claude workers also report the model the session actually resolved; that authoritative value is announced when it differs from the requested one — an alias like `opus` resolving to a dated model ID — and is kept in state as `reported_model`.

## Fresh-process contract

Each iteration launches a new top-level CLI process with normal user and project configuration but with permission prompts and sandboxing bypassed (`--dangerously-skip-permissions` / `--dangerously-bypass-approvals-and-sandbox`) — headless workers cannot answer prompts, so only start the loop on work the user has already approved for autonomous execution. It performs exactly one decision ticket or one build ticket, finishes all nested review and verification agents, records durable tracker and Git state, and exits. The next process rereads the root artifact and recomputes the dependency frontier.

The runner keeps durable state, a human-readable log, and raw provider events under the target repository's Git directory. Claims made by that run include the ID, so a later invocation of the same command can recognize and resume its own interrupted work item without taking over another session's work. A per-root lock prevents concurrent runner processes from sharing that identity. Terminal state remains inspectable; rerunning a completed root starts a new run, while failures and human gates resume the existing run.

A heartbeat proves that the worker process is alive. It defaults to five minutes; set `AUTOPILOT_HEARTBEAT_SECONDS` to a positive number of seconds when a different cadence is needed. `quiet threshold reached` means it has emitted no provider event for two heartbeat intervals; treat that as a prompt to inspect the log or attach, not proof that the worker is hung. The runner never kills quiet work automatically.

Use the installed workflow skills as the single source of truth. The script locates their `SKILL.md` files and passes their absolute paths to the worker. If the pipeline skills are absent, install this repository's complete skill collection before retrying.

## Ticket status

Every unit is marked in progress before work starts and closed after it is verified and committed, so the markdown tracker under `.scratch/` always reflects reality. The worker writes the transition in the shape its tracker uses — `**Status:** in-progress (claimed <date>, autopilot:<run-id>)` then `**Status:** closed` plus `## Resolution` for a build ticket or directly implemented spec; `claimed-by:` then `status: closed` for a `wayfinder` decision ticket.

The runner does not take that on trust. It snapshots every work item beside the root before each iteration, announces each status change afterwards (`ticket .scratch/x/issues/01-y.md: ready-for-agent -> closed`), and fails the run when a `continue` or `complete` result names a unit whose file is not closed — one iteration earlier than the repeated-`completed_ref` guard would catch it. A unit this run claimed and left open is announced as an open claim.

Stopping at a gate leaves the in-progress marker and the run's claim in place on purpose: that marker is how a later process recognizes its own resumable work rather than colliding with another session's.

## Human gates

Headless workers cannot conduct a live interview or approve a new spec or ticket breakdown. Stop with `needs_input` when `wayfinder` reaches a HITL ticket, `to-spec` needs seam or publication approval, `to-tickets` needs breakdown approval, or implementation exposes an undecided product question. After resolving the gate interactively, rerun the same command; tracker state and commits are the resume point.

If an interrupted owned claim cannot be safely resumed from the current tracker and worktree state, stop with `needs_input` and identify the claim and unresolved changes. Never clear or take over a differently owned claim automatically.

Exit codes are `0` complete, `2` needs input, `3` blocked, `4` worker failure, `5` runner/configuration failure, `129` hangup, `130` interrupted, and `143` terminated.
