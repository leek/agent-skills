---
name: wayfinder
description: Plan work too big for one agent session as a shared map of decision tickets on the project's issue tracker, then resolve them one per session until the route to the destination is clear.
disable-model-invocation: true
---

# Wayfinder

A loose idea has arrived — too big for one agent session, and wrapped in fog: the way from here to the **destination** isn't visible yet. Wayfinding finds that way instead of charging at the destination. Chart the way as a **shared map** on the project's issue tracker, then work its **decision tickets** — questions whose resolution is a decision, not slices of a build to execute — one at a time until the route is clear.

Naming the destination is the first act of charting — it shapes every ticket. It might be a spec to hand to `to-spec`, a decision to lock before planning starts, or a change made in place (a data-model migration, an expand–contract schema change).

Pipeline position: `wayfinder` (find the way) → `to-spec` (write the spec) → `to-tickets` (slice it) → `implement` (build one slice per session).

## Plan, don't do

Each ticket resolves a **decision**; the map is done when nothing is left to decide before someone goes and does the thing. The pull to just do the work is usually the signal you've reached the edge of the map and it's time to hand off. An effort can override this in its **Notes** — carrying execution into the map itself — but absent that, produce decisions, not deliverables.

When the map clears, **hand off — don't build**: use `to-spec` when the linked decisions need collapsing into a buildable plan, or go straight to `to-tickets` when the effort is genuinely small and already clear. `implement` starts from a build ticket, never directly from the map.

## Refer by name

Every map and ticket is an issue, so it has a **name** — its title. In everything the human reads, refer to it by that name with the path, id, or URL riding inside as a link — never a bare file path, `#42`, or `LIN-42`. A wall of identifiers is illegible; names read at a glance.

## The Map

The map is the configured tracker's canonical wayfinding artifact. Its tickets are children of the map.

The map is an **index**, not a store. It lists decisions made and points at the tickets that hold their detail; a decision lives in exactly one place — its ticket — so the map never restates it, only gists it and links.

Resolve the tracker once per session through `docs/agents/issue-tracker.md` (written by `/setup`) or an `## Issue tracker` section in `CLAUDE.md`/`AGENTS.md`. Its **Wayfinding operations** are the single source of truth for creating maps and children, recording types, wiring blockers, claiming, querying the frontier, resolving, and linking assets. When no tracker is configured, use the local-markdown operations under `.scratch/` from the `setup` skill's `issue-tracker-local.md` seed and suggest running `/setup` once to make the choice durable.

### The map body

The whole map at low resolution, loaded once per session. Open tickets are **not** listed — find them through the tracker's Frontier operation.

```markdown
## Destination

<what reaching the end of this map looks like — the spec, decision, or change
this effort is finding its way to. One or two lines; every session orients to
it before choosing a ticket.>

## Notes

<domain; skills every session should consult; standing preferences for this
effort — e.g. "all schema changes expand–contract", "Filament v3 conventions">

## Decisions so far

<!-- the index — one line per closed ticket -->

- [<closed ticket title>](link) — <one-line gist of the answer>

## Not yet specified

<!-- in-scope fog you can't ticket yet; graduates as the frontier advances -->

## Out of scope

<!-- work ruled beyond the destination; closed, never graduates -->
```

### Tickets

Each ticket is a **child issue** of the map. Its body is the question, sized to one fresh ~100K-token agent session:

```markdown
## Question

<the decision or investigation this ticket resolves>
```

Each ticket records one type — `research`, `prototype`, `grilling`, or `task` — through the configured tracker's wayfinding operations.

A session **claims** a ticket through the tracker's Claim operation **first**, before any work, so concurrent sessions skip it. A ticket with no claim is unclaimed.

Wire blocking through the tracker's Blocking operation. A ticket is **unblocked** when every ticket blocking it is closed; the **frontier** is the open, unblocked, unclaimed children — the edge of the known.

Record the answer only through the tracker's Resolve operation, rather than duplicating it in the initial question. Link assets created while resolving through its Assets operation.

## Ticket types

Every ticket is either **HITL** — human in the loop, worked *with* a human who speaks for themselves — or **AFK**, driven by the agent alone. A HITL ticket only resolves through that live exchange; the agent never stands in for the human's side (a grilling agent that answers its own questions has broken this).

- **Research** (AFK): read documentation, package source, third-party APIs, or internal knowledge bases to surface a fact a decision waits on. Resolved by a `research` **subagent** — findings land as a markdown summary linked from the ticket. Use when knowledge outside the working directory is required — e.g. "does Cashier support per-seat proration the way we need?"
- **Prototype** (HITL): raise the fidelity of the discussion with a cheap, throwaway, concrete artifact to react to — the `prototype` skill drives it. Laravel flavors: a scratch Artisan command or Tinker script that pushes a state model through hard cases; a throwaway route/Blade view, Livewire component, or Filament page for "what should it look like". Clearly named as a prototype, committed to a throwaway branch off main, linked from the ticket. Fold only the validated decision back.
- **Grilling** (HITL): run a `grilling` session — structured, click-to-answer questions, one decision at a time — with `domain-modeling` alongside it, capturing terms and ADRs as decisions land. The default type.
- **Task** (HITL or AFK): manual work that must happen before a *decision* can be made — signing up for a service so its API can be judged, provisioning access, moving data so its shape can be seen. The one type that *does* rather than decides, earning its place by unblocking a decision. The agent drives it alone where it can; otherwise it hands the human a precise checklist. The answer records what was done and any resulting facts (credentials location, URLs, row counts) later tickets depend on.

## Fog of war

