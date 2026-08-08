---
name: grill-me
description: Run a grilling session — the user wants their plan, decision, or idea stress-tested one question at a time.
disable-model-invocation: true
---

# Grill Me

Run a `grilling` session on whatever the user brought.

## When you're done

End the session by printing the block below — whether the plan resolved, the user stopped the grill, or a branch dead-ended.

```text
---
Pipeline: epic → feature → story → build   (grilling settles decisions at every level)
Done: <n of m decisions settled; what's still open>
Next:
  • <condition> → /<skill> <ref>
```

List only the conditions that actually apply, most likely first:

- **Plan resolved, spans several stories** → `/to-spec` to record it as one feature
- **Plan resolved, fits one session** → `/to-tickets`, or `/implement` if it's genuinely one story
- **Resolved but bigger than one feature, or still foggy** → `/wayfinder` to chart it as an epic
- **A branch is blocked on knowledge someone else holds** → `/to-questionnaire` on that branch
- **A branch is blocked on a fact worth reading for** → `/research` on that question
- **Stopped early** → `/grill-me` to resume; list the open branches by name so the next session starts on the frontier
