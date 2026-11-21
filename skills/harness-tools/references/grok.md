# Grok

The moves, their fallbacks, and the rules for every sub-agent are in [../SKILL.md](../SKILL.md). Verified against Grok's live tool schema and its logged calls (its parameter is `background`, though the docs say `run_in_background`); tool names rechecked 2026-11-17 against Grok 1.0.88's live tool list (sources in `docs/research/`).

- **Brief:** a child starts a new conversation, so the brief is all it has.
- **Typed agents** load from this plugin's `agents/` when the plugin is installed: pass the same `leek-skills:<name>` as `subagent_type`. An install from `npx skills` alone has none.
- **Model tier:** inherit.

## Dispatch and wait

`spawn_subagent` with `background: false`.

## Dispatch in the background

`spawn_subagent` (`background` defaults to true), keeping each id. The harness notifies you when a child finishes; then read its result with `get_command_or_subagent_output`. Never poll.

## Follow up

`send_subagent_message`, only when active agent messages are on (`GROK_ACTIVE_AGENT_MESSAGES` or `[features] active_agent_messages`); otherwise wait for it to finish and continue it with `resume_from`.

## Stop

`kill_command_or_subagent`.

## Waiting on a background shell command

Run the command in the background (or let the shell tool background it at its timeout) and wait for its completion notification; never poll in a loop.

## Structured question

`ask_user_question`: like Claude Code's, but the pick-several flag is `multi_select` and there is no `header`. Up to 4 questions per call, 2–4 options each; options take `label`, `description`, and `preview`.
