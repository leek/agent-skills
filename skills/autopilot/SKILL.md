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

Run the script as a background task and poll its output: one iteration is a full build lifecycle and routinely outlasts a foreground shell-command timeout. Immediately report the run ID, log path, and printed observer commands. Then report worker milestones and five-minute heartbeats from stderr as they arrive; leave routine tool events in the log.

Foreground run mode prints progress to stderr and one terminal result object to stdout; completion is exit code `0` with `status: complete`. Observer modes keep their operational messages on stderr: `--status` prints one state object, `--history` prints an array of retained states, `--tmux` prints one launch object, and `--follow` streams the human-readable run log to stdout.

Use the printed commands to inspect a run independently:

```bash
bash <autopilot-skill-dir>/scripts/autopilot.sh --status --root <ref> [--repo <path>]
bash <autopilot-skill-dir>/scripts/autopilot.sh --follow --root <ref> [--repo <path>]
bash <autopilot-skill-dir>/scripts/autopilot.sh --history --root <ref> [--repo <path>]
```

`--follow` exits when the run does; `--history` returns every retained run for the root. For a detached terminal-owned run, add `--tmux`. Its stdout is a launch object rather than the eventual worker result. Report the printed `status`, `follow`, and `tmux attach` commands; continue monitoring through `--status` until the run reaches a terminal state. Read the exact terminal result from the `result_file` in status.

## Fresh-process contract

Each iteration launches a new top-level CLI process with normal user and project configuration but with permission prompts and sandboxing bypassed (`--dangerously-skip-permissions` / `--dangerously-bypass-approvals-and-sandbox`) — headless workers cannot answer prompts, so only start the loop on work the user has already approved for autonomous execution. It performs exactly one decision ticket or one build ticket, finishes all nested review and verification agents, records durable tracker and Git state, and exits. The next process rereads the root artifact and recomputes the dependency frontier.

The runner keeps durable state, a human-readable log, and raw provider events under the target repository's Git directory. Claims made by that run include the ID, so a later invocation of the same command can recognize and resume its own interrupted work item without taking over another session's work. A per-root lock prevents concurrent runner processes from sharing that identity. Terminal state remains inspectable; rerunning a completed root starts a new run, while failures and human gates resume the existing run.

A heartbeat proves that the worker process is alive. It defaults to five minutes; set `AUTOPILOT_HEARTBEAT_SECONDS` to a positive number of seconds when a different cadence is needed. `quiet threshold reached` means it has emitted no provider event for two heartbeat intervals; treat that as a prompt to inspect the log or attach, not proof that the worker is hung. The runner never kills quiet work automatically.

Use the installed workflow skills as the single source of truth. The script locates their `SKILL.md` files and passes their absolute paths to the worker. If the pipeline skills are absent, install this repository's complete skill collection before retrying.

## Human gates

Headless workers cannot conduct a live interview or approve a new spec or ticket breakdown. Stop with `needs_input` when `wayfinder` reaches a HITL ticket, `to-spec` needs seam or publication approval, `to-tickets` needs breakdown approval, or implementation exposes an undecided product question. After resolving the gate interactively, rerun the same command; tracker state and commits are the resume point.

If an interrupted owned claim cannot be safely resumed from the current tracker and worktree state, stop with `needs_input` and identify the claim and unresolved changes. Never clear or take over a differently owned claim automatically.

Exit codes are `0` complete, `2` needs input, `3` blocked, `4` worker failure, `5` runner/configuration failure, `129` hangup, `130` interrupted, and `143` terminated.
