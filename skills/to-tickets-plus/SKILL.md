---
name: to-tickets-plus
description: Break a plan, spec, or the current conversation into tracer-bullet vertical-slice tickets with explicit blocking edges, approve the breakdown via AskUserQuestion, and publish to the project's issue tracker (GitHub, Linear, or local markdown). Use when the user says "to tickets", "break this into tickets/issues", or a spec needs slicing for implementation.
---

# To Tickets Plus

Break a plan, spec, or conversation into **tickets** — tracer-bullet vertical slices, each declaring the tickets that **block** it.

Pipeline position: `to-spec-plus` (record) → **`to-tickets-plus`** (slice) → `implement-plus` (build one ticket per session).

## Process

### 1. Gather context

Work from whatever is already in the conversation. If the user passes a reference (a spec path, an issue id or URL), fetch it and read its full body and comments.

### 2. Explore the codebase

If you haven't already, explore to understand the current state. Ticket titles and descriptions use the project's domain vocabulary (`CONTEXT.md`/glossary if present) and respect ADRs in the area.

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

### 4. Approve the breakdown

Present the proposal as a numbered list — per ticket: **Title**, **Blocked by**, **What it delivers** (the end-to-end behavior it makes work).

Then put the review through `AskUserQuestion` rather than an open-ended "thoughts?":

- **Granularity** — right-sized (recommended, if you believe it) / too coarse, split more / too fine, merge some.
- **Blocking edges** — correct / over-constrained (tickets could parallelize) / missing edges.
- Follow-ups per adjustment the user picks, until they approve.

Iterate on the list until approved. Do not publish an unapproved breakdown.

### 5. Publish

Publishing creates external artifacts — do it only after step 4's approval.

Tracker fast path: follow `docs/agents/issue-tracker.md` if present, else an `## Issue tracker` section in `AGENTS.md`/`CLAUDE.md`, else detect (Linear MCP → Linear; GitHub remote + `gh` → GitHub Issues; neither → local markdown) and confirm once with `AskUserQuestion`, offering to persist the choice.

Publish in dependency order — **blockers first** — so each ticket's edges reference real identifiers:

- **Linear** — one issue per ticket via `save_issue`; `parentId` = the spec/parent issue if there is one; `blockedBy` = native blocking relations; apply the `ready-for-agent` label.
- **GitHub** — one issue per ticket via `gh issue create`; native sub-issue/dependency APIs where available, `Blocked by: #a, #b` body lines where not (probe once, fall back without ceremony); apply the `ready-for-agent` label.
- **Local markdown** — one file per ticket under `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, numbered from `01` in dependency order. Never a single combined file.

Do NOT close or modify any parent issue.

## Ticket templates

Tracker issue:

```markdown
## Parent

Reference to the parent spec/issue (omit if none).

## What to build

The end-to-end behaviour this ticket makes work, from the user's perspective —
not a layer-by-layer implementation list.

## Acceptance criteria

- [ ] Behavior statements — what a user/caller can now do, what data is
      persisted, what is forbidden (authorization) — never presentation
      ("page shows heading X") or implementation ("uses a repository")

## Blocked by

- Reference to each blocking ticket, or "None — can start immediately".
```

Local file: same sections plus a `**Status:** ready-for-agent` line under the title `# <NN> — <Ticket title>`.

In either form, avoid file paths and code snippets — they go stale fast. Exception: a prototype-derived snippet that encodes a decision more precisely than prose (state machine, schema, enum shape); trim to the decision-rich parts.

## After publishing

Work the **frontier** — any ticket whose blockers are all done — one ticket at a time with `implement-plus`, clearing context between tickets. For a linear chain that means top to bottom.

## When you're done

End the session by printing the block below — on a clean finish, a stop, or a dead end. On harnesses without slash commands, write the command as plain phrasing (`run implement-plus on <ref>`) instead of `/implement-plus <ref>`.

```text
---
Pipeline: decide → spec → **slice** → build   (3 of 4)
Done: <how many tickets, how many on the frontier, with refs>
Next:
  • <condition> → /<skill> <ref>
```

List only the conditions that actually apply, most likely first:

- **Tickets published with a frontier** → `/implement-plus <first frontier ticket>`, then one per session with cleared context
- **Every ticket is blocked by something already open on the tracker** → `/implement-plus <that blocker>` first; name it
- **A ticket turned out to be a decision, not a build** → `/grill-me-plus` on it (or `/wayfinder-plus` if there are several)
- **Slicing exposed a gap the spec never settled** → `/grill-me-plus` on the gap, then re-run `/to-spec-plus`
- **Stopped before publishing** → say which tickets exist, which are drafted only, and which blocking edges are unwired
