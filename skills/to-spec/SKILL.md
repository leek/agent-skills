---
name: to-spec
description: Turn the current conversation into a spec (PRD) and save it as markdown under .scratch/ — no interview, just synthesis, with Laravel test seams chosen from the tdd ranking rules rather than asked about.
disable-model-invocation: true
---

# To Spec

Take the current conversation context and codebase understanding and produce a spec (a PRD). Do **not** interview the user — the interview already happened (usually a `grilling` session); this skill synthesizes it.

If a load-bearing decision is genuinely unresolved — one the spec cannot be written without — don't guess and don't launch a full interview. Ask just that decision (via `AskUserQuestion` where available, otherwise a plain question in chat — recommended option first, trade-offs per option), or suggest a `grill-me` round if several are open.

**Written once per effort, revised in place after.** One spec covering everything the effort builds, written in a single session. If it came from a `wayfinder` map, that first write closes the map and does not run on it again. Later, if downstream work exposes a wrong or missing decision, re-run to **edit this spec in place** — never write a second spec beside it, and never reopen or re-close the map.

Pipeline position: `grill-with-docs`/`wayfinder` (decide) → **`to-spec`** (write the spec) → `to-tickets` (break it into tickets) → `implement` (build one ticket per session).

## Process

### 1. Explore the repo

Understand the current state of the codebase if you haven't already. Use the project's domain vocabulary throughout the spec (read `CONTEXT.md` if one exists — `domain-modeling` maintains it) and respect any ADRs in the area being touched.

**Invoked with a `wayfinder` map, read the map and every closed decision ticket's `## Resolution` first** — those resolutions are the authoritative decisions the spec must encode. Don't synthesize from conversation memory alone; a fresh session may not hold what earlier ticket sessions decided.

Finish exploring only when you can name the domain terms and ADRs that constrain the spec, the closest existing implementation and tests to imitate (or confirm none exist), and the tracker destination step 3 will use.

### 2. Sketch the test seams

A **seam** is the public boundary the feature will be tested at (`codebase-design` holds the full deep-module vocabulary). Before proposing seams, consult and apply the Laravel ranking and selection rules in the `tdd` skill's **Seams — where tests go** section; it is the single source of truth. While sketching seams, look for a **deepening opportunity** — functionality worth hiding behind a smaller, more stable interface — and record it under Implementation Decisions.

**Decide the seams yourself — don't ask.** Seam placement is test structure, which `grilling`'s **What still earns a question** hands to you: the ranking rules settle it, so apply them and move on. Record the chosen set in the spec with a one-line why per seam; the user reviews them as part of the step 3 draft, which is the only gate this step needs. Ask only on a genuine fork — two placements the rules rank equally that would make materially different work — and then ask just that one.

### 3. Write and publish the spec

Write the spec using the template below. Show the complete draft and wait for the user to approve publication or request changes.

A spec is a markdown file under `.scratch/` — there is no external tracker. Read the layout from `.agents/issue-tracker.md` (written by `/setup`). If it's missing, try `docs/agents/issue-tracker.md` (legacy), then the path below; suggest running `/setup` once to make it durable.

After approval, publish to `.scratch/<slug>/spec.md` with `status: ready-for-agent` in its YAML frontmatter (or the AFK-ready role string from `.agents/triage-labels.md` when that mapping differs). **Invoked with a map, reuse that map's directory** and set `map.md`'s frontmatter to `status: closed` — the map's job is done. A later in-place revision leaves the map closed.

The spec covers the whole effort. Its short **Build Contract** is the canonical home for invariants, ordering, and shared seams every implementation ticket needs; detailed decisions below it hold ticket-specific context without repeating that contract. If the effort feels too big for one spec, say so and recommend narrowing it rather than writing a second spec beside the first.

## Spec template

```markdown
## Problem Statement

The problem the user is facing, from the user's perspective.

## Solution

The solution to the problem, from the user's perspective.

## Build Contract

- The cross-ticket invariants every implementation must preserve
- Delivery or expand–contract ordering that constrains more than one ticket
- Shared public seams later tickets can rely on
- Links to named sections below that workers should load only when their ticket reaches them

## User Stories

A LONG, numbered list covering all aspects of the feature:

1. As an <actor>, I want <a feature>, so that <benefit>

## Implementation Decisions

The detailed decisions that were made. Keep Build Contract material in that section only; link to it instead of repeating it here. Examples:

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

Print the end-of-session block using the frame in [`wayfinder/references/pipeline-end-block.md`](../wayfinder/references/pipeline-end-block.md).

```text
---
Pipeline: decide → **spec** → tickets → build   (2 of 4)
Done: <what exists now, with its reference; whether a map was closed>
Next:
  • <condition> → /<skill> <ref>
```

Stage-specific **Next** conditions (only those that apply, most likely first):

- **Spec published, work spans several tickets** → `/to-tickets <spec ref>`
- **Spec published, work fits one session** → `/implement <spec ref>`
- **A load-bearing decision is still open** → `/grill-me` on that decision, naming it; re-run `/to-spec` after
- **Several decisions open, or the effort is bigger than one spec** → `/wayfinder` to chart it first, on a narrower destination
- **Blocked on knowledge someone else holds** → `/to-questionnaire`; **on a fact worth reading for** → `/research`
- **Stopped before publishing** → say what the draft covers, where it lives, and which sections are unwritten
