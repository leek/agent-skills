# Map run

A **map run** (`/wayfinder <map> all`) works every ticket of one map in this session, in frontier order, until the map is clear. Each ticket still gets its own claim, its own resolution, and the same steps as **Work through the map**: the run only removes the `/clear` and re-invoke between them. Use it when most tickets need one or two answers from the user; a map whose tickets each need a long grilling or a prototype still reads better one per session.

The tracker is the run's memory. A closed ticket's `## Resolution` holds everything later tickets need, so nothing about it has to stay in context: fetch it again when a later ticket depends on it, the same as a fresh session would.

**Ticket board.** Report each ticket's status per [`ticket-board.md`](ticket-board.md), with `kind: "map"`: `ready` and `blocked` (note: the blockers) at the start, `skipped` for tickets claimed by someone else, `running` at its claim (a research sub-agent takes the name `<slug>--<NN>`), `resolved` (note: the decision, in a few words), `closed` when ruled out of scope or superseded (note: why), and `released` (note: why). A ticket an answer creates joins the board as `ready` or `blocked`.

## Loop

1. **Dispatch the research.** Claim every research ticket on the frontier and send each to its own research sub-agent at once, per the `research` skill's Wayfinder integration (in Claude Code, the `leek-skills:researcher` agent in the background; in Codex, `spawn_agent` with `fork_turns: "none"`; otherwise run them inline before step 2). Resolve each as its findings land. Done when every frontier research ticket is claimed and running or resolved.
2. **Take the next ticket.** The first unclaimed frontier ticket that is not research, by number. Claim it.
3. **Gather the facts away from the main context.** When the ticket needs code or docs read before a question can be framed, send one read-only exploration sub-agent with the ticket's question and ask for a short brief: the facts, the existing pattern, file:line pointers (in Claude Code, the `Explore` agent; in Codex, `spawn_agent` with `fork_turns: "none"`; otherwise read inline, sparingly). Done when you can state the situation each question needs.
4. **Resolve it** per its type, exactly as in **Work through the map** steps 3–5: grill (one question at a time, defaults recorded), resolve, add or graduate tickets, close what the answer invalidated.
5. **Report one line**, then loop to step 1: `<ticket name> resolved (<k> of <n>); next: <ticket name>`. Skip the line when the ticket board's pane shows the run. New research tickets an answer created are dispatched on the next pass.

## Stop

Stop the loop, print the end-of-session block, and name which condition fired:

- **The map is clear**: no ticket open, nothing in Not yet specified. Next is `/to-spec`.
- **The user says stop.** Release any ticket claimed but unresolved, with a `## Comments` note saying what was decided so far.
- **Every open ticket is blocked** on knowledge only someone else holds (`/to-questionnaire`) or on a research sub-agent still running. Wait for the running ones; the run ends when nothing can move.
- **A ticket needs work outside the session**: a task ticket only the human can perform, or a prototype the user wants to sit with. Release it with a note and keep working the rest of the frontier; stop when only such tickets remain.

Never leave a research sub-agent running past the end of the run: collect its findings and resolve its ticket first, or release the ticket and say so.
