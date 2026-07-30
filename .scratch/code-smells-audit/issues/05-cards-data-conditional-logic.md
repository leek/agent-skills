# 05 — Cards: Data + Conditional Logic lenses (14 smells)

**Status:** closed (2026-07-30, commit 97dd3ae)

## Parent

Spec: `.scratch/code-smells-audit/spec.md`

## What to build

Finished distilled cards for every smell whose `occurrence` is **Data** (8) or
**Conditional Logic** (6), derived from the upstream clone's frontmatter and
following the card format proven by the pilot exactly. On completion, these
lenses are fully audit-ready: their index entries link to real cards.

Follow the working rules recorded in ticket 03 (sub-agent fan-out with
in-session review focused on stack-manifestation sections; PHP/TS examples
only, authored from the definition where upstream has none; normalization map
applied; frontmatter rules applied; partial-mode validation run if the script
exists).

## Acceptance criteria

- [x] Every Data and Conditional Logic smell has a card with all sections of the agreed format
- [x] No Python remains in any example; smells without upstream examples have authored ones
- [x] All refactor names on these cards are canonical per the normalization map
- [x] All related-smell links from these cards use the typed edge vocabulary and point at valid slugs
- [x] The index entries for these lenses link to the new cards

## Blocked by

- 01 — Pilot: skill skeleton + card format proven on the Measured Smells lens

## Resolution (2026-07-30, commit 97dd3ae)

Built as specified: 14 cards (8 Data, 6 Conditional Logic) authored via
4-agent fan-out from a fresh shallow clone of upstream, then reviewed
in-session with scrutiny on the stack-manifestation sections. Lens membership
re-derived from frontmatter and matched the index exactly. Mechanical
verification: taxonomy lines, related-smell edges, aliases, and refactor
lists all diffed against upstream frontmatter — all match; every PHP block
(30) lints under `php -l` 8.4; 4 ts blocks; no Python. Ticket 02's validator
passes in partial mode: 45 cards present, 11 pending, 2228 checks, 0 failures.

Notes for later tickets:

- **No normalization-map extension was needed.** One dedup this batch:
  null-check's upstream `Introduce Maybe` + `Introduce Optional` both map to
  `Introduce Optional` — the card lists it once, so a naive card-vs-upstream
  count diff will show 2 card entries vs 3 upstream. Deliberate.
- `global-data` was this batch's only smell without an upstream example
  (authored from the definition). Two more upstream examples are
  **smelly-only** (`special-case`, `tramp-data`); their solution halves are
  authored, and their provenance lines say so — batch 06 should use the same
  wording if it hits smelly-only examples.
- `callback-hell`'s upstream example is JavaScript, not Python — provenance
  line says so (echoes ticket 03's boolean-blindness/Haskell warning).
- Fan-out agents rendered multi-alias "Also known as" sections as bullet
  lists; pilot convention is comma-separated prose. Normalized in review —
  batch 06 prompts should state the prose convention explicitly.
- The four remaining no-example smells (base-class-depends-on-subclass,
  dead-code, incomplete-library-class — plus none others) all fall in
  batch 06.
