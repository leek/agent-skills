# 04 — Cards: Responsibility + Message Calls lenses (13 smells)

**Status:** closed (2026-07-30, commit e79c52c)

## Parent

Spec: `.scratch/code-smells-audit/spec.md`

## What to build

Finished distilled cards for every smell whose `occurrence` is
**Responsibility** (11) or **Message Calls** (2), derived from the upstream
clone's frontmatter and following the card format proven by the pilot exactly.
On completion, these lenses are fully audit-ready: their index entries link to
real cards.

Follow the working rules recorded in ticket 03 (sub-agent fan-out with
in-session review focused on stack-manifestation sections; PHP/TS examples
only, authored from the definition where upstream has none; normalization map
applied; frontmatter rules applied; partial-mode validation run if the script
exists).

## Acceptance criteria

- [x] Every Responsibility and Message Calls smell has a card with all sections of the agreed format
- [x] No Python remains in any example; smells without upstream examples have authored ones
- [x] All refactor names on these cards are canonical per the normalization map
- [x] All related-smell links from these cards use the typed edge vocabulary and point at valid slugs
- [x] The index entries for these lenses link to the new cards

## Blocked by

- 01 — Pilot: skill skeleton + card format proven on the Measured Smells lens

## Resolution (2026-07-30, commit e79c52c)

Built as specified: 13 cards (11 Responsibility, 2 Message Calls) authored via
4-agent fan-out from a fresh shallow clone of upstream, reviewed in-session
with scrutiny on the stack-manifestation sections. Lens membership re-derived
from frontmatter and matched the index exactly. Mechanical verification:
taxonomy lines, related-smell edges (including merged multi-type rows),
aliases, and refactor lists all diffed against upstream frontmatter — all
match; every PHP block (22) lints under `php -l` 8.4; 4 ts blocks, no Python.
Ticket 02's validator passes in partial mode: 31 cards present, 25 pending,
1596 checks, 0 failures.

Notes for later tickets:

- **No normalization-map extension was needed.** Translations applied:
  `Extract Function`/`Move Function` → `Extract Method`/`Move Method`
  (divergent-change), `Extract method` → `Extract Method` (fate-over-action),
  `Fold Hierarchy into One` → `Collapse Hierarchy`
  (parallel-inheritance-hierarchies), and shotgun-surgery's two composites
  expanded (`Move Method and Move Field`, `Inline Function/Class`).
- Every smell in this batch had an upstream Python example — none authored
  from definition. The remaining no-example smells (base-class-depends-on-
  subclass, dead-code, global-data, incomplete-library-class) fall in
  batches 05/06.
- Upstream relation names are kept verbatim as link text even where they
  differ from card titles ("Flag Arguments", "Base Class Depends on
  Subclass", "Required Setup/Teardown Code") — slugs are what the validator
  checks, and all resolve.
- message-chain and middle-man deliberately cross-reference each other's
  examples (Hide Delegate applied once vs. reflexively) — kept after review;
  it mirrors upstream's framing of the antagonistic pair.
