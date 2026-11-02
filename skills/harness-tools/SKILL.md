---
name: harness-tools
description: The tool each agent harness (Claude Code, Codex, Grok, agy) uses to start, follow up with, or stop a sub-agent, and to ask the user a structured question. Use when a skill names one of these moves and points here, or when you are not sure which tool your harness has for it.
user-invocable: false
---

# Harness Tools

Skills name a **move** (dispatch and wait, dispatch in the background, follow up, stop, structured question) and point here for the tool. Find your harness's row, use that tool with the skill's own content (the brief, the agent type, the options), and use the fallback when the tool is not in your tool list. A harness with no row here: use its own tool for the move if it has one, otherwise the fallback. The fallback is always a complete path.

Verified against: Codex CLI 0.166's model-visible tools; Grok's live tool schema and its logged calls (its parameter is `background`, though the docs say `run_in_background`); agy 1.4.12's live tool schema, checked against its logged calls.

## Every sub-agent

- **Brief it in full.** A sub-agent starts with none of your conversation: a Grok child starts a new conversation, Codex's `fork_turns: "none"` passes no history, and an agy sub-agent gets only its `Prompt`. Put every path, ref, and rule it needs in the brief.
- **Typed agents.** A skill may name a typed agent, `leek-skills:<name>`, often in its Claude Code clause. Claude Code and Grok both load these from this plugin's `agents/` when the plugin is installed, so in Grok pass that same name as `subagent_type`. Codex and agy never load `agents/`, and neither does a Claude Code or Grok install from `npx skills` alone. There, start a general sub-agent with the same brief, and hold it to the typed agent's rules (read-only, output shape) through the brief.
- **Model tier.** Where the skill asks for a cheaper or stronger model: Claude Code's `model` (`haiku`, `sonnet`, `opus`), Codex's `model` (omit it to inherit), agy's `Model` (`flash_lite` or `flash` cheaper, `pro` stronger, `inherit` the default). Grok: inherit.

## Dispatch and wait

Start one or more sub-agents and use every result before you go on. For several, start them all in one message first, then wait for all of them.

| Harness | Tool |
|---|---|
| Claude Code | `Agent` (foreground) |
| Codex | `spawn_agent` with a `task_name`, the brief as `message`, and `fork_turns: "none"`; then call `wait_agent` (raise `timeout_ms`, up to 3600000) until each one's final answer has arrived. `wait_agent` reports which agents have updates; the answers arrive as messages. |
| Grok | `spawn_subagent` with `background: false` |
| agy | `invoke_subagent` with `TypeName: "self"`, a 2–5 word `Role`, the brief as `Prompt`. agy has no foreground form: each sub-agent sends you a message when it finishes, so end the turn and let those messages wake you, and do nothing else the step depends on until every one has arrived. Never poll. `TypeName: "research"` also exists; its tool set is unverified, so a read-only brief still says read-only. |

Fallback: do the work inline, and say so.

## Dispatch in the background

Start sub-agents and keep working on something else; collect each result when it lands. Keep each returned name or id against the skill's label for it, so you can follow up or stop it.

| Harness | Tool |
|---|---|
| Claude Code | `Agent` with `run_in_background: true` where offered (sub-agents may already default to the background), and a `name`. Each completion notification wakes you; end the turn while you wait, and never poll. |
| Codex | `spawn_agent` as above, keeping each `task_name`. Do the other work in the same turn, then `wait_agent` for the results. Do not end the turn while they run. |
| Grok | `spawn_subagent` (`background` defaults to true), keeping each id. The harness notifies you when a child finishes; then read its result with `get_command_or_subagent_output`. Never poll. |
| agy | `invoke_subagent` as above, keeping the `conversationId` it returns. It sends you a message when it finishes; never poll. |

Fallback: run them inline one after another.

A sub-agent's handle dies at `/clear`, at session end, and at compaction. In anything durable (tickets, comments, hand-off text), refer to its output by file path, never by task id.

## Follow up

Send more work to a sub-agent that is running or has finished, so it keeps its context.

| Harness | Tool |
|---|---|
| Claude Code | `SendMessage` to its `name` |
| Codex | `followup_task` to its `task_name` (starts a turn if it is idle), or `send_message` (no new turn) |
| Grok | `send_subagent_message`, only when active agent messages are on (`GROK_ACTIVE_AGENT_MESSAGES` or `[features] active_agent_messages`); otherwise wait for it to finish and continue it with `resume_from` |
| agy | `send_message` with `Recipient` (its `conversationId`) and `Message` |

Fallback: brief a fresh sub-agent with everything the follow-up needs (paths, the finding, the failure output).

## Stop

| Harness | Tool |
|---|---|
| Claude Code | `TaskStop` with its name or task id |
| Codex | `interrupt_agent` (it stops the current turn; the agent stays available for follow-ups) |
| Grok | `kill_command_or_subagent` |
| agy | `manage_subagents` with `Action: "kill"` and its `ConversationIds`. This also kills its own sub-agents and deletes any branched workspace. |

Fallback: leave it running and say so in the report.

## Structured question

A click-to-answer question: the recommended option first and marked as recommended, real options only, and a free-text Other that the harness adds. When the skill asks for more questions or options than your tool takes, split them over further calls; when it asks for `multiSelect` and your tool has none, ask that question in chat.

| Harness | Tool | Shape |
|---|---|---|
| Claude Code | `AskUserQuestion` | Up to 4 questions per call, 2–4 options each. Each question has a `header` (12 characters at most); each option a `label` and a `description`, and may have a `preview` (single-select only). `multiSelect: true` for a pick-several question. |
| Grok | `ask_user_question` | Like Claude Code, but the pick-several flag is `multi_select` and there is no `header`. Options take `label`, `description`, and `preview`. |
| Codex | `request_user_input`, only when it is in your tool list for this turn (Plan mode) | 1–3 questions, each with a `header` (12 characters at most), an `id`, and 2–3 single-select options of `label` and `description`. No `preview` and no multi-select: put a short snippet in the option description, or show side-by-side artifacts in chat first. |
| agy | `ask_question` | `questions` of `{question, options, is_multi_select}`. Options are plain strings with no description or preview: put each option's trade-off in its text, start the recommended one with `(Recommended)`, and show any preview in chat first. Ask a trivial yes/no in plain text instead. |

Fallback: the same shape in chat: the question, the numbered options with the recommendation first, then wait for the answer.

## Workspaces

A skill that makes its own git worktree passes that path in the brief. In agy, keep `invoke_subagent`'s `Workspace` at its default (`inherit`), so the path in the brief is the path the sub-agent sees.
