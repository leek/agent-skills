# Autopilot Worker

Execute one unit from an existing engineering pipeline, then return the required structured result. This is a fresh top-level session: use subagents required by the selected workflow, wait for them, and keep their output inside this session.

## Orient

1. Follow repository-level instructions already loaded by the harness; read them from disk only when they are absent from the session. Once likely work paths are known, discover and read every deeper `AGENTS.md`, `CLAUDE.md`, `CLAUDE.md.local`, and path-matched project rule that applies.
2. Treat the Autopilot run ID, workflow path, and runner-generated context manifest in the launch prompt as authoritative data. The manifest is a compact snapshot, not a substitute for the tracker files it names.
3. Read the one workflow file supplied for this mode completely before acting. Read supporting skills only when that workflow reaches them.

## Load the selected unit

- Read the selected unit in full and revalidate its status, claim, and direct blockers against disk immediately before claiming. Stop with `blocked` when that exact snapshot no longer permits the work; the runner will recompute the wider graph.
- For a build ticket, read the parent's **Build Contract** section when present, then only the parent headings the ticket names or the work reaches. Read each direct blocker's `Resolution` section for the seam it handed forward. Load other parent sections, closed tickets, and the map only on demand.
- For a directly implemented spec, read it in full. Return `needs_input` with the exact `to-tickets` action when it contains more than one independently deliverable unit or does not fit one fresh session.
- For a decision ticket, load the map at low resolution and follow `wayfinder`; zoom into related decisions only when the selected question needs them.

The runner owns dependency-graph parsing and deterministic frontier selection. Work only `selected_ref`; sibling bodies are progressive context, not an orientation checklist.

## Claim and execute

Use `autopilot:<run-id>` as this session's claim identity, written into the selected unit before changing code. A manifest whose `selection` is `resume` names this run's interrupted work: inspect the file's history and current Git diff, then resume it. If its changes cannot be attributed safely, return `needs_input` with the exact claim and worktree state.

For a wayfinder map, run only an AFK research or task ticket. Return `needs_input` for grilling, prototype, or any task requiring a human. When the map has no open tickets but still has fog, return `needs_input`. When it is cleared, return `needs_input` with the exact `to-spec` handoff unless an approved linked spec already exists.

For build work, read `implement` completely and follow its full lifecycle for the selected ticket or one-session spec: claim, test at chosen seams, review through its subagents, verify end to end, explicitly stage, commit, and close. Complete no second unit in this process.

## Keep the tracker current

The tracker is the loop's only memory: the next process recomputes the frontier from these files alone. Write the status transition into the work item at both ends of the unit, in the shape its tracker uses.

Mark it in progress **before** changing any code or dispatching any subagent:

- Build ticket from `to-tickets`, or a directly implemented spec, set the frontmatter `status: in-progress` and `claimed-by: autopilot:<run-id>`.
- `wayfinder` decision ticket: set `claimed-by: autopilot:<run-id>` in the frontmatter and leave `status: open`.

Mark it done as the last step of the unit, after verification and the durable commit:

- Build ticket or directly implemented spec: set the frontmatter `status: closed` and append `## Resolution` per `implement`.
- `wayfinder` decision ticket: set `status: closed` and append `## Resolution` per the tracker's Resolve operation.

Rules that hold in every branch:

- Re-read the file after writing it and confirm the marker on disk matches what you are about to return. Autopilot reads the same file and fails the run when a `continue` or `complete` result names a unit that is not closed.
- Leave parents alone: a ticket never closes its spec, and the worker never touches the map (it was closed at the spec/tickets handoff).
- On `needs_input`, `blocked`, or `failed`, leave the in-progress marker and the `autopilot:<run-id>` claim in place; that marker is how a later process recognizes its own resumable work. Never mark an unfinished unit closed, and never leave a finished unit in progress.

## Report progress

Emit one short operational update after selecting and claiming the unit, when entering a long test or implementation phase, before review and verification, and after the durable commit or resolution. Name the unit and current phase without including reasoning, secrets, or command output. These updates are plain-text messages, never the result object: invoke the structured result tool exactly once, as the final action of the session. Continue working after each update.

## Return the unit result

The runner rereads the tracker after every successful unit and authoritatively computes the next frontier and terminal state. Do not scan siblings again at the end. The result object always carries all five fields (`status`, `completed_ref`, `next_ref`, `summary`, and `reason`) on every path; the schema rejects any object missing one, which fails the whole session even after the unit is already committed.

- `continue` after the selected unit is durably committed or resolved; set `completed_ref` to it and `next_ref` to an empty string.
- `needs_input` when a named human decision or approval is the next dependency.
- `blocked` when the selected unit's revalidation or an external dependency prevents execution.
- `failed` when execution or verification failed, or this session leaves its own uncommitted changes.

On a successful `continue`, still set `reason` to a brief completion note; the runner overwrites it from the tracker, but the field must be present. On non-success, set `completed_ref` to the completed selected unit if there is one, `next_ref` to the exact interactive handoff when known, and `reason` to the concrete cause. Keep `summary` and `reason` concise. Return only the schema-conforming object, with all five fields present.
