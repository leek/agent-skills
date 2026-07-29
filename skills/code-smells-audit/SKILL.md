---
name: code-smells-audit
description: Audit a codebase, path, glob, or branch diff for classic code smells using the 56-smell Luzkan catalog, with detection heuristics tuned to PHP/Laravel and TS/React — sweep nine occurrence lenses, verify every candidate against the smell's card definition, emit a ranked markdown findings report. Use when the user says "audit code smells", "code smell audit", "smell check", or asks which catalog smells a module exhibits. Currently reference-only — the audit workflow is under construction; use the cards as review reference material.
---

# Code Smells Audit

Catalog-driven smell detection: instead of ad-hoc reviewer memory, findings are
matched against 56 distilled reference cards derived from Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) and verified against each
smell's actual definition before they reach the report.

> **Status: under construction.** The card catalog is being built lens by
> lens; the audit workflow lands once all 56 cards and the validation script
> exist. Until then this skill is reference-only.

## Reference material

- [references/index.md](references/index.md) — all 56 smells grouped under the
  9 occurrence lenses, one line each; detection passes dispatch from here and
  load full cards only for candidate matches
- `references/smells/<slug>.md` — one card per smell: taxonomy line,
  definition, detection heuristics (agnostic + PHP/Laravel + TS/React),
  example, refactorings, typed related-smell links, aliases
- [references/refactoring-names.md](references/refactoring-names.md) — the
  canonical refactoring vocabulary and the normalization map from upstream's
  103 raw names
- [references/ATTRIBUTION.md](references/ATTRIBUTION.md) — upstream MIT
  notice and the requested academic citation
