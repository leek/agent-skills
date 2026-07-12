---
name: to-spec-plus
description: Turn the current conversation into a spec (PRD) and publish it to the project's issue tracker — no interview, just synthesis of what was already discussed, with Laravel test seams confirmed via AskUserQuestion before writing. Use when the user says "to spec", "write this up as a spec/PRD", or a grilling session is done and needs a durable artifact.
---

# To Spec Plus

Take the current conversation context and codebase understanding and produce a spec (a PRD). Do **not** interview the user — the interview already happened (usually a `grill-me-plus` session); this skill synthesizes it.

If a load-bearing decision is genuinely unresolved — one the spec cannot be written without — don't guess and don't launch a full interview. Ask just that decision through `AskUserQuestion` (recommended option first, trade-offs per option), or suggest a `grill-me-plus` round if several are open.

Pipeline position: `grill-me-plus`/`wayfinder-plus` (decide) → **`to-spec-plus`** (record) → `to-tickets-plus` (slice) → `implement-plus` (build).

## Process

### 1. Explore the repo

Understand the current state of the codebase if you haven't already. Use the project's domain vocabulary throughout the spec (read `CONTEXT.md` if one exists — `domain-modeling-plus` maintains it) and respect any ADRs in the area being touched.

### 2. Sketch the test seams

A **seam** is the public boundary the feature will be tested at (`codebase-design-plus` holds the full deep-module vocabulary). Prefer existing seams to new ones, and the highest seam possible — the fewer seams across the codebase, the better; the ideal number is one.

The Laravel seam ladder, highest first:

1. **HTTP boundary** — a feature test hitting the route (`get()`/`post()` + `assertDatabaseHas`/response assertions). The default for anything with an endpoint.
2. **Livewire / Filament component** — `Livewire::test()` or Filament's testing helpers, when the behavior lives in a component rather than a plain endpoint.
3. **Console command** — `$this->artisan()` with exit code and side-effect assertions.
4. **Queued job / listener** — dispatch or `handle()` directly, asserting side effects.
5. **Action / service class** — direct test at the class's public API, for logic shared by several entry points.
6. **Model** — only for non-trivial scopes, casts, or derived attributes.

Then **confirm the seams with the user via `AskUserQuestion`** before writing the spec — proposed seam set as the recommended option, one-step-higher and one-step-lower alternatives with their trade-offs (higher = fewer, more integrated tests; lower = faster, more coupled).

### 3. Write and publish the spec

Write the spec using the template below. Show the draft, then publish it to the project's issue tracker with the `ready-for-agent` label (creating an issue is an external action — publish only after the user has seen the draft).

Tracker fast path: follow `docs/agents/issue-tracker.md` if present, else an `## Issue tracker` section in `AGENTS.md`/`CLAUDE.md`, else detect (Linear MCP → Linear; GitHub remote + `gh` → GitHub Issues; neither → a markdown file under `.scratch/<feature-slug>/spec.md`) and confirm once with `AskUserQuestion`, offering to persist the choice to `docs/agents/issue-tracker.md`.

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

- The agreed seams (from step 2) and which behaviors each covers
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

## After publishing

Point the user at `to-tickets-plus` to break the spec into tracer-bullet tickets, or `implement-plus` directly if the work fits one session.
