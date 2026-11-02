---
name: harness-tools
description: The tool each agent harness (Claude Code, Codex, Grok, agy) uses to start, follow up with, or stop a sub-agent, and to ask the user a structured question. Use when a skill names one of these moves and points here, or when you are not sure which tool your harness has for it.
user-invocable: false
---

# Harness Tools

Skills name a **move** (dispatch, follow up, stop, structured question) and point here for the tool. Find your harness's row, use that tool with the skill's own content (the brief, the agent type, the options), and use the fallback when your harness has no row or the tool is not in your tool list. The fallback is always a complete path.

Verified against: Codex CLI 0.165's model-visible tools; Grok's live tool schema (its parameter is `background`, though the docs say `run_in_background`); agy 1.4.12's live tool schema, checked against its logged calls.

## Typed agents

A skill may name a typed agent, `leek-skills:<name>`, often in its Claude Code clause. Claude Code and Grok both load these from this plugin's `agents/` when the plugin is installed, so in Grok pass that same name as `subagent_type`. Codex and agy never load `agents/`, and neither does a Claude Code or Grok install from `npx skills` alone. There, start a general sub-agent with the same brief, on the model tier the skill asks for where the harness lets you choose.

## Dispatch and wait

Start a sub-agent and use its result before you continue.

| Harness | Tool |
|---|---|
| Claude Code | `Agent` (foreground) |
| Codex | `spawn_agent` with `fork_turns: "none"`, then `wait_agent` |
| Grok | `spawn_subagent` with `background: false` |
| agy | `invoke_subagent` with `TypeName: "self"`, a 2–5 word `Role`, the brief as `Prompt`. It always runs in the background and sends you a message when it finishes: end the turn and let that message wake you; never poll. |

Fallback: do the work inline, and say so.

## Dispatch in the background

Start one or more sub-agents and keep working; each one's completion wakes you. Keep each returned name or id against the skill's label for it, so you can follow up or stop it.

| Harness | Tool |
|---|---|
| Claude Code | `Agent` with `run_in_background: true` where offered (sub-agents may already default to the background), and a `name` |
| Codex | `spawn_agent` with `fork_turns: "none"`, then `wait_agent` to collect each result |
| Grok | `spawn_subagent` (`background` defaults to true), then `get_command_or_subagent_output` to collect each result |
| agy | `invoke_subagent` as above; keep the `conversationId` it returns |

Fallback: run them inline one after another.

A sub-agent's handle dies at `/clear`, at session end, and at compaction. In anything durable (tickets, comments, hand-off text), refer to its output by file path, never by task id.

## Follow up

Send more work to a sub-agent that is running or has finished, so it keeps its context.

| Harness | Tool |
|---|---|
| Claude Code | `SendMessage` to its `name` |
| Codex | `followup_task` (starts a new turn) or `send_message` (no new turn) |
| Grok | `send_subagent_message`, only when active agent messages are on (`GROK_ACTIVE_AGENT_MESSAGES` or `[features] active_agent_messages`); otherwise wait for it to finish and continue it with `resume_from` |
| agy | `send_message` with `Recipient` (its `conversationId`) and `Message` |

Fallback: brief a fresh sub-agent with everything the follow-up needs (paths, the finding, the failure output).

## Stop

| Harness | Tool |
|---|---|
| Claude Code | `TaskStop` with its name or task id |
| Codex | `interrupt_agent` |
| Grok | `kill_command_or_subagent` |
| agy | `manage_subagents` with `Action: "kill"` and its `ConversationIds`. This also kills its own sub-agents and deletes any branched workspace. |

Fallback: leave it running and say so in the report.

## Structured question

A click-to-answer question: the recommended option first and marked as recommended, 2–4 real options, and a free-text Other that the harness adds.

| Harness | Tool | Limits |
|---|---|---|
| Claude Code | `AskUserQuestion` | Up to 4 questions per call. Each option has a `label` and a `description`, and may have a `preview` (single-select only). `multiSelect` for a pick-several question. |
| Grok | `ask_user_question` | Same shape as Claude Code. |
| Codex | `request_user_input`, only when it is in your tool list for this turn | No `preview`: put a short snippet in the option description, or show side-by-side artifacts in chat first. |
| agy | `ask_question` | `questions` of `{question, options, is_multi_select}`. Options are plain strings with no description or preview: put each option's trade-off in its text, start the recommended one with `(Recommended)`, and show any preview in chat first. Ask a trivial yes/no in plain text instead. |

Fallback: the same shape in chat: the question, the numbered options with the recommendation first, then wait for the answer.

## Workspaces

A skill that makes its own git worktree passes that path in the brief. In agy, keep `invoke_subagent`'s `Workspace` at its default (`inherit`), so the path in the brief is the path the sub-agent sees.
