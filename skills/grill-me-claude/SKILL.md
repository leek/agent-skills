---
name: grill-me-claude
description: Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree — asking via the AskUserQuestion tool so every question is click-to-answer. Use when user wants to stress-test a plan, get grilled on their design, or mentions "grill me".
---

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

If a question can be answered by exploring the codebase, explore the codebase instead of asking.

## Ask through the AskUserQuestion tool

Pose every question with the `AskUserQuestion` tool instead of as plain prose, so each one is click-to-answer.

- **One decision at a time.** Default to a single question per call so each answer can steer the next branch. Only batch into one call (max 4 questions) when the questions are genuinely independent of one another.
- **Lead with your recommendation.** Make your recommended answer the first option and append " (Recommended)" to its label. The whole point of this exercise is that you have an opinion — state it.
- **2–4 real options.** Give every option a concise `label` (1–5 words) and a `description` that explains the trade-off or what choosing it commits us to. No filler options.
- **`header` ≤ 12 chars.** A short tag for the decision, e.g. "Auth", "DB engine", "Caching".
- **"Other" is automatic.** The user can always type a custom answer, so never add your own "Other"/"Something else" option. Don't force their intent into your list — if the real answer is likely off-list, keep the options honest and let them say so.
- **`multiSelect` only when choices stack.** Set `multiSelect: true` when more than one option can legitimately be chosen together (e.g. "which of these should we support?"); otherwise leave it false.

Keep going branch by branch until the plan is fully resolved.
