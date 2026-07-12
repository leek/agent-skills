---
name: grill-me-plus
description: Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree. Use Claude Code's AskUserQuestion or Codex's request_user_input when available so decisions are click-to-answer. Use when the user says "grill me", wants to stress-test a plan, compare design choices, or resolve ambiguous implementation decisions.
---

# Grill Me Plus

Interview the user relentlessly about every aspect of a plan, design, product idea, implementation approach, or architectural choice until there is shared understanding.

Walk the decision tree one branch at a time. Resolve dependencies between decisions in order. For each question, provide a recommended answer and concrete alternatives with trade-offs.

If a question can be answered by exploring the codebase, files, docs, or current implementation, inspect that context instead of asking.

## Core Loop

1. Identify the next unresolved decision that matters.
2. Check whether existing context already answers it. If yes, record the decision and move on.
3. Ask one focused structured question through the current harness's question tool when available.
4. Lead with the recommended option and explain the trade-off for every option.
5. After the user answers, update the decision ledger and infer any downstream decisions that answer implies.
6. Continue until the plan is resolved, the user stops the grill, or the remaining uncertainty cannot be resolved without external information.

## Decision Ledger

Maintain a running internal ledger:

- `settled`: decisions the user explicitly chose.
- `implied`: decisions that follow from earlier answers.
- `open`: branches still worth asking about.
- `deferred`: questions blocked by missing context, external constraints, or user choice.

Before asking anything, check the ledger. Never re-ask a resolved or implied branch.

## Tool Selection

Use the best structured question tool exposed by the current agent harness:

- **Claude Code:** use `AskUserQuestion`.
- **Codex:** use `request_user_input` when it is listed in the available tools for the current turn.
- **Other agents or missing structured tool:** ask directly in chat, one question at a time, preserving the same recommendation/options/trade-off structure.

Do not print fake tool JSON to the user. Either call the available tool or ask naturally in chat.

## Shared Question Rules

- Ask one decision at a time by default.
- Batch only genuinely independent questions.
- Put the recommended option first and suffix its label with ` (Recommended)`.
- Use concise option labels, ideally 1-5 words.
- Make every option real. No filler choices.
- Do not add an explicit `Other` option when the tool already provides free-form custom answers.
- Use a short header/tag, 12 characters or fewer when the tool supports headers.
- Phrase the question so answering it commits to a concrete decision.
- Explain what each option commits the project to, not just what it is.

## Claude Code: AskUserQuestion

Use `AskUserQuestion` for every question when it is available.

**These questions are always blocking. Do not time out and do not continue without a real user response.** Every `AskUserQuestion` call must wait for the user to actually answer. Never proceed on an assumed answer, a default, or your own best guess when the tool is still waiting. If the user has not responded, stay blocked — do not advance the grill, infer the answer, or move to the next decision until a genuine answer comes back.

Use the tool to its full capability:

- Ask 1 question per call by default.
- Batch up to 4 questions only when the answers are independent.
- Provide 2-4 options per question.
- Use `multiSelect: true` only when options can legitimately stack, such as feature support lists or acceptable constraints. Otherwise leave it false or omit it.
- If the tool supports option `preview`, use it only for useful concrete snippets or examples. Never pass `null`; omit `preview` entirely when there is no meaningful preview.
- Keep `header` short: `Auth`, `DB`, `Scope`, `UI`, `Risk`, `API`, `Ship`.

Example shape:

```json
{
  "questions": [
    {
      "header": "Auth",
      "question": "Which authentication direction should this plan assume?",
      "multiSelect": false,
      "options": [
        {
          "label": "OIDC (Recommended)",
          "description": "Uses the existing identity provider and keeps authorization centralized."
        },
        {
          "label": "Email magic",
          "description": "Simpler for users, but adds email delivery dependency and weaker enterprise fit."
        },
        {
          "label": "Password login",
          "description": "Familiar and self-contained, but adds password storage and recovery surface area."
        }
      ]
    }
  ]
}
```

## Codex: request_user_input

Use `request_user_input` whenever it is listed in Codex's available tools for the current turn. If it is not available, ask in chat.

Codex has a stricter shape than Claude Code:

- Ask 1 question per call by default.
- Ask at most 3 questions per call.
- Provide exactly 2-3 mutually exclusive options per question.
- Include a stable `id` in `snake_case`.
- Include a `header` of 12 characters or fewer.
- Include a single-sentence `question`.
- Each option must have a short `label` and one-sentence `description`.
- Put the recommended option first and suffix its label with ` (Recommended)`.
- Do not include `Other`; the client adds free-form Other automatically.
- Omit `autoResolutionMs` for grill-me decisions because these questions are usually blocking.
- Use `autoResolutionMs` only when the question is useful but non-blocking and the grill can continue with best judgment if the user does not answer.

Example shape:

```json
{
  "questions": [
    {
      "header": "Data",
      "id": "data_source",
      "question": "Which data source should this design optimize around first?",
      "options": [
        {
          "label": "Primary DB (Recommended)",
          "description": "Keeps the first version aligned with current writes and avoids introducing sync state."
        },
        {
          "label": "Search index",
          "description": "Improves query flexibility, but makes freshness and rebuild behavior first-order concerns."
        },
        {
          "label": "Event stream",
          "description": "Fits audit-heavy workflows, but increases operational complexity before the base flow is proven."
        }
      ]
    }
  ]
}
```

Because Codex options are mutually exclusive and capped at 3, convert multi-select topics into either a smaller mutually exclusive choice or a follow-up sequence.

## Chat Fallback

When no structured tool is available, ask directly:

```text
Auth: Which authentication direction should this plan assume?

1. OIDC (Recommended) - Uses the existing identity provider and keeps authorization centralized.
2. Email magic - Simpler for users, but adds email delivery dependency and weaker enterprise fit.
3. Password login - Familiar and self-contained, but adds password storage and recovery surface area.
```

Then wait for the answer before continuing.

## Stop Conditions

Stop when:

- The user says to stop.
- The plan is sufficiently resolved to act.
- Remaining branches depend on information outside the current context.
- The user asks for a summary, PRD, implementation plan, or next-step artifact.

End with a compact summary of settled decisions, unresolved risks, and the recommended next action. When the plan is resolved and the user wants a durable artifact, suggest `to-spec-plus` (spec/PRD) or `to-tickets-plus` (implementation tickets); for efforts too big for one session, suggest charting a `wayfinder-plus` map.
