# Smoke-audit judgment — code-smells-audit skill

Date: 2026-07-30 · Ticket: 08 · Report: [smoke-audit-report.md](smoke-audit-report.md)

## Run

- **Target**: `~/Developer/Leek/streamaba/app/Services` — real production Laravel
  codebase, 231 PHP files, path-scoped (medium tier → one sub-agent per lens,
  per SKILL.md).
- **Sweep**: 9 lens passes, each armed only with its index section.
  Candidates per lens: Responsibility 15, Names 14, Data 14, Measured 14,
  Unnecessary Complexity 12, Conditional Logic 12, Interfaces 10,
  Duplication 10, Message Calls 9 — **110 total**.
- **Verify**: 7 batched adversarial passes reading full cards.
  **28 dropped (25.5%), 82 findings survived.**

## Judgment against the three spec criteria

**1. Report shape matches the spec — pass.** Header carries target / lenses /
candidate / dropped / finding counts; every one of the 82 findings has all
five required fields (smell name, location, definition-citing rationale,
obstruction tag, card refactorings) plus a one-line ranking rationale and a
card pointer.

**2. Ranking is sane — pass.** Top of the report is the workflow-engine
cluster (five parallel rule engines with *live semantic drift* — a
VOB-completeness rule and a duplicate-task guard already differ between
copies) and a PDF-pipeline copy where a production-proven timeout fix reached
only one of two copies. Bottom is `array_fill` one-liners and `$dateStr`
renames. Top findings are genuinely higher leverage than bottom ones, and
taxonomy was never used as a severity proxy (the ranking interleaves lenses
freely).

**3. Verify pass demonstrably dropped false positives — pass.**
False-positive counts: **110 before verify → 82 after; 28 dropped**, with
per-card drop reasons recorded in the report. The drops were substantive, not
cosmetic:

- One outright false premise caught: `ClaimCreationResult` flagged for
  mutable public fields is actually a `readonly` class.
- Card carve-outs honored: 4 of 6 inappropriate-static candidates dropped as
  "pure functions with no plausible second implementation"; all 3
  incomplete-library-class candidates dropped because the gap was filled once,
  through public API — the card's prescribed cure, not the smell.
- Definition-fit rejections: single-axis method families rejected for
  combinatorial-explosion (sum, not product); a behavior-rich model rejected
  for fate-over-action; Haversine's published `$a`/`$c` notation rejected for
  uncommunicative-name.
- Several drops correctly re-routed the evidence to the smell that did
  survive (static recursion guards: global-data → inappropriate-static;
  engine-family divergence: alternative-classes → duplicated-code).

## Baseline for future audits

| Metric | Value |
|---|---|
| Candidates / files | 110 / 231 (0.48 per file) |
| Verify drop rate | 25.5% |
| Survivors High / Med / Low (approx.) | 17 / 36 / 29 |
| Sweep agents · verify agents | 9 · 7 |

## Caveats observed

- Sweep agents sample rather than exhaustively read at this scale; recall
  within a lens is capped by the ~12-candidate instruction. Fine for a smoke;
  a whole-repo run should expect proportionally more candidates.
- One sweep evidence line overstated scope (claimed 14 services reach into
  `filament()->getTenant()`; verify counted 7) — the verify pass corrected it,
  which is the design working.
- Report was written next to the spec instead of the audited repo's
  `docs/audits/` (skill allows caller-named path) to avoid dirtying streamaba.
