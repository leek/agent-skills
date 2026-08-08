---
name: to-spec
description: Turn the current conversation into a spec (PRD) for one feature and publish it to the project's issue tracker — no interview, just synthesis, with Laravel test seams chosen from the tdd ranking rules rather than asked about.
disable-model-invocation: true
---

# To Spec

Take the current conversation context and codebase understanding and produce a spec (a PRD). Do **not** interview the user — the interview already happened (usually a `grilling` session); this skill synthesizes it.

If a load-bearing decision is genuinely unresolved — one the spec cannot be written without — don't guess and don't launch a full interview. Ask just that decision (via `AskUserQuestion` where available, otherwise a plain question in chat — recommended option first, trade-offs per option), or suggest a `grill-me` round if several are open.

A spec is one **feature**: the unit between an epic and its stories. An epic (a `wayfinder` map) hands off one feature or many, each in its own session; small work has no epic and starts here.

Pipeline position: `wayfinder` charts the **epic** → **`to-spec`** writes each **feature** → `to-tickets` cuts its **stories** → `implement` builds one story per session.

## Process

### 1. Explore the repo

Understand the current state of the codebase if you haven't already. Use the project's domain vocabulary throughout the spec (read `CONTEXT.md` if one exists — `domain-modeling` maintains it) and respect any ADRs in the area being touched.

Finish exploring only when you can name the domain terms and ADRs that constrain the spec, the closest existing implementation and tests to imitate (or confirm none exist), and the tracker destination step 3 will use.

### 2. Sketch the test seams

A **seam** is the public boundary the feature will be tested at (`codebase-design` holds the full deep-module vocabulary). Before proposing seams, consult and apply the Laravel ranking and selection rules in the `tdd` skill's **Seams — where tests go** section; it is the single source of truth. While sketching seams, look for a **deepening opportunity** — functionality worth hiding behind a smaller, more stable interface — and record it under Implementation Decisions.

**Decide the seams yourself — don't ask.** Seam placement is test structure, which `grilling`'s **What still earns a question** hands to you: the ranking rules settle it, so apply them and move on. Record the chosen set in the spec with a one-line why per seam; the user reviews them as part of the step 3 draft, which is the only gate this step needs. Ask only on a genuine fork — two placements the rules rank equally that would make materially different work — and then ask just that one.

### 3. Write and publish the spec

Write the spec using the template below. Show the complete draft and wait for the user to approve publication or request changes. After approval, publish it to the project's issue tracker with the repo's AFK-ready label (`ready-for-agent` unless `docs/agents/triage-labels.md` maps it differently; create the label if it doesn't exist).

Resolve the tracker through `docs/agents/issue-tracker.md` (written by `/setup`) or an `## Issue tracker` section in `CLAUDE.md`/`AGENTS.md`. When neither exists, default to **local markdown** and suggest running `/setup` once to make the choice durable.

**Where it goes depends on whether an epic sent you.** Cover exactly one feature either way — if the draft grew to cover two, publish the first and say the second needs its own session.

- **Invoked with a map** — publish inside the epic, as its next feature: `.scratch/<epic-slug>/specs/<NN>-<feature-slug>/spec.md`, numbered from `01` in handoff order. Then append one line to the map's **Handed off** section through the tracker's Hand off operation, and leave the map open — an epic closes only after its last feature.
- **Invoked without a map** — publish standalone at `.scratch/<feature-slug>/spec.md`.

## Spec template

```markdown
## Problem Statement

The problem the user is facing, from the user's perspective.

## Solution

The solution to the problem, from the user's perspective.

## User Stories

A LONG, numbered list covering all aspects of the feature:

1. As an <actor>, I want <a feature>, so that <benefit>

## Implementation Decisions

The decisions that were made, e.g.:

- Schema changes (expand–contract sequencing for live tables)
- Eloquent models and relationships to add or modify
- Validation (FormRequest rules) and authorization (policies, record-level scoping)
- Events, listeners, jobs, notifications
- API contracts (routes, resources, payload shapes)
- Filament resources/pages or Livewire components affected
- Config/env keys, feature flags
- Architectural decisions and their reasoning

Do NOT include specific file paths or code snippets — they go stale fast.
Exception: a prototype-derived snippet that encodes a decision more precisely
than prose (state machine, schema, enum, type shape) — inline it, note it came
from a prototype, trim to the decision-rich parts.

## Testing Decisions

- The chosen seams (from step 2) and which behaviors each covers
- Prior art — similar tests already in the codebase to imitate
- Ground rules: test behavior through public interfaces, never presentation
  (no assertions on copy, layout, or CSS); don't test framework behavior;
  do test business rules, validation, persisted data, record-level
  authorization, and side effects (via Queue/Mail/Storage/Event fakes)

## Out of Scope

What this spec deliberately excludes.

## Further Notes

Anything else future readers need.
```

## When you're done

End the session by printing the block below — on a clean finish, a stop, or a dead end. On harnesses without slash commands, write the command as plain phrasing (`run to-tickets on <ref>`) instead of `/to-tickets <ref>`.

```text
---
Pipeline: epic → **feature** → story → build   (one feature, many stories)
Done: <what exists now, with its reference; the epic it belongs to, if any>
Next:
  • <condition> → /<skill> <ref>
```

List only the conditions that actually apply, most likely first:

- **Feature published, work spans several stories** → `/to-tickets <spec ref>`
- **Feature published, work fits one session** → `/implement <spec ref>`
- **Published under an epic that still has open decisions** → `/wayfinder <map>` for its next frontier ticket; say how many remain
- **A load-bearing decision is still open** → `/grill-me` on that decision, naming it; re-run `/to-spec` after
- **Several decisions open, or the work is bigger than one feature** → `/wayfinder` to chart it as an epic first
- **Blocked on knowledge someone else holds** → `/to-questionnaire`; **on a fact worth reading for** → `/research`
- **Stopped before publishing** → say what the draft covers, where it lives, and which sections are unwritten
