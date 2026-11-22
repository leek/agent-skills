# Build schedule

Read after drafting a multi-ticket breakdown, and again when `implement-spec`
chooses among ready tickets. Optimize elapsed build time within the real dependency
graph; a larger worker count cannot shorten a chain.

## Before publishing

1. Compare every ticket's `## Files` list against the others. List shared paths
   and distinguish a semantic dependency from incidental file contention. Move
   append-only shared registrations (an independent route, translation key,
   provider binding, or config/menu entry) to `## Shared registrations` so they
   do not serialize unrelated slices. Verify callers and the repository's
   extension points before choosing a change.
2. For remaining incidental contention under `## Files`, consider an existing
   module/registration boundary or a small behavior-preserving prefactor that
   gives each feature its own file. Add the prefactor only when its cost is
   justified by the parallel work it unlocks; its tests preserve existing
   behavior, and dependent feature tickets block on it. Keep each feature
   independently demoable. A `## Files` edit that remains stays serialized;
   incomplete features waiting for a final wiring ticket are not a fix.
3. Give each build ticket a `## Scheduling` section with `Work: 1`, `Work: 2`, or
   `Work: 3` (small, medium, large relative to this effort), and one sentence naming
   the likely cost: implementation, setup, or tests. These are scheduling estimates,
   not promises or questions for the user. Split a ticket too large for one session.
4. In the delivery ticket's `## Build schedule`, record the longest dependency
   chain, remaining shared-file bottlenecks, and the proposed first wave. A chain
   that could be shortened without changing semantics gets revised before publish.

Finish when every shared path has an owner/dependency or an explicit serialization
note, and the first wave can run together: no `## Files` path of one ticket appears
in another's `## Files` or `## Shared registrations` (two Shared registrations of one
path may overlap).

## At dispatch

For each unmerged build ticket, its remaining path weight is its Work plus the
largest remaining path weight of any dependent (zero if it has none). Exclude the
delivery ticket; an older ticket without Work uses 2. Count actual blockers, not
ticket-number order. A cycle is a tracker error to fix before dispatch.

Among ready, unclaimed tickets, dispatch the largest remaining path weight first;
break ties by ticket number. Skip a candidate when a `## Files` path of either
ticket appears in the other's `## Files` or `## Shared registrations`, and try the
next; overlap only under `## Shared registrations` runs in parallel. Recompute after merges, releases, or graph changes.
Dependencies, deploy gates, claims, and the concurrency limit remain hard
constraints.
