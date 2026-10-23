# Ticket board

A multi-ticket run (`implement-spec`, `implement <spec> all`, `wayfinder <map> all`) can show each ticket's status in a pane beside the chat. The skill that points here names its statuses; this file holds the rest.

- **Only where it exists.** Use it when the harness lists the `mcp__leek-skills__ticket_board` tool (Claude Code with this plugin; load it with ToolSearch if it is deferred). Elsewhere, skip it: the run is complete without it.
- **What to send.** `board: <slug>`, `kind: "spec"` or `"map"`, and only the tickets that changed, each with `number`, `status`, and a `note` of a few words where the skill names one. The first call lists every in-scope ticket with its `title`; a ticket created mid-run joins with its `title` on its first call.
- **When.** The first call goes out as soon as the run has read every ticket's frontmatter, before any question, branch, worktree, or claim: the pane is how the person watches the setup too. After that, at every status change, with the changes of one moment in one call.
- **Worker names.** Name each sub-agent that works one ticket `<slug>--<NN>` where the Agent tool takes a `name`; the pane shows its live tool count on that ticket's row.
- **The tracker stays the record.** The board never replaces a claim, a resolution, or a status in `.scratch/`.
- **Progress lines.** When the reply says a pane shows the run, skip the skill's chat progress line for that change. When the tool is absent or the reply says no pane shows it, post the line as before.
