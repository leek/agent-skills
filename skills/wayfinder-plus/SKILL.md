---
name: wayfinder-plus
description: Plan work too big for one agent session as a shared map of decision tickets on the project's issue tracker (GitHub, Linear, or local markdown), then resolve them one per session until the route to the destination is clear. Use when the user says "wayfinder", "chart a map", "work the map", or brings a loose idea too large or foggy to spec in one sitting.
---

# Wayfinder Plus

A loose idea has arrived — too big for one agent session, and wrapped in fog: the way from here to the **destination** isn't visible yet. Wayfinding finds that way instead of charging at the destination. Chart the way as a **shared map** on the project's issue tracker, then work its **decision tickets** — questions whose resolution is a decision, not slices of a build to execute — one at a time until the route is clear.

Naming the destination is the first act of charting — it shapes every ticket. It might be a spec to hand to `to-spec-plus`, a decision to lock before planning starts, or a change made in place (a data-model migration, an expand–contract schema change).

Pipeline position: `wayfinder-plus` (find the way) → `to-spec-plus` (write the spec) → `to-tickets-plus` (slice it) → `implement-plus` (build one slice per session).

## Plan, don't do

Each ticket resolves a **decision**; the map is done when nothing is left to decide before someone goes and does the thing. The pull to just do the work is usually the signal you've reached the edge of the map and it's time to hand off. An effort can override this in its **Notes** — carrying execution into the map itself — but absent that, produce decisions, not deliverables.

When the map clears, **hand off — don't build**: `to-spec-plus` collapses the map's linked decisions into a buildable plan, then `to-tickets-plus` and `implement-plus` as usual. Looping the map straight into `implement-plus` skips that collapse and throws the linked detail away — skip to `implement-plus` only when the effort turned out genuinely small.

## Refer by name

Every map and ticket is an issue, so it has a **name** — its title. In everything the human reads, refer to it by that name with the id/URL riding inside as a link — never a bare `#42` or `LIN-42`. A wall of ids is illegible; names read at a glance.

## The Map

The map is a single issue labelled `wayfinder:map` — the canonical artifact. Its tickets are child issues of the map.

The map is an **index**, not a store. It lists decisions made and points at the tickets that hold their detail; a decision lives in exactly one place — its ticket — so the map never restates it, only gists it and links.

How the map, children, blocking, and frontier queries are physically expressed is tracker-specific — see [references/trackers.md](references/trackers.md).

### The map body

The whole map at low resolution, loaded once per session. Open tickets are **not** listed — they are open child issues, found by query.

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

Each ticket is a **child issue** of the map. Its body is the question, sized to one fresh agent session:

```markdown
## Question

<the decision or investigation this ticket resolves>
```

Each ticket carries a `wayfinder:<type>` label — one of `research`, `prototype`, `grilling`, `task`.

A session **claims** a ticket by assigning it to the driving dev **first**, before any work, so concurrent sessions skip it. The assignee *is* the claim: an open, unassigned ticket is unclaimed.

Blocking uses the tracker's **native** dependency relationship where one exists (Linear `blockedBy`, GitHub issue dependencies) so the human sees what's takeable in the tracker's own UI. Only a tracker without native blocking falls back to a `Blocked by:` body line. A ticket is **unblocked** when every ticket blocking it is closed; the **frontier** is the open, unblocked, unclaimed children — the edge of the known.

The answer isn't part of the body — it's recorded on resolution. Assets created while resolving (research notes, prototype branches) are linked from the issue, not pasted in.

## Ticket types

Every ticket is either **HITL** — human in the loop, worked *with* a human who speaks for themselves — or **AFK**, driven by the agent alone. A HITL ticket only resolves through that live exchange; the agent never stands in for the human's side (a grilling agent that answers its own questions has broken this).

- **Research** (AFK): read documentation, package source, third-party APIs, or internal knowledge bases to surface a fact a decision waits on. Resolved by a `research-plus` **subagent** — findings land as a markdown summary linked from the ticket. Use when knowledge outside the working directory is required — e.g. "does Cashier support per-seat proration the way we need?"
- **Prototype** (HITL): raise the fidelity of the discussion with a cheap, throwaway, concrete artifact to react to. Laravel flavors: a scratch Artisan command or Tinker script that pushes a state model through hard cases; a throwaway route/Blade view, Livewire component, or Filament page for "what should it look like". Clearly named as a prototype, committed to a throwaway branch off main, linked from the ticket. Fold only the validated decision back.
- **Grilling** (HITL): run a `grill-me-plus` session — structured, click-to-answer questions, one decision at a time — with `domain-modeling-plus` alongside it, capturing terms and ADRs as decisions land. The default type.
- **Task** (HITL or AFK): manual work that must happen before a *decision* can be made — signing up for a service so its API can be judged, provisioning access, moving data so its shape can be seen. The one type that *does* rather than decides, earning its place by unblocking a decision. The agent drives it alone where it can; otherwise it hands the human a precise checklist. The answer records what was done and any resulting facts (credentials location, URLs, row counts) later tickets depend on.

