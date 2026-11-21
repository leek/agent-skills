# Claude Code

The moves, their fallbacks, and the rules for every sub-agent are in [../SKILL.md](../SKILL.md). Verified against Claude Code 2.1.291–2.1.325 session logs (a named sub-agent got 0 of 266 wakes from its own background command, an unnamed one 175 of 230).

- **Typed agents** `leek-skills:<name>` load from this plugin's `agents/` when the plugin is installed. An install from `npx skills` alone has none.
- **Model tier:** `model` (`haiku`, `sonnet`, `opus`).

## Dispatch and wait

`Agent` in the foreground.

## Dispatch in the background

`Agent` with `run_in_background: true` where offered (sub-agents may already default to the background), and **no `name`**: a named sub-agent becomes a teammate, and a teammate is never woken by its own background command, so it sleeps until you message it. Keep the `agentId` its result returns, and put the skill's label first in `description` (`<slug>--<NN> build`). Each completion notification wakes you; end the turn while you wait, and never poll.

The interim notice that an unnamed agent "is waiting on its own background work" gets no reply: end the turn without text. The harness resumes it when that work ends.

## Follow up

`SendMessage` to its `agentId` (or its `name`, for one started with a name).

## Stop

`TaskStop` with its `agentId` or task id.

## Structured question

`AskUserQuestion`: up to 4 questions per call, 2–4 options each. Each question has a `header` (12 characters at most); each option a `label` and a `description`, and may have a `preview` (single-select only). `multiSelect: true` for a pick-several question.
