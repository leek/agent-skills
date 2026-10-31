# Pipeline end-of-session block

**Single source of truth** for the banner format printed by pipeline skills (`grill-me`, `wayfinder`, `to-spec`, `to-tickets`, `implement`, `implement-spec`, and standalone `code-review` / `to-questionnaire`). Owned by `wayfinder` as the pipeline base. Stage skills keep their own **Done** placeholders and **Next** condition lists; they only restyle the frame here.

## When to print

Print on a clean finish, a stop, or a dead end: unless the skill says an inner invocation must stay silent (only the outermost skill prints).

## Frame

```text
---
Pipeline: <stage highlight on the decide → spec → tickets → build line>   (<n of 4 or role note>)
Done: <stage-specific summary>
Next:
  • <condition> → /<skill> <ref>
```

Rules:

1. Bold the current pipeline stage on the `decide → spec → tickets → build` line (or note a supporting role, e.g. review runs inside build).
2. Fill **Done** from live state: never guess at frontiers; query the markdown tracker when the skill owns one.
3. List only **Next** conditions that actually apply, most likely first. A condition applies while its trigger is still open, so a finished effort or a closed map adds none. When the user already made the choice (build on the current branch and commit there), the only Next line is that action, with no alternatives beside it. When nothing remains, leave out the Next line.
4. Never tell the user to `/clear`, compact, or start a fresh session, in **Next** or anywhere in the block. Each **Next** line is the command alone; when and whether to clear is the user's call.
5. Prefix the **Done** line with ✅ (⚠️ on a stop or dead end) and the **Next** line with 👉. No other marks in the block.
6. On harnesses without slash commands, write the command as plain phrasing (`run <skill> on <ref>`) instead of `/<skill> <ref>`.
7. When a **Next** condition is a clock time (`after 2026-10-30 15:54 UTC`), not an event (a deploy, a bot posting), ask once after the block whether to schedule it (`AskUserQuestion` where available, otherwise in chat). Where the harness has neither cloud routines nor `CronCreate`, make no offer. On yes, schedule a one-time run at that time: in Claude Code, a cloud routine through the `schedule` skill, with the connectors the checks need attached; failing that, `CronCreate` with `recurring: false`, which fires only while this session stays open, so say so. The prompt is plain text, never the slash command: a scheduled run cannot invoke a user-invoked skill, and a cloud routine starts in a fresh clone with no plugin skills and nobody to approve a step. It carries the whole task: the branch that holds the ticket (push it first; a routine reads only what is pushed), the ticket path, each read-only check with the result to expect, "never run a step marked `(changes data)`; list it for the user", and what to write: tick each item that passed with what was observed, and when every item is ticked, append `## Resolution` and set `status: closed`, committed on a new branch with a PR. Report the routine's link and run time, or the cron job's next run time. On no, the **Next** line stands as printed.
