# 01 — Pilot: skill skeleton + card format proven on the Measured Smells lens

**Status:** closed (2026-07-28, commit 5b42c1b)

## Parent

Spec: `.scratch/code-smells-audit/spec.md`

## What to build

The `code-smells-audit` skill folder exists in this repo's conventions, and the
distilled-card format is proven end to end on the smallest, hardest lens: the
4 smells whose `occurrence` is **Measured Smells** (derive membership from the
upstream clone's frontmatter — this lens includes `long-method`, one of the
seven smells with no upstream code example, so the slice exercises
from-definition example authoring, not just translation).

A reviewer can open any pilot card and judge the complete format: taxonomy
line, rewritten definition, agnostic + PHP/Laravel + TS/React detection
heuristics, PHP/TS example, normalized refactorings, typed related-smell
links, aliases.

Also delivered because every later ticket depends on them:

- The attribution note (upstream MIT notice, Copyright (c) 2022-2026 Marcel
  Jerzyk, plus the Jerzyk & Madeyski 2023 Springer citation; cards are noted
  as derivative works).
- The occurrence-axis index scaffold: all 9 lenses, all 56 slugs with their
  upstream one-line descriptions; the 4 pilot smells link to real cards, the
  other 52 are listed but unlinked.
- The refactor-name normalization map, derived from the full set of 103
  upstream `refactors` names (near-duplicates collapsed to one canonical name
  each), recorded where card-batch tickets can apply it.

If the session scratchpad clone of Luzkan/smells is gone, re-clone shallow
from https://github.com/Luzkan/smells first. Apply the spec's frontmatter
rules: `['---']` means empty; the `tags` field is dead.

## Acceptance criteria

- [x] The skill folder exists with a valid SKILL.md stub (name + trigger-phrase description frontmatter) so the marketplace format is satisfiable later
- [x] 4 Measured Smells cards exist, each containing every section of the agreed card format, with examples in PHP or TS (none in Python)
- [x] The card for a smell with no upstream example has an authored example consistent with its definition
- [x] The index lists all 56 smells exactly once, grouped under the 9 occurrence lenses, each with a one-line description
- [x] The normalization map covers all 103 upstream refactor names with no remaining near-duplicate canonical names
- [x] The attribution note is present and contains the verbatim MIT notice and the Springer citation
- [x] Related-smell links on pilot cards use the typed edge vocabulary (causes / caused / family / co-exist / antagonistic)

## Blocked by

- None — can start immediately.

## Resolution (2026-07-28, commit 5b42c1b)

Built as specified: `skills/code-smells-audit/` with SKILL.md stub,
`references/{ATTRIBUTION.md,index.md,refactoring-names.md}` and 4 cards in
`references/smells/`. Measured Smells membership derived from frontmatter =
large-class, long-method, long-parameter-list, vertical-separation; two of
those (large-class, long-method) had no upstream example, so the slice
exercised from-definition authoring twice. Verified structurally (all
criteria checked mechanically against the upstream clone) plus two review
sub-agents (standards + spec fidelity — both clean after fixes). PHP
examples lint under `php -l` 8.4.

Deviations and notes for later tickets:

- **Cards live at `references/smells/<slug>.md`** (two levels below
  SKILL.md). Deliberate: the index is the dispatch hop, per the spec's
  progressive-disclosure design. Tickets 03–06 must use the same directory
  and `<slug>.md` naming — pilot cards already forward-link to
  side-effects.md, flag-argument.md, temporary-field.md, data-clump.md,
  message-chain.md, global-data.md, clever-code.md, obscured-intent.md,
  dubious-abstraction.md. These links are dead until those batches land
  (ticket 02's script will catch any that stay dead).
- **Normalization map yields 86 canonical names** (14 variants collapsed,
  5 composites expanded, introducing Replace Subclass with Delegate and
  Replace Type Code with State/Strategy). Card batches translate every
  upstream `refactors` entry through the table before writing it.
- **Card conventions the batches should copy:** "Also known as" section is
  always present ("None recorded upstream." when empty); upstream duplicate
  relation rows merge into one row with combined edge tokens (see
  long-method's Side Effects "causes, co-exist"); each card ends with the
  edge-vocabulary legend and the derivative-work footer; example sections
  state provenance ("Translated from the upstream example." or "Authored
  for this card — upstream has no code example for this smell.").
- **SKILL.md description ends with a "currently reference-only" clause** —
  ticket 07 should remove it when the workflow lands.
- Registration in marketplace.json/README deliberately not done (ticket 08).
- Upstream frontmatter parsing gotcha: `- ---` placeholder values contain
  the string `---\n`, so naive frontmatter splitting truncates 26 of 56
  files — anchor the delimiter to a full line (`^---$`).
