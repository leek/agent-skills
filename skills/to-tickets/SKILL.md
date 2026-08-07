---
name: to-tickets
description: Break a plan, spec, or the current conversation into tracer-bullet vertical-slice tickets with explicit blocking edges, take one green light on the breakdown, and publish to the project's issue tracker.
disable-model-invocation: true
---

# To Tickets

Break a plan, spec, or conversation into **tickets** — tracer-bullet vertical slices, each declaring the tickets that **block** it.

Pipeline position: `to-spec` (record) → **`to-tickets`** (slice) → `implement` (build one ticket per session).

## Process

### 1. Gather context

Work from whatever is already in the conversation. If the user passes a reference (a spec path, an issue id or URL), fetch it and read its full body and comments.

### 2. Explore the codebase when applicable

When the work targets an existing codebase and you haven't already explored it, inspect the current state. Ticket titles and descriptions use the project's domain vocabulary (`CONTEXT.md`/glossary if present) and respect ADRs in the area. For greenfield or non-code work, continue from the gathered context.

Look for opportunities to **prefactor** — restructure first so the feature lands cleanly. "Make the change easy, then make the easy change." Prefactors become the first tickets.

### 3. Draft vertical slices

Break the work into **tracer bullet** tickets:

- Each slice cuts a narrow but COMPLETE path through every layer it needs — for a typical Laravel feature: migration → model/factory → behavior (controller / FormRequest / action / job / Livewire / Filament) → route → feature test. Vertical, never a horizontal slice of one layer ("all migrations", "all the tests").
- A completed slice is demoable or verifiable on its own — a route you can hit, a command you can run, a test you can watch pass.
- Each slice is sized to fit one fresh agent session.
- Prefactoring tickets come first.

Give each ticket its **blocking edges** — the tickets that must complete before it can start. A ticket with no blockers can start immediately.

**Wide refactors are the exception to vertical slicing.** A wide refactor is one mechanical change — rename a column, retype a shared value object — whose blast radius fans across the codebase so no vertical slice can land green. Sequence it as **expand–contract**:

1. **Expand** — add the new form beside the old so nothing breaks (new nullable column + dual-write; new method delegating to old).
2. **Migrate** — move call sites/data over in batches sized by blast radius (per module, per directory), each batch its own ticket blocked by the expand. A data backfill is its own ticket — a one-time operation leaving no permanent infra.
3. **Contract** — drop the old form once no caller remains, in a ticket blocked by *every* migrate batch. The contract migration is the only destructive step and lands last.

When even batches can't stay green alone, keep the sequence but share an integration branch, all blocking a final integrate-and-verify ticket — green is promised only there.

### 4. Green-light publication

**Granularity, blocking edges, and slicing axis are yours to settle.** Step 3's rules decide them, so don't run a review round on each — `grilling`'s **What still earns a question** keeps mechanical judgment off the user's plate.

Present the finished breakdown as a numbered list — per ticket: **Title**, **Blocked by**, **What it delivers** (the end-to-end behavior it makes work).

Then ask **exactly one** question, because step 5 creates issues on a shared tracker and that isn't cheap to undo: publish as listed (recommended) / adjust first, say what. Make whatever the user names, reprint the list, and don't reopen the parts they left alone.

### 5. Publish

Publishing creates external artifacts — do it only after step 4's green light.

Resolve the tracker through `docs/agents/issue-tracker.md` (written by `/setup`) or an `## Issue tracker` section in `CLAUDE.md`/`AGENTS.md`. Follow that configuration for creation, parent links, blocking relations, and labels; it is the single source of truth for tracker mechanics. When neither exists, default to one local markdown file per ticket under `.scratch/<feature-slug>/issues/` and suggest running `/setup` once to make the choice durable.

Publish in dependency order — **blockers first** — so each ticket's edges reference real identifiers. Publish idempotently: if a run fails mid-loop, re-read existing issues before creating more.

Do NOT close or modify any parent issue.

## Ticket template

The local template below is canonical. For a tracker issue, put the title and AFK-ready state in native fields and use the body from `## Parent` onward, replacing file references with issue identifiers.

```markdown
# <NN> — <Ticket title>

**Status:** ready-for-agent

## Parent

Relative path to the spec (`../spec.md`), or omit if none.

## What to build

The end-to-end behaviour this ticket makes work, from the user's perspective —
not a layer-by-layer implementation list.

## Acceptance criteria

- [ ] Behavior statements — what a user/caller can now do, what data is
      persisted, what is forbidden (authorization) — never presentation
      ("page shows heading X") or implementation ("uses a repository")

## Blocked by

- <NN>-<slug>.md per blocker, or "None — can start immediately".
```

Files are numbered from `01` in topological order: every blocker has a lower number than the ticket it blocks. Numbers order dependencies; they do not serialize independent tickets.

In either form, avoid file paths and code snippets — they go stale fast. Exception: a prototype-derived snippet that encodes a decision more precisely than prose (state machine, schema, enum shape); trim to the decision-rich parts.

## After publishing

Work the **frontier** — any ticket whose blockers are all done — with `implement`, one ticket per fresh session. Unblocked, unclaimed tickets can run in parallel on every tracker, including local markdown. `implement` claims each ticket before building (assignment on a tracker, `**Status:** in-progress (claimed <date>, <who>)` in a local file), so an accidental second session skips work already in progress instead of colliding with it.

## When you're done

End the session by printing the block below — on a clean finish, a stop, or a dead end. On harnesses without slash commands, write the command as plain phrasing (`run implement on <ref>`) instead of `/implement <ref>`.

```text
---
Pipeline: decide → spec → **slice** → build   (3 of 4)
Done: <how many tickets, how many on the frontier, with refs>
Next:
  • <condition> → /<skill> <ref>
```

List only the conditions that actually apply, most likely first:

- **Tickets published with a frontier** → `/implement <frontier ticket>` in one fresh session per ticket; parallelize only independent frontier tickets
- **Every ticket is blocked by something already open on the tracker** → `/implement <that blocker>` first; name it
- **A ticket turned out to be a decision, not a build** → `/grill-me` on it (or `/wayfinder` if there are several)
- **Slicing exposed a gap the spec never settled** → `/grill-me` on the gap, then re-run `/to-spec`
- **Stopped before publishing** → say which tickets exist, which are drafted only, and which blocking edges are unwired
