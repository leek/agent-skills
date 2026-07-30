# 06 — Cards: Unnecessary Complexity + Interfaces lenses (11 smells)

**Status:** closed (2026-07-30, commit 95d0ef6)

## Parent

Spec: `.scratch/code-smells-audit/spec.md`

## What to build

Finished distilled cards for every smell whose `occurrence` is **Unnecessary
Complexity** (7) or **Interfaces** (4), derived from the upstream clone's
frontmatter and following the card format proven by the pilot exactly. On
completion, these lenses are fully audit-ready: their index entries link to
real cards — and with tickets 03–05 done, all 56 cards exist.

Follow the working rules recorded in ticket 03 (sub-agent fan-out with
in-session review focused on stack-manifestation sections; PHP/TS examples
only, authored from the definition where upstream has none; normalization map
applied; frontmatter rules applied; partial-mode validation run if the script
exists).

## Acceptance criteria

- [x] Every Unnecessary Complexity and Interfaces smell has a card with all sections of the agreed format
- [x] No Python remains in any example; smells without upstream examples have authored ones
- [x] All refactor names on these cards are canonical per the normalization map
- [x] All related-smell links from these cards use the typed edge vocabulary and point at valid slugs
- [x] The index entries for these lenses link to the new cards

## Blocked by

- 01 — Pilot: skill skeleton + card format proven on the Measured Smells lens

## Resolution (2026-07-30, commit 95d0ef6)

Built as specified: 11 cards (7 Unnecessary Complexity, 4 Interfaces) authored
via 3-agent fan-out from a fresh shallow clone of upstream, reviewed
in-session with scrutiny on the stack-manifestation sections. Lens membership
re-derived from frontmatter and matched the index exactly. Mechanical
verification: taxonomy lines, related-smell edges, aliases, and refactor
lists all diffed against upstream frontmatter — all match; every PHP block
(18) lints under `php -l` 8.4; 6 ts blocks, no Python. **All 56 cards now
exist**; ticket 02's validator passes in **strict** mode for the first time:
56 cards, 2697 checks, 0 failures.

Notes for later tickets:

- **No normalization-map extension was needed.** Translations applied:
  `Replace Loop with built-in` → `Replace with Built-In` (imperative-loops),
  `Inline Function` → `Inline Method` (lazy-element, speculative-generality),
  and refused-bequest's composite `Replace Superclass/Subclass with Delegate`
  expanded to both canonical names.
- `base-class-depends-on-subclass` is the catalog's only smell with an empty
  upstream `refactors` list. Its Refactorings section is prose, starting
  "None recorded upstream." followed by one sentence of practical direction —
  the validator only name-checks `- ` bullet lines, so this passes. New
  convention if upstream ever adds more refactor-less smells.
- The three remaining no-example smells (base-class-depends-on-subclass,
  dead-code, incomplete-library-class) got authored examples; refused-bequest
  upstream is smelly-only (Python) and uses batch 05's provenance wording.
- Upstream example languages this batch: Python (clever-code, lazy-element,
  speculative-generality, status-variable, inappropriate-static),
  JavaScript (imperative-loops), Python + a C++ block noted in the provenance
  line (obscured-intent).
- Card-batch tickets are done — 03–06 all closed. Frontier is ticket 07
  (SKILL.md audit workflow), then 08 (ship: registration, strict validation,
  smoke audit).
