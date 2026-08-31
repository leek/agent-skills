---
name: to-tickets
description: Break a spec into tracer-bullet vertical-slice tickets with explicit blocking edges, take one green light on the breakdown, and save one markdown file per ticket beside the spec.
disable-model-invocation: true
---

# To Tickets

Break one spec into **tickets**: tracer-bullet vertical slices, each declaring the tickets that **block** it. A ticket is one session of build work, and it is the smallest unit the pipeline tracks.

Pipeline position: `wayfinder` (decide) → `to-spec` (write the spec) → **`to-tickets`** (break it into tickets) → `implement` (build one ticket per session).

## Process

### 1. Gather context

Work from whatever is already in the conversation. If the user passes a reference (a spec path, or a `wayfinder` **map** when the effort skips the spec) fetch it and read its full body and comments. On a map, the source is the map plus every closed decision ticket's `## Resolution`.

### 2. Explore the codebase when applicable

When the work targets an existing codebase and you haven't already explored it, inspect the current state. Ticket titles and descriptions use the project's domain vocabulary (`CONTEXT.md`/glossary if present) and respect ADRs in the area. For greenfield or non-code work, continue from the gathered context.

Look for opportunities to **prefactor**: restructure first so the feature lands cleanly. "Make the change easy, then make the easy change." Prefactors become the first tickets.

### 3. Draft the tickets

Cut the spec into **tracer bullet** tickets:

- Each ticket cuts a narrow but COMPLETE path through every layer it needs: for a typical Laravel feature: migration → model/factory → behavior (controller / FormRequest / action / job / Livewire / Filament) → route → feature test. Vertical, never a horizontal slice of one layer ("all migrations", "all the tests").
- A completed ticket is demoable or verifiable on its own; a route you can hit, a command you can run, a test you can watch pass.
- Each ticket is sized to fit one fresh agent session.
- When a spec exists, each ticket points to the parent's **Build Contract** and only the additional spec headings it needs; those heading links route progressive context, they do not restate the spec. On the spec-less path there is no Build Contract to link: carry the decisions the ticket needs inline instead.
- Prefactoring tickets come first.

Give each ticket its **blocking edges**: the tickets that must complete before it can start. A ticket with no blockers can start immediately.

**Wide refactors are the exception to vertical slicing.** A wide refactor is one mechanical change (rename a column, retype a shared value object) whose blast radius fans across the codebase so no vertical slice can land green. Sequence it as **expand–contract**:

1. **Expand**: add the new form beside the old so nothing breaks (new nullable column + dual-write; new method delegating to old).
2. **Migrate**: move call sites/data over in batches sized by blast radius (per module, per directory), each batch its own ticket blocked by the expand. A data backfill is its own ticket, a one-time operation leaving no permanent infra.
3. **Contract**: drop the old form once no caller remains, in a ticket blocked by *every* migrate batch. The contract migration is the only destructive step and lands last.

When even batches can't stay green alone, keep the sequence but share an integration branch, all blocking a final integrate-and-verify ticket: green is promised only there.

### 4. Green-light publication

**Granularity, blocking edges, and the axis you cut along are yours to settle.** Step 3's rules decide them, so don't run a review round on each: `grilling`'s **What still earns a question** keeps mechanical judgment off the user's plate.

Present the finished breakdown as a numbered list: per ticket: **Title**, **Blocked by**, **What it delivers** (the end-to-end behavior it makes work).

Then ask **exactly one** question, because step 5 writes a file per ticket and renumbering them afterwards isn't cheap: publish as listed (recommended) / adjust first, say what. Make whatever the user names, reprint the list, and don't reopen the parts they left alone.

### 5. Publish

Publishing creates external artifacts: do it only after step 4's green light.

Write one markdown file per ticket into `.scratch/<slug>/tickets/` (the `tickets/` directory **beside the spec**) there is no external tracker. Read the layout from `.agents/issue-tracker.md` (written by `/setup`) when the repo has one (`docs/agents/issue-tracker.md` is the legacy path); suggest running `/setup` once to make the paths durable. Set each ticket's `status` to `ready-for-agent`, or the AFK-ready role string from `.agents/triage-labels.md` when that mapping differs.

Publish in dependency order (**blockers first**) so each ticket's edges reference real identifiers. Publish idempotently: before writing, read what `tickets/` already holds, if this spec was already broken down, don't mint a second set; a re-run only fills gaps a failed mid-loop run left behind.

Do NOT close or modify the parent spec. Invoked directly on a spec-less map, set that `map.md`'s frontmatter to `status: closed`: `to-tickets` is then the handoff that ends the map. Invoked on a spec, leave the already-closed map alone.

## Ticket template

This template is canonical.

```markdown
---
title: <Ticket title>
status: ready-for-agent
claimed-by:            # empty = unclaimed
blocked-by: []         # blocker ticket numbers, e.g. [01, 03]; [] = can start immediately
---

# <NN>: <Ticket title>

## Parent

Relative path to the spec (`../spec.md`), or omit on the spec-less path.

## Parent context

Only when a spec exists, omit this whole section otherwise:

- [Build Contract](../spec.md#build-contract)
- [<only another spec heading this ticket needs>](../spec.md#<heading-anchor>)

## What to build

The end-to-end behaviour this ticket makes work, from the user's perspective, 
not a layer-by-layer implementation list.

## Acceptance criteria

- [ ] Behavior statements: what a user/caller can now do, what data is
      persisted, what is forbidden (authorization), never presentation
      ("page shows heading X") or implementation ("uses a repository")
```

Blockers live in the `blocked-by` frontmatter (ticket numbers), not a body section.

Files are numbered from `01` in topological order: every blocker has a lower number than the ticket it blocks. Numbers order dependencies; they do not serialize independent tickets.

Avoid file paths and code snippets; they go stale fast. Exception: a prototype-derived snippet that encodes a decision more precisely than prose (state machine, schema, enum shape); trim to the decision-rich parts.

## After publishing

Work the **frontier** (any ticket whose blockers are all done) with `implement`, one ticket per fresh session. Unblocked, unclaimed tickets can run in parallel in the same checkout. `implement` claims each ticket before building, by setting its frontmatter `status: in-progress` and `claimed-by:` to a session-unique value (compare-after-write, per the tracker's Claim operation), so a second session skips work already in progress instead of colliding with it.

## When you're done

Print the end-of-session block using the frame in [`wayfinder/references/pipeline-end-block.md`](../wayfinder/references/pipeline-end-block.md).

```text
---
Pipeline: decide → spec → **tickets** → build   (3 of 4)
Done: <how many tickets, how many on the frontier, with refs>
Next:
  • <condition> → /<skill> <ref>
```

Stage-specific **Next** conditions (only those that apply, most likely first):

- **Tickets published with a frontier** → `/implement <frontier ticket>` in one fresh session per ticket; parallelize only independent frontier tickets
- **Every ticket is blocked by another that is still open** → `/implement <that blocker>` first; name it
- **A ticket turned out to be a decision, not a build** → `/grill-me` on it (or `/wayfinder` if there are several)
- **Cutting the tickets exposed a gap the spec never settled** → `/grill-me` on the gap, then re-run `/to-spec`
- **Stopped before publishing** → say which tickets exist, which are drafted only, and which blocking edges are unwired
