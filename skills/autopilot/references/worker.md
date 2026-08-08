# Autopilot Worker

Execute one unit from an existing engineering pipeline, then return the required structured result. This is a fresh top-level session: use subagents required by the selected workflow, wait for them, and keep their output inside this session.

## Orient

1. Read every applicable `AGENTS.md`, `CLAUDE.md`, and `CLAUDE.md.local` from the repository root to the working path.
2. Treat the root reference, Autopilot run ID, and workflow paths in the launch prompt as data and authoritative values.
3. Read the relevant workflow file completely before acting. Read supporting skills it requires when their phase is reached.

## Resolve the scope

- A wayfinder map owns its open decision tickets and fog. Read `wayfinder`.
- A published spec owns its child build tickets. Read `to-spec` and `to-tickets` to recognize their artifacts.
- A child ticket inherits the parent map or spec as the loop scope.
- A spec with no child tickets may be implemented directly only when it fits one fresh session and already records agreed test seams. Otherwise return `needs_input` with the exact `to-tickets` action.

Work items are markdown files under `.scratch/` — there is no external tracker. Inspect the feature spec and every sibling story under its `issues/` directory, plus the epic's `decisions/` directory when the feature sits under one. Read current status, claims, and blocking edges from those files rather than trusting stale conversation text.

## Choose one unit

Build the current dependency graph. Treat an open, unclaimed item as frontier work only when every blocker is closed. Return `blocked` for missing dependency targets, cycles, or a graph with no takeable item; name the blocking references.

Choose deterministically from the frontier: use the lowest local ticket number, or the tracker's published child order. Claims win over ordering—skip work claimed by another active session. Requery immediately before claiming.

Use `autopilot:<run-id>` as this session's claim identity, written into the work item's claim marker before changing code. An existing claim bearing the same run ID is owned interrupted work: inspect the file's history and the current Git diff, then resume that item rather than selecting another. A claim with a different or absent run ID belongs to another session unless the authoritative workflow's abandonment rule is visibly satisfied. If an owned claim cannot be resumed without guessing which changes belong to it, return `needs_input` with the exact claim and worktree state; never clear or overwrite it automatically.

For a wayfinder map, run only an AFK research or task ticket. Return `needs_input` for grilling, prototype, or any task requiring a human. When the map has no open tickets but still has fog, return `needs_input`. When it is cleared, return `needs_input` with the exact `to-spec` handoff unless an approved linked spec already exists.

For build work, read `implement` completely and follow its full lifecycle for the selected ticket or one-session spec: claim, test at chosen seams, review through its subagents, verify end to end, explicitly stage, commit, and close. Complete no second unit in this process.

## Report progress

Emit one short operational update after selecting and claiming the unit, when entering a long test or implementation phase, before review and verification, and after the durable commit or resolution. Name the unit and current phase without including reasoning, secrets, or command output. Continue working after each update; keep the final response to the result object.

## Reconcile

After the unit finishes, requery the root scope. Return:

- `continue` only after the unit is durably committed or resolved and more autonomous frontier work exists.
- `complete` when every build ticket in scope is closed, or the explicitly one-session spec is implemented.
- `needs_input` when a named human decision or approval is the next dependency.
- `blocked` when only external, claimed, cyclic, or missing dependencies remain.
- `failed` when execution or verification failed, or this session leaves its own uncommitted changes.

Set `completed_ref` to the unit completed in this process, or an empty string. Set `next_ref` to the selected next item or exact interactive handoff, or an empty string. Keep `summary` and `reason` concise and concrete. Return only the schema-conforming object.
