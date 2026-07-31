---
name: handoff
description: Compact the current conversation into a handoff document for another agent to pick up.
argument-hint: "What will the next session be used for?"
disable-model-invocation: true
---

Write a handoff document summarising the current conversation so a fresh agent can continue the work. Save to the temporary directory of the user's OS - not the current workspace.

Include a "suggested skills" section in the document, which suggests skills that the agent should invoke. Name them exactly as this collection names them — e.g. `wayfinder`, `grill-me`, `to-spec`, `to-tickets`, `implement`, `tdd`, `verify`, `code-review`, `diagnosing-bugs`, `triage`, `prototype`, `research`, `codebase-design`, `domain-modeling` — so the next agent can invoke them directly.

Do not duplicate content already captured in other artifacts (specs, plans, ADRs, issues, commits, diffs). Reference them by path or URL instead.

Redact any sensitive information, such as API keys, passwords, or personally identifiable information.

If the user passed arguments, treat them as a description of what the next session will focus on and tailor the doc accordingly.