## Fog of war

The map is *deliberately* incomplete: don't chart what you can't yet see. Beyond the live tickets lies the **fog of war** — decisions you can tell are coming but can't pin down, because they hang on questions still open. Resolving a ticket clears the fog ahead of it, graduating whatever's now specifiable into fresh tickets, until the way to the destination is clear and no tickets remain.

**Not yet specified** on the map holds that dim view: the suspected question, the area to revisit. Everything there is in scope, just not sharp enough to ticket.

**Fog or ticket?** The test is whether you can state the question precisely *now* — not whether you can answer it now.

- **Ticket** when the question is already sharp — even if it's blocked.
- **Not yet specified** when you can't phrase it that sharply. Don't pre-slice fog into ticket-sized pieces: one patch may graduate into several tickets, or none, once the frontier reaches it.

## Out of scope

The destination fixes the scope, so work beyond it is **out of scope** — not fog, and not "Not yet specified". It gets the map's **Out of scope** section: work consciously ruled out of *this* effort.

When an existing ticket turns out to sit past the destination, **close it** and leave one line in Out of scope — the gist plus why, linking the closed ticket. It stays out of Decisions so far, which records only the route actually walked. Out-of-scope work never graduates; it returns only if the destination is redrawn, and then as a fresh effort.

## Tracker resolution (fast path)

Resolve the tracker once per session, in order — see [references/trackers.md](references/trackers.md) for the operations each tracker uses:

1. `docs/agents/issue-tracker.md` exists → follow it.
2. An `## Issue tracker` section in `AGENTS.md`/`CLAUDE.md` → follow it.
3. Detect: Linear MCP tools available and the user works this project in Linear → Linear. A GitHub remote plus authed `gh` → GitHub Issues. Neither → local markdown under `.scratch/`.
4. On first detection, confirm the choice with one `AskUserQuestion` and offer to persist it to `docs/agents/issue-tracker.md` so future sessions skip the question.

## Structured questions

Decision points that arise outside a full grilling — confirming the destination phrasing, choosing between scope rulings, picking which frontier ticket to work — go through `AskUserQuestion` (Claude Code) or `request_user_input` (Codex): recommended option first, real trade-offs per option, blocking until answered. The full question protocol lives in `grill-me-plus`; don't reinvent it here.

## Invocation

Two modes. Either way, **never resolve more than one ticket per session** — with the exception of research tickets.

### Chart the map

User invokes with a loose idea.

1. **Name the destination.** Run `grill-me-plus` (with `domain-modeling-plus`) to pin down what this map is finding its way to. The destination fixes the scope, so it's settled first.
2. **Map the frontier.** Grill again, **breadth-first**: fan out across the whole space rather than deep on any thread, surfacing the open decisions and the first steps takeable now. **If this surfaces no fog** — the whole journey fits one session — you don't need a map. Stop and ask the user whether to go straight to `to-spec-plus` or `to-tickets-plus`.
3. **Create the map** (label `wayfinder:map`): Destination and Notes filled in, Decisions so far empty, the fog sketched into Not yet specified.
4. **Create the tickets you can specify now** as children of the map — then wire blocking edges in a **second pass** (issues need ids before they can reference each other). Everything you can't yet specify stays in the fog.
5. **Fire the research subagents.** For each `research` ticket you just created, spin up a `research-plus` subagent to resolve it in parallel, capturing its findings on a throwaway `research/<name>` branch with a context pointer from the ticket.
6. Stop — charting is one session's work; it hand-resolves nothing.

### Work through the map

User invokes with a map (URL, id, or path). A ticket is optional — without one, you pick the next.

1. Load the **map** — the low-res view, not every ticket body.
2. Choose the ticket. If the user named one, use it; otherwise take the first frontier ticket. **Claim it** — assign before any work.
3. Resolve it per its type — zoom as needed: fetch full bodies of related or closed tickets on demand; consult the skills the map's Notes name. If in doubt, grill.
4. Record the resolution: post the answer as a **resolution comment**, **close** the issue, and **append a one-line pointer** to the map's Decisions so far.
5. Add newly surfaced tickets (create-then-wire); graduate any fog the answer made specifiable, clearing each graduated patch from Not yet specified. If the answer reveals a ticket sits beyond the destination, rule it out of scope rather than resolving it. If the decision invalidates other parts of the map, update or delete those tickets.

The user may run unblocked tickets in parallel, so expect other sessions to be editing the tracker concurrently.
