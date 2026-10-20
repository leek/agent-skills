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
3. List only **Next** conditions that actually apply, most likely first. A condition applies while its trigger is still open. A finished effort, a closed map, and a choice the user already made (build on the current branch and commit there) add no extra Next line: the Next line is that settled action, or the block has no Next line when nothing remains.
4. Prefix the **Done** line with ✅ (⚠️ on a stop or dead end) and the **Next** line with 👉. No other marks in the block.
5. On harnesses without slash commands, write the command as plain phrasing (`run <skill> on <ref>`) instead of `/<skill> <ref>`.