The map is *deliberately* incomplete: don't chart what you can't yet see. Beyond the live tickets lies the **fog of war** — decisions you can tell are coming but can't pin down, because they hang on questions still open. Resolving a ticket clears the fog ahead of it, graduating whatever's now specifiable into fresh tickets, until the way to the destination is clear and no tickets remain.

**Not yet specified** on the map holds that dim view: the suspected question, the area to revisit. Everything there is in scope, just not sharp enough to ticket. It excludes what's already decided, what's already a live ticket, and what's out of scope.

**Fog or ticket?** The test is whether you can state the question precisely *now* — not whether you can answer it now.

- **Neither** when `grilling`'s **Settle it yourself first** ladder already answers it — existing context, established practice, or the default bias toward reuse and configurability. Settle it, record it in the map's **Notes** as a standing convention for the effort, and don't spend a ticket on it.
- **Ticket** when the question is already sharp — even if it's blocked.
- **Not yet specified** when you can't phrase it that sharply. Don't pre-slice fog into ticket-sized pieces: one patch may graduate into several tickets, or none, once the frontier reaches it.

## Out of scope

The destination fixes the scope, so work beyond it is **out of scope** — not fog, and not "Not yet specified". It gets the map's **Out of scope** section: work consciously ruled out of *this* effort.

When an existing ticket turns out to sit past the destination, **close it** and leave one line in Out of scope — the gist plus why, linking the closed ticket. It stays out of Decisions so far, which records only the route actually walked. Out-of-scope work never graduates; it returns only if the destination is redrawn, and then as a fresh effort.

## Structured questions

Decision points that arise outside a full grilling — confirming the destination phrasing, choosing between scope rulings, picking which frontier ticket to work — use the question shape from `grilling` (via `AskUserQuestion` where available, otherwise a plain question in chat): recommended option first, real trade-offs per option, wait for the answer. Don't reinvent the protocol here — including its **Settle it yourself first** ladder and **What still earns a question** bar, which gate every question this skill asks and every ticket it charts. When this skill invokes `grilling` or `domain-modeling`, the inner skill does **not** print an end-of-session block — only the outermost skill does.

## Invocation

Two modes. Either way, **never resolve more than one ticket per session** — with the exception of research tickets.

### Chart the map

User invokes with a loose idea.

1. **Name the destination.** Run a `grilling` session (with `domain-modeling`) to pin down what this map is finding its way to. The destination fixes the scope, so it's settled first.
2. **Map the frontier.** Grill again, **breadth-first**: fan out across the whole space rather than deep on any thread, surfacing the open decisions and the first steps takeable now. **If this surfaces no unresolved decision tickets**, the destination is already clear enough to hand off and you don't need a map. An empty Not yet specified section alone is not enough — sharp open decisions still become tickets. Stop and ask the user whether to go straight to `to-spec` or `to-tickets`.
3. **Create the map** through the tracker's Create map operation: Destination and Notes filled in, Decisions so far empty, the fog sketched into Not yet specified.
4. **Create the tickets you can specify now** through the tracker's Create ticket operation — then wire blocking edges in a **second pass**. Everything you can't yet specify stays in the fog.
5. **Resolve eligible research tickets.** Follow the `research` skill's Wayfinder integration to claim, dispatch, persist, and resolve them. If a research ticket cannot finish during this charting session, leave it open on the frontier for its own session.
6. Stop — charting is one session's work; it hand-resolves nothing.

### Work through the map

User invokes with a map (URL, id, or path). A ticket is optional — without one, you pick the next.

1. Load the **map** — the low-res view, not every ticket body.
2. Choose the ticket. If the user named one, use it; otherwise take the first frontier ticket. **Claim it** through the tracker's Claim operation before any work.
3. Resolve it per its type — zoom as needed: fetch full bodies of related or closed tickets on demand; consult the skills the map's Notes name. If in doubt, grill.
4. Record the answer through the tracker's Resolve operation, which closes the ticket and appends a one-line pointer to the map's Decisions so far.
5. Add newly surfaced tickets (create-then-wire); graduate any fog the answer made specifiable, clearing each graduated patch from Not yet specified. If the answer reveals a ticket sits beyond the destination, rule it out of scope rather than resolving it. Update tickets that remain valid; close invalidated tickets as superseded with a short reason so their history remains intact.

The user may run unblocked tickets in parallel, so expect other sessions to be editing the tracker concurrently.

## When you're done

End the session by printing the block below — on a clean finish, a stop, or a dead end. Refer to the map and tickets **by name**, per **Refer by name** above. On harnesses without slash commands, write the command as plain phrasing (`run wayfinder on <map>`) instead of `/wayfinder <map>`.

```text
---
Pipeline: **decide** → spec → slice → build   (1 of 4, multi-session map)
Done: <map name; tickets open, resolved, and still in the fog>
Next:
  • <condition> → /<skill> <map or ticket name>
```

Query the tracker for the current frontier before writing the block — don't guess at what's open. List only the conditions that actually apply, most likely first:

**After charting:**

- **Map charted with a frontier** → `/clear`, then `/wayfinder <map>` to resolve the first frontier ticket; name it (research tickets already resolved point at their `research/<slug>` branches)
- **Charting found no unresolved decision tickets** → no map needed: `/to-spec`, or `/to-tickets` if the shape is already clear

**After working a ticket:**

- **Map still has open tickets** → `/clear`, then `/wayfinder <map>` for the next frontier ticket; name it and say how many remain
- **Map cleared and its decisions need synthesis** → `/to-spec <map>` to collapse them into a buildable spec
- **Map cleared and the effort turned out genuinely small** → `/to-tickets <map>`
- **Ticket blocked on someone else's knowledge** → `/to-questionnaire`; **on a fact worth reading for** → `/research`
- **Stopped mid-ticket** → say which ticket is claimed, what's decided so far, and that the claim remains active
