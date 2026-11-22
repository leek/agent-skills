# Shared exploration

When planning or building against an existing codebase, reuse a compact evidence
record at `.scratch/<effort>/research/codebase.md`. Start it when an effort directory
exists; earlier exploration stays in session context until that handoff. A grill
with no durable tracker prints the findings with its ledger instead. This is an
index of verified facts, not a second decision ledger or spec.

## Record during exploration

- **Revision**: inspected commit SHA, relevant uncommitted changes, and date.
- **Constraints**: pointers to applicable repo rules, ADRs, and domain vocabulary.
- **Live paths**: entry point → caller/registration → producer or consumer for each
  affected invariant. File existence alone is not evidence of use.
- **Prior art**: verified implementation and test paths, public test boundaries,
  and what each example covers or misses.
- **Validation**: exact focused commands and required setup, with results only for
  commands actually run. Reference configuration rather than copying secrets.
- **Volatile facts**: database counts, external docs, or service behavior, with the
  source, observation time, and the condition requiring another check.

For each finding, list the source paths and symbols (or external source), the
inspected revision, and its scope. Include discovery inputs such as route/provider
registration, manifests, and relevant directories: a newly added caller can change
a finding even when its named source file did not change. Link authoritative
decisions in `decisions/` and the spec; keep their answers there.

## Reuse at each handoff

Read the record before exploring. Compare its revision with the current tree,
including staged, unstaged, and untracked changes in its scope. A rebase, missing
revision, incomplete scope, or uncertain change impact requires fresh exploration
of the affected finding. For a known history, inspect changed paths and new files in
the recorded discovery scope; refresh findings those changes could affect. Recheck
external facts when their freshness matters, and database counts immediately before
using them to justify a destructive simplification. A matching Git revision alone
does not establish either fact's freshness.

Reuse unaffected findings; explore gaps and changed areas, then update those entries
with the new evidence and revision. Do not stamp unverified entries as current.
The record is complete for a handoff when every fact the next stage relies on has
either reusable evidence or a named gap to investigate.

## Ownership

Planning stages update this file as they discover facts. `to-spec` links it in
Further Notes; tickets link the relevant headings in Parent context. During a
parallel build, the orchestrator refreshes the shared record before dispatch and
passes its pointer in every brief. Workers report corrections in their run notes;
the orchestrator incorporates them, so workers keep the rule that only the
orchestrator writes `.scratch/`. Preserve findings from any shared exploration
worker here before creating ticket worktrees. Commit updates with the effort's
existing planning/tracker commits, without a new approval gate.

Reviewers independently trace the implementation and its callers. The record can
locate evidence, but its conclusions never replace review or frame a fresh
reviewer's initial pass.
