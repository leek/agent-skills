# Pipeline end-of-session block

**Single source of truth** for the banner format printed by pipeline skills (`grill-me`, `wayfinder`, `to-spec`, `to-tickets`, `implement`, and standalone `code-review` / `to-questionnaire`). Stage skills keep their own **Done** placeholders and **Next** condition lists; they only restyle the frame here.

## When to print

Print on a clean finish, a stop, or a dead end — unless the skill says an inner invocation must stay silent (only the outermost skill prints).

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
2. Fill **Done** from live state — never guess at frontiers; query the markdown tracker when the skill owns one.
3. List only **Next** conditions that actually apply, most likely first.
4. On harnesses without slash commands, write the command as plain phrasing (`run <skill> on <ref>`) instead of `/<skill> <ref>`.
