# 03 — Cards: Names + Duplication lenses (14 smells)

**Status:** closed (2026-07-30, commit 90ccba8)

## Parent

Spec: `.scratch/code-smells-audit/spec.md`

## What to build

Finished distilled cards for every smell whose `occurrence` is **Names** (11)
or **Duplication** (3), derived from the upstream clone's frontmatter and
following the card format proven by the pilot exactly. On completion, these
lenses are fully audit-ready: their index entries link to real cards.

Working rules (same for every card-batch ticket):

- Author via sub-agent fan-out, then review every card in-session with the
  scrutiny concentrated on the PHP/Laravel and TS/React manifestation
  sections — that is where hallucinated heuristics would hide.
- Rewrite all examples in PHP or TS; author examples from the definition for
  any smell in this batch that has none upstream (the batch may include some
  of: base-class-depends-on-subclass, dead-code, duplicated-code, global-data,
  incomplete-library-class — check frontmatter for actual lens membership).
- Apply the pilot's refactor-name normalization map; extend it only if this
  batch surfaces a collision the map missed, and note the extension.
- Apply the spec's frontmatter rules (`['---']` = empty, `tags` dead).
- If the validation script (ticket 02) exists by the time this runs, finish by
  running it in partial mode; if not, self-check the same properties manually.

## Acceptance criteria

- [x] Every Names and Duplication smell has a card with all sections of the agreed format
- [x] No Python remains in any example; smells without upstream examples have authored ones
- [x] All refactor names on these cards are canonical per the normalization map
- [x] All related-smell links from these cards use the typed edge vocabulary and point at real slugs (cards may not exist yet if the target is in another batch — slug must still be valid)
- [x] The index entries for these lenses link to the new cards

## Blocked by

- 01 — Pilot: skill skeleton + card format proven on the Measured Smells lens

## Resolution (2026-07-30, commit 90ccba8)

Built as specified: 14 cards (11 Names, 3 Duplication) authored via 4-agent
fan-out from a fresh shallow clone of upstream, then reviewed in-session.
Lens membership re-derived from frontmatter and matched the index exactly.
Verification was mechanical where possible: taxonomy lines, related-smell
edges, aliases, and refactor lists all diffed against upstream frontmatter
(all match); link slugs checked against the 56 upstream slugs (all valid);
no Python in any example; every PHP block lints under `php -l` 8.4 (bare
method snippets wrapped in a class for linting, same shape the pilot uses).
Ticket 02's validator passes in partial mode: 18 cards present, 38 pending,
1020 checks, 0 failures.

Notes for later tickets:

- **No normalization-map extension was needed** — all 14 upstream refactor
  lists resolve through the existing table; the only actual translation was
  `Extract Function` → `Extract Method` on duplicated-code.
- `duplicated-code` was this batch's only smell without an upstream example
  (authored from the definition). The other frontier candidates on the
  spec's no-example list (base-class-depends-on-subclass, dead-code,
  global-data, incomplete-library-class) fall in batches 05/06.
- `boolean-blindness`'s upstream example is Haskell, not Python — its
  provenance line says so. Batches 04–06 should not assume "Python" in the
  provenance wording without checking.
- `binary-operator-in-name` extends the edge-vocabulary legend with one
  sentence explaining its unusual antagonistic edge to Side Effects —
  deliberate, kept after review.
