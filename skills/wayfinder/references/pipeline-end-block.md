# Pipeline end-of-session block

**Single source of truth** for the banner format printed by pipeline skills (`grill-me`, `wayfinder`, `to-spec`, `to-tickets`, `implement`, `implement-spec`, and standalone `code-review` / `to-questionnaire`). Owned by `wayfinder` as the pipeline base. Stage skills keep their own **Done** placeholders, **Open** sources, and **Next** condition lists; they only restyle the frame here.

## When to print

Print on a clean finish, a stop, or a dead end: unless the skill says an inner invocation must stay silent (only the outermost skill prints).

## Frame

```text
---
Pipeline: <stage highlight on the decide → spec → tickets → build line>   (<n of 4 or role note>)
Done: <stage-specific summary>
Open:
  • <what is open, in plain words> (<where it is tracked>)
Next:
  • <condition> → /<skill> <ref>
```

Rules:

1. Bold the current pipeline stage on the `decide → spec → tickets → build` line (or note a supporting role, e.g. review runs inside build).
2. Fill **Done** from live state: never guess at frontiers; run the tracker's Frontier operation (`ticket.sh frontier <slug>`, for its `frontier`, `next`, and `counts`) when the skill owns one. Count a built item done only when you observed its result in the output (the rendered page, the response, a passing test that asserts it); an item edited but not observed is listed as unchecked. A text change is observed by searching the built output for the old wording too. While **Open** has an entry, Done names what is done and never calls the whole effort done.
3. List only **Next** conditions that actually apply, most likely first. A condition applies while its trigger is still open, so a finished effort or a closed map adds none. When the user already made the choice (build on the current branch and commit there), the only Next line is that action, with no alternatives beside it. When nothing remains, leave out the Next line.
4. Never tell the user to `/clear`, compact, or start a fresh session, in **Next** or anywhere in the block. Each **Next** line is the command alone; when and whether to clear is the user's call.
5. Prefix the **Done** line with ✅ (⚠️ on a stop or dead end), the **Open** line with ⚠️, and the **Next** line with 👉. No other marks in the block.
6. On harnesses without slash commands, write the command as plain phrasing (`run <skill> on <ref>`) instead of `/<skill> <ref>`.
7. When a **Next** condition is a clock time (`after 2026-10-30 15:54 UTC`), not an event (a deploy, a bot posting), ask once after the block whether to schedule it (a structured question ([harness-tools](../../harness-tools/SKILL.md)), otherwise in chat). Where the harness has neither cloud routines nor `CronCreate`, make no offer. On yes, schedule a one-time run at that time: in Claude Code, a cloud routine through the `schedule` skill, with the connectors the checks need attached; failing that, `CronCreate` with `recurring: false`, which fires only while this session stays open, so say so. The prompt is plain text, never the slash command: a scheduled run cannot invoke a user-invoked skill, and a cloud routine starts in a fresh clone with no plugin skills and nobody to approve a step. It carries the whole task: the branch that holds the ticket (push it first; a routine reads only what is pushed), the ticket path, each read-only check with the result to expect, "never run a step marked `(changes data)`; list it for the user", and what to write: tick each item that passed with what was observed, and when every item is ticked, append `## Resolution` and set `status: closed`, committed on a new branch with a PR. Report the routine's link and run time, or the cron job's next run time. On no, the **Next** line stands as printed.
8. Print **Open** whenever anything is open when the skill stops, and leave the line out only when nothing is: an open ticket or decision, a finding or a verification left undone, a fix not yet pushed, a question that waits on the user, work the user asked for in chat. One short entry per item, with the place it is tracked (a ticket path, a decision record, a pull request); tickets of one effort may share an entry that gives their count and directory. An item with no tracking place gets one before the block prints: record it as a ticket, or as a decision record per `grilling`'s [Record the ledger](../../grilling/SKILL.md#record-the-ledger), and name that path. Only where the repo has no tracker to hold it does the entry say `untracked`, written out.
