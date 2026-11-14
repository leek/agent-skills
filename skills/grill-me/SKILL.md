---
name: grill-me
description: "Run a grilling session: the user wants their plan, decision, or idea stress-tested one question at a time."
disable-model-invocation: true
argument-hint: "The plan, decision, or idea to stress-test"
---

# Grill Me

Run a `grilling` session on whatever the user brought.

**Invoked on a spec**, every line under its `## Open questions` starts in the ledger as `open`: the board sends the user here because that section is not empty, and sends them back until it is. Each line ends the grill settled (asked, or taken off the ladder as a default) or `deferred` with the reason. A line that is not a question (a fact taken as given, a risk the user accepted) is recorded as a default, so `to-spec` moves it out of the section.

## When you're done

Print the end-of-session block using the frame in [`wayfinder/references/pipeline-end-block.md`](../wayfinder/references/pipeline-end-block.md): whether the plan resolved, the user stopped the grill, or a branch dead-ended.

```text
---
Pipeline: **decide** → spec → tickets → build   (1 of 4)
Done: <n of m decisions settled; what's still open>
Open: <each open or deferred branch and unresolved risk (the grill's decision record)>
Next:
  • <condition> → /<skill> <ref>
```

Stage-specific **Next** conditions (only those that apply, most likely first):

- **Plan resolved, spans several tickets** → `/to-spec` to record it
- **Plan resolved, fits one session** → `/to-tickets`, or `/implement` if it's genuinely one ticket (say "in a worktree, open a PR" to get its branch and PR delivery)
- **Resolved but too big for one spec, or still foggy** → `/wayfinder` to chart it as a map
- **A branch is blocked on knowledge someone else holds** → `/to-questionnaire` on that branch
- **A branch is blocked on a fact worth reading for** → `/research` on that question
- **Stopped early** → `/grill-me` to resume; list the open branches by name so the next session starts on the frontier
