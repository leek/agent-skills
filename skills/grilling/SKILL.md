---
name: grilling
description: Interview the user one decision at a time until reaching shared understanding, resolving each branch of the decision tree with recommended options and trade-offs. Use when a plan, design, or idea needs its soft spots found and forced into the open, or when another skill needs the interview protocol.
---

# Grilling

Interview the user relentlessly about every aspect of a plan, design, product idea, implementation approach, or architectural choice until there is shared understanding. **Do not act on the plan until the user confirms shared understanding has been reached.**

Walk the decision tree one branch at a time. Resolve dependencies between decisions in order. The **frontier** is every open decision whose prerequisites are already settled — the questions that can be asked now without guessing at answers not yet given. For each question, provide a recommended answer and concrete alternatives with trade-offs.

Finding facts is never the user's job. If a question can be answered by exploring the environment — codebase, files, docs, tools, or current implementation — inspect that context instead of asking. When a fact needs real reading, resolve it through the `research` skill's dispatch rules (its sub-agent must complete inside this session), mark the branch deferred, and keep interviewing the rest of the frontier.

## Core Loop

1. Identify the next unresolved decision that matters.
2. Check whether existing context already answers it. If yes, record the decision and move on.
3. Ask **exactly one question at a time**. Asking multiple questions at once is bewildering.
4. Lead with the recommended option and explain the trade-off for every option.
5. After the user answers, update the decision ledger and infer any downstream decisions that answer implies.
6. Continue until the plan is resolved, the user stops the grill, or the remaining uncertainty cannot be resolved without external information.

## Decision Ledger

Maintain a running internal ledger:

- `settled`: decisions the user explicitly chose.
- `implied`: decisions that follow from earlier answers.
- `open`: branches still worth asking about.
- `deferred`: questions blocked by missing context, a pending fact lookup, external constraints, or user choice.

Before asking anything, check the ledger. Never re-ask a resolved or implied branch. When a deferred fact resolves, move its downstream branches back to `open`.

## Asking the question

Where `AskUserQuestion` is available, use it — decisions become click-to-answer:

- One question per call.
- 2–4 options, every one real — no filler choices, no explicit `Other` (the tool provides free-form input).
- Recommended option first, label suffixed ` (Recommended)`, labels 1–5 words, `header` ≤ 12 characters.
- Describe what each option commits the project to, not just what it is.
- `multiSelect: true` only when options legitimately stack.

Without the tool, ask the same shape in chat — numbered options, recommendation first, trade-off per line — and wait for the answer. Never print fake tool JSON.

## Stop Conditions

Stop when:

- The user says to stop.
- The user confirms shared understanding — the only exit that permits acting on the plan.
- Remaining branches depend on information outside the current context.

A request for a summary, PRD, or implementation plan is a request to *record* the settled decisions, not permission to resolve open branches by yourself.

Before ending, settle or explicitly abandon every `deferred` branch — no fact lookup may still be running, and no task ID belongs in any summary or hand-off text (a task handle dies with the session).

End with a compact summary of settled decisions and unresolved risks. When invoked directly (not from another skill), also print the routing block from `grill-me` — only the outermost skill prints one.
