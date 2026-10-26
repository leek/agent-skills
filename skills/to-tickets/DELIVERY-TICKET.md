# Delivery ticket

Every ticket breakdown ends with one **delivery ticket**. It builds nothing. It proves that the spec shipped whole: each requirement traced to working code, the full checks run, and every step that only happens at or after deploy (commands, backfills, flags, smoke checks) written down and then done. The spec is complete only when this ticket is closed, so a spec cannot read as done while a backfill still waits.

## Draft it

`to-tickets` drafts it last, from the spec and the other tickets, and gives it the highest number. Its `blocked-by` lists every other ticket, and `delivery: true` marks it in the frontmatter. A ticket added later (a gap, a spec revision) joins its `blocked-by`.

Fill each list from the source. Do not leave a generic placeholder: write the real command, URL, table, or flag. A list with nothing in it says `None`.

- **Spec coverage**: each user story or requirement in the spec, with the ticket that delivers it. A requirement that no ticket delivers is a gap: add a ticket for it before you publish.
- **Before merge**: checks the builder runs in the session. The full test suite (or the repo's rule for it). One end-to-end pass over each flow that crosses tickets. The docs, `.env.example` keys, config, and changelog lines the spec needs.
- **After deploy**: each step that runs in a real environment. Migrations, artisan or other commands, data backfills, scheduled jobs and queue workers to check or restart, feature flags to flip, env keys to set, smoke checks (a URL, a command, a query, with the result to expect), logs and error trackers to watch, and the timing of a later contract step. Mark each step that changes data as `(changes data)`.

## Template

```markdown
---
title: Delivery check: <spec title>
status: ready-for-agent
claimed-by:
blocked-by: [01, 02, …]   # every other ticket
deploy-gate: false
delivery: true
---

# <NN>: Delivery check: <spec title>

## Parent

`../spec.md`

## What to build

Nothing new. Prove the spec shipped whole, before merge and after deploy.

## Spec coverage

- [ ] <user story or requirement>: ticket <NN>

## Before merge

- [ ] Full test suite green
- [ ] End to end: <flow that crosses tickets>

## After deploy

- [ ] `<command>` (changes data): <what to expect>
- [ ] Smoke check <URL or command>: <what to expect>
```

## Work it

The builder (`implement`, a spec run, `implement-spec`, an autopilot worker) works it after every other ticket is closed or merged, in two passes.

**Pass 1: before merge.** Skip the seams and TDD steps; nothing new gets built.

1. Check each **Spec coverage** line against the code and each ticket's `Resolution`. A requirement that is missing or broken is a gap. In a spec run or `implement-spec`, fix it in the run, like a verify failure. In a one-ticket `implement` session, add a ticket for it (numbered after the last one, with `to-tickets`' template), add it to this ticket's `blocked-by`, release this ticket, and stop.
2. Run each **Before merge** check, and tick each one that passes.
3. With **After deploy** at `None`: close the ticket per `implement` step 8. Otherwise: set `status: ready-for-human`, clear `claimed-by`, and append a `## Comments` note with the commit or PR to deploy. Copy the After deploy list into the PR body after Merge Danger, as `After deploy:` lines. `ready-for-human` holds autopilot at this ticket and keeps the spec open in `scratch-status`.

**Pass 2: after deploy.** `/implement <this ticket>` once the work is live. Confirm the deploy first: ask the user, or check the deployed commit when the repo documents how. Run each read-only check yourself. A step that changes data or a real environment runs only with the user's explicit approval for that step; otherwise give the user the exact command and wait for the result. Tick each item with what you observed. When every item is ticked, append `## Resolution` with the evidence and set `status: closed`. An item that fails stays unticked: report it, and leave the ticket open.
