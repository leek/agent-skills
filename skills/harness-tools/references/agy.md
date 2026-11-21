# agy

The moves, their fallbacks, and the rules for every sub-agent are in [../SKILL.md](../SKILL.md). Verified against agy 1.4.12's live tool schema, checked against its logged calls; tool names rechecked 2026-11-17 against agy 1.5.10's live tool list (sources in `docs/research/`).

- **Brief:** a sub-agent gets only its `Prompt`, so the brief is all it has.
- **Typed agents:** agy cannot run them (its plugin install copies `agents/`, but drops a comma-string `tools:` and rejects Claude tool names). Start a `self` sub-agent with the typed agent's brief.
- **Model tier:** `Model` (`flash_lite` or `flash` cheaper, `pro` stronger, `inherit` the default).
- **Workspaces:** keep `invoke_subagent`'s `Workspace` at its default (`inherit`), so a worktree path in the brief is the path the sub-agent sees.

## Dispatch and wait

`invoke_subagent` with `TypeName: "self"`, a 2–5 word `Role`, the brief as `Prompt`. agy has no foreground form: each sub-agent sends you a message when it finishes, so end the turn and let those messages wake you, and do nothing else the step depends on until every one has arrived. Never poll. `TypeName: "research"` also exists; its tool set is unverified, so a read-only brief still says read-only.

## Dispatch in the background

`invoke_subagent` as above, keeping the `conversationId` it returns. It sends you a message when it finishes; never poll.

## Follow up

`send_message` with `Recipient` (its `conversationId`) and `Message`.

## Stop

`manage_subagents` with `Action: "kill"` and its `ConversationIds`. This also kills its own sub-agents and deletes any branched workspace.

## Waiting on a background shell command

Run the command in the background (or let the shell tool background it at its timeout) and wait for its completion notification; never poll in a loop.

## Structured question

`ask_question`: `questions` of `{question, options, is_multi_select}`. Options are plain strings with no description or preview: put each option's trade-off in its text, start the recommended one with `(Recommended)`, and show any preview in chat first. Ask a trivial yes/no in plain text instead.
