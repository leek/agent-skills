# 02 — Structural validation script

**Status:** closed (2026-07-29, commit da24850)

## Parent

Spec: `.scratch/code-smells-audit/spec.md`

## What to build

A validation script inside the skill folder, per this repo's script
conventions (bash, `set -e`, status messages to stderr, machine-readable JSON
results to stdout), that structurally verifies the card set so a future
upstream re-sync or careless edit cannot silently ship a broken catalog.

Checks, per the spec's testing decisions:

- Every expected slug has a card; no unexpected cards.
- Every card contains the required sections of the agreed format.
- Taxonomy values belong to the closed vocabularies (2 expanse, 10
  obstruction, 9 occurrence values).
- Every related-smell link resolves to an existing card.
- The index lists each of the 56 smells exactly once under an occurrence lens.

Because card batches land incrementally, the script supports a partial-set
mode: validate whatever cards exist (format, taxonomy, resolvable links among
present cards) while reporting missing slugs as pending rather than failing —
with the strict all-56 mode as the default for the ship gate.

## Acceptance criteria

- [x] Running the script against the pilot set passes in partial mode and reports the 52 pending slugs
- [x] Strict mode fails while any of the 56 cards is missing
- [x] Deliberately breaking a card (removed section, invented taxonomy value, dangling related-smell link, duplicate index entry) makes the script fail loudly, with the offending file and reason in the output
- [x] JSON on stdout is parseable and states pass/fail, checked counts, and failures; human-readable status goes to stderr

## Blocked by

- 01 — Pilot: skill skeleton + card format proven on the Measured Smells lens

## Resolution (2026-07-29, commit da24850)

Built `skills/code-smells-audit/scripts/validate-cards.sh` (bash 3.2 / BSD
sed+awk compatible; strict mode default, `--partial` for mid-build). All four
acceptance scenarios verified by execution, plus a wider regression battery
from two review sub-agents (standards + spec fidelity). A reviewer confirmed
strict mode reaches green on a synthetic valid 56-card set, so the ship gate
is reachable. SKILL.md gained a "Validating the card set" usage section.

Checks beyond the spec's five, adopted from review — tickets 03–06 should
expect these to be enforced:

- Every related-table row must parse as `| [Title](slug.md) | edges |`;
  unparseable rows fail loudly instead of being silently exempted (the
  index-style `(smells/slug.md)` prefix is the likely copy-paste mistake).
- No duplicate targets in a related table — merge edge types into one row.
- Required sections must be non-empty, not just present.
- Refactoring bullets must start with a canonical name from
  refactoring-names.md (an optional ` — gloss` suffix is allowed).
- Each card needs ≥1 `php`/`ts`/`tsx` fence; `py`/`python` fences are banned
  in any casing; other supplementary languages (json, bash, …) are allowed.
- Example sections must state provenance (a line mentioning "upstream").
- Edge-vocabulary legend line (`Edge vocabulary: …`) required per card.
- Cards' occurrence value must match the embedded catalog lens; index
  entries must sit under the correct lens with accurate per-lens counts;
  a card that exists but is unlinked in the index fails — this forces each
  batch to update the index as it lands.

Known limits, accepted: the validator cannot detect *dropped* content (a
card keeping 1 of 5 upstream relations passes — batch review must catch
that); headings quoted inside code fences would double-count; the embedded
catalog assumes upstream's single-occurrence-per-smell invariant holds.
