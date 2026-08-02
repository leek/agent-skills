---
name: autopilot
description: Drive an existing wayfinder map, spec, or ticket set to completion through fresh top-level Claude Code or Codex sessions.
disable-model-invocation: true
---

# Autopilot

Run approved pipeline work until it is complete or reaches a genuine human gate. Keep `wayfinder`, `to-spec`, `to-tickets`, and `implement` authoritative; this skill adds a fresh-process loop around them.

## Start the loop

1. Require a map, spec, parent ticket, or child ticket reference. Run from the target Git repository.
2. Select the current harness as the provider: `claude` in Claude Code, `codex` in Codex. When running directly from a terminal, require the user to choose.
3. Resolve this skill's installed directory, then run the bundled script by absolute path while keeping the target repository as the working directory:

```bash
bash <autopilot-skill-dir>/scripts/autopilot.sh --provider <claude|codex> --root <ref>
```

Pass `--repo <path>` when the target is not the current repository and `--max-iterations <n>` to replace the default limit of 50.

Run the script as a background task and poll its output: one iteration is a full build lifecycle and routinely outlasts a foreground shell-command timeout. Report progress from stderr as it arrives.

The script prints progress to stderr and one result object to stdout. Completion is an exit code of `0` with `status: complete`.

## Fresh-process contract

Each iteration launches a new top-level CLI process with normal user and project configuration but with permission prompts and sandboxing bypassed (`--dangerously-skip-permissions` / `--dangerously-bypass-approvals-and-sandbox`) — headless workers cannot answer prompts, so only start the loop on work the user has already approved for autonomous execution. It performs exactly one decision ticket or build ticket, finishes all nested review and verification agents, records durable tracker and Git state, and exits. The next process rereads the root artifact and recomputes the dependency frontier.

The runner keeps a durable run ID under the target repository's Git directory. Claims made by that run include the ID, so a later invocation of the same command can recognize and resume its own interrupted ticket without taking over another session's work. A per-root lock prevents concurrent runner processes from sharing that identity. Successful completion removes the runner state; failures and human gates retain it for recovery.

Use the installed workflow skills as the single source of truth. The script locates their `SKILL.md` files and passes their absolute paths to the worker. If the pipeline skills are absent, install this repository's complete skill collection before retrying.

## Human gates

Headless workers cannot conduct a live interview or approve a new spec or ticket breakdown. Stop with `needs_input` when `wayfinder` reaches a HITL ticket, `to-spec` needs seam or publication approval, `to-tickets` needs breakdown approval, or implementation exposes an undecided product question. After resolving the gate interactively, rerun the same command; tracker state and commits are the resume point.

If an interrupted owned claim cannot be safely resumed from the current tracker and worktree state, stop with `needs_input` and identify the claim and unresolved changes. Never clear or take over a differently owned claim automatically.

Exit codes are `0` complete, `2` needs input, `3` blocked, `4` worker failure, and `5` runner/configuration failure.
