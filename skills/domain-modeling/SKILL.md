---
name: domain-modeling
description: Build and sharpen a project's domain model — challenge terms against the glossary, resolve fuzzy language, stress-test concepts with concrete scenarios, and record CONTEXT.md entries and ADRs the moment decisions land. Use when pinning down domain terminology or a ubiquitous language, recording an architectural decision, or when another skill (grilling, wayfinder, to-spec) needs the domain model maintained.
---

# Domain Modeling

Actively build and sharpen the project's domain model as you design. This is the *active* discipline — challenging terms, inventing edge-case scenarios, and writing the glossary and decisions down the moment they crystallise. Merely *reading* `CONTEXT.md` for vocabulary is not this skill — that's a one-line habit any skill can do. This skill is for when you're changing the model, not just consuming it.

Runs alongside `grilling` sessions (`grill-with-docs` is the front door that pairs the two), `wayfinder` grilling tickets, and `to-spec` synthesis — anywhere terms get decided. When running inside another skill, don't print an end-of-session block — only the outermost skill does.

## File structure

Most repos have a single context:

```
/
├── CONTEXT.md
├── docs/
│   └── adr/
│       ├── 0001-single-db-multi-tenancy.md
│       └── 0002-money-as-integer-minor-units.md
└── app/
```

If a `CONTEXT-MAP.md` exists at the root, the repo has multiple contexts. The map points to where each one lives — in a Laravel modular monolith that's the module root:

```
/
├── CONTEXT-MAP.md
├── docs/
│   └── adr/                              ← system-wide decisions
└── app/Domain/                           ← or modules/, app-modules/ — follow the repo
    ├── Ordering/
    │   ├── CONTEXT.md
    │   └── docs/adr/                     ← context-specific decisions
    └── Billing/
        ├── CONTEXT.md
        └── docs/adr/
```

Create files lazily — only when you have something to write. No `CONTEXT.md`? Create one when the first term is resolved. No `docs/adr/`? Create it when the first ADR is needed. Formats: [references/context-format.md](references/context-format.md) and [references/adr-format.md](references/adr-format.md).

## During the session

### Challenge against the glossary

When the user uses a term that conflicts with the existing language in `CONTEXT.md`, call it out immediately: "Your glossary defines 'cancellation' as X, but you seem to mean Y — which is it?"

### Sharpen fuzzy language

When the user uses vague or overloaded terms, propose a precise canonical term. Where `AskUserQuestion` is available, put the candidates as options — your recommendation first, each option's description saying what choosing it commits the model to; otherwise ask the same shape in chat. "You're saying 'account' — is that the Customer or the User?" is a click-to-answer decision, not an open-ended essay prompt.

### Discuss concrete scenarios

When domain relationships are being discussed, stress-test them with specific scenarios. Invent scenarios that probe edge cases and force precision about the boundaries between concepts: "A Customer with two Subscriptions cancels one mid-cycle — what happens to the Invoice already issued?"

### Cross-reference with code

When the user states how something works, check whether the code agrees. In a Laravel codebase the model lives in more places than prose — check the glossary term against:

- Eloquent model and relationship names (`app/Models`, `HasMany` method names)
- Table and column names in migrations
- Enum cases (`app/Enums`)
- Policy names and ability strings
- Filament resource/page labels and navigation names
- Route names, job names, event names

If you find a contradiction, surface it: "Your code cancels entire Orders (`Order::cancel()`), but you just said partial cancellation is possible — which is right?" When a term is resolved *against* the code's current naming, the rename is real work — note it as a decision (and a ticket, if a tracker is in play), never silently absorb it.

### Update CONTEXT.md inline

When a term is resolved, update `CONTEXT.md` right there. Don't batch these up — capture them as they happen. Use the format in [references/context-format.md](references/context-format.md).

`CONTEXT.md` must stay totally devoid of implementation details. It is a glossary — not a spec, a scratch pad, or a home for implementation decisions.

### Offer ADRs sparingly

Only offer to create an ADR when all three are true:

1. **Hard to reverse** — the cost of changing your mind later is meaningful
2. **Surprising without context** — a future reader will wonder "why did they do it this way?"
3. **The result of a real trade-off** — there were genuine alternatives and you picked one for specific reasons

If any of the three is missing, skip the ADR. Use the format in [references/adr-format.md](references/adr-format.md).
