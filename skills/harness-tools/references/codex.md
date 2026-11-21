# Codex

The moves, their fallbacks, and the rules for every sub-agent are in [../SKILL.md](../SKILL.md). Verified against Codex CLI 0.166's model-visible tools; tool names rechecked 2026-11-17 against Codex 0.169's live tool list (sources in `docs/research/`).

- **Brief:** `fork_turns: "none"` passes no history, so the brief is all the sub-agent has.
- **Typed agents:** Codex never loads `agents/`. Start a general sub-agent with the typed agent's brief.
- **Model tier:** `model`; omit it to inherit.

## Dispatch and wait

`spawn_agent` with a `task_name`, the brief as `message`, and `fork_turns: "none"`; then call `wait_agent` (raise `timeout_ms`, up to 3600000) until each one's final answer has arrived. `wait_agent` reports which agents have updates; the answers arrive as messages.

## Dispatch in the background

`spawn_agent` as above, keeping each `task_name`. Do the other work in the same turn, then `wait_agent` for the results. Do not end the turn while they run.

Codex limits how many agent threads are live at once. When `spawn_agent` fails with `agent thread limit reached`, `wait_agent` until one running agent finishes, then spawn the next; when none is running, do that piece inline. An agent whose status is `errored` (for example `out of credits`) produced nothing: report it once and do its piece inline in the same turn.

## Follow up

`followup_task` to its `task_name` (starts a turn if it is idle), or `send_message` (no new turn).

## Stop

`interrupt_agent`. It stops the current turn; the agent stays available for follow-ups.

## Structured question

`request_user_input`, only when it is in your tool list for this turn (Plan mode): 1–3 questions, each with a `header` (12 characters at most), an `id`, and 2–3 single-select options of `label` and `description`. No `preview` and no multi-select: put a short snippet in the option description, or show side-by-side artifacts in chat first.
