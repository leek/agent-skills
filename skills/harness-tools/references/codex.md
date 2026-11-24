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

## Waiting on a background shell command

Start it with `exec_command`, then poll with an empty `write_stdin` at `yield_time_ms: 300000` on every poll until it exits, the longest an empty poll takes (verified on Codex CLI 0.169). Each poll re-reads the whole context, so a 1- to 60-second yield costs a full step for nothing. Between polls, send nothing: one waiting message covers the checkpoint, and the next message reports its verdict.

## Structured question

`request_user_input`, only when it is in your tool list for this turn (Plan mode): 1–3 questions, each with a `header` (12 characters at most), an `id`, and 2–3 single-select options of `label` and `description`. No `preview` and no multi-select: put a short snippet in the option description, or show side-by-side artifacts in chat first.

Prefer `request_user_input` whenever it is in your tool list: it blocks until the user answers, so the question stays open. Use `request_user_input_async` only when the blocking tool is absent. It returns as soon as the question is displayed, before the user answers: an `accepted` result means delivery, not an answer, and ending the turn can dismiss its controls. No tool is known to wait for the answer (the top-level `wait` is not documented as one), so after an async question, do only work that does not depend on the answer, then end the turn with the chat fallback: the complete question and its numbered choices in the final reply, so it stays answerable after the controls disappear. Never end on a status summary while a question is pending.

Keep the decision open until the user answers; elapsed time, dismissal, or a new unrelated message is not a choice.
