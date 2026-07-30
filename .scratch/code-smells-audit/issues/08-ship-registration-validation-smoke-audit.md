# 08 — Ship: registration, full validation, smoke audit

**Status:** closed (2026-07-30, commit 51788de)

## Parent

Spec: `.scratch/code-smells-audit/spec.md`

## What to build

The integrate-and-verify slice: the skill becomes installable and proven.

- Register the skill in the marketplace manifest and add its README section,
  following the repo's registration steps for a new skill.
- Run the validation script in strict all-56 mode; fix whatever it finds
  (this is the gate where cross-batch link targets, index completeness, and
  normalization-map consistency are finally checkable together).
- Run one smoke audit of the finished skill against a real PHP/Laravel or
  TS/React codebase (pick one available locally), judged on: report shape
  matches the spec, ranking is sane (top findings are genuinely higher
  leverage than bottom ones), and the verify pass demonstrably dropped
  false-positive candidates rather than passing everything through.
- Record the smoke-audit judgment (including false-positive counts before and
  after verify) in a short note next to the spec, so the first real use has a
  baseline.

## Acceptance criteria

- [x] The skill appears in the marketplace manifest and README, and a fresh session can trigger it by description
- [x] Strict validation passes across all 56 cards with zero failures
- [x] The smoke-audit report exists, is ranked, and every finding carries smell name, location, rationale, obstruction tag, and refactorings
- [x] At least one candidate finding was dropped by the verify pass during the smoke audit, or the note explains why none needed to be
- [x] The smoke-audit judgment note exists alongside the spec

## Blocked by

- 02 — Structural validation script
- 03 — Cards: Names + Duplication lenses
- 04 — Cards: Responsibility + Message Calls lenses
- 05 — Cards: Data + Conditional Logic lenses
- 06 — Cards: Unnecessary Complexity + Interfaces lenses
- 07 — SKILL.md audit workflow

## Resolution (2026-07-30)

- Registered `./skills/code-smells-audit` in `.claude-plugin/marketplace.json`
  and added the README **Available Skills** section (commit 51788de).
- Strict validation passed first try: 56 cards, 2,697 checks, zero failures —
  no cross-batch link, index, or normalization-map fixes needed.
- Smoke audit ran end to end against `~/Developer/Leek/streamaba/app/Services`
  (231 files, medium tier → 9 lens sub-agents + 7 verify sub-agents):
  110 candidates → 28 dropped in verify (25.5%) → 82 ranked findings.
  Report: `.scratch/code-smells-audit/smoke-audit-report.md`.
  Judgment note (all three criteria pass, baseline metrics, caveats):
  `.scratch/code-smells-audit/smoke-audit-note.md`.
- Deviation: the smoke report was written next to the spec rather than the
  audited repo's `docs/audits/` (caller-named path, allowed by SKILL.md) to
  avoid dirtying streamaba.
- For the next user: the verify pass caught one false-premise candidate
  (a `readonly` class flagged as mutable) and honored card carve-outs —
  the definition-over-taste ground rule held in practice.
