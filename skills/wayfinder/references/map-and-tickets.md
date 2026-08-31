# Map body and tickets

Open tickets are **not** listed on the map: find them through the tracker's Frontier operation.

## Map body

```markdown
## Destination

<what reaching the end of this map looks like, the spec, decision, or change
this effort is finding its way to. One or two lines; every session orients to
it before choosing a ticket.>

## Notes

<domain; skills every session should consult; standing preferences for this
effort: e.g. "all schema changes expand–contract", "Filament v3 conventions">

## Decisions so far

<!-- derived index: regenerate from the closed, resolved tickets when you
     read or show it; never hand-append, or parallel resolves clobber it -->

- [<closed ticket title>](link), <one-line gist of the answer>

## Not yet specified

<!-- in-scope fog you can't ticket yet; graduates as the frontier advances -->

## Out of scope

<!-- work ruled beyond the destination; closed, never graduates -->
```

## Ticket body

Each ticket is a **child file** of the map. Sized to one fresh ~100K-token agent session:

```markdown
## Question

<the decision or investigation this ticket resolves>
```

Each ticket records one type (`research`, `prototype`, `grilling`, or `task`) through the configured tracker's wayfinding operations.

A session **claims** a ticket through the tracker's Claim operation **first**, before any work, so concurrent sessions skip it. A ticket with no claim is unclaimed.

Wire blocking through the tracker's Wire blocking operation. A ticket is **unblocked** when every ticket blocking it is closed; the **frontier** is the open, unblocked, unclaimed children, the edge of the known.

Record the answer only through the tracker's Resolve operation, rather than duplicating it in the initial question. Link assets created while resolving through its Assets operation.
