# 07 — SKILL.md audit workflow

**Status:** closed (2026-07-30, commit aea7a2d)

## Parent

Spec: `.scratch/code-smells-audit/spec.md`

## What to build

The complete audit procedure in SKILL.md, replacing the pilot's stub, written
against the pilot lens so it is demoable before all cards exist. Per the
spec's workflow decisions:

1. **Target resolution** — argument is a path, glob, or `diff` (current
   branch's changes); no argument means whole-repo sweep, fanning out
   sub-agents by codebase size.
2. **Sweep** — one detection pass per occurrence lens, dispatched from the
   index; each pass loads only that lens's card summaries, reading full cards
   for candidate matches (progressive disclosure).
3. **Verify** — every candidate finding is adversarially re-checked against
   the full card's definition before it may enter the report; a finding that
   fails the definition is dropped even if the code is ugly.
4. **Report** — durable ranked markdown artifact ordered by judged
   severity/leverage; each finding carries smell name, location,
   qualification rationale, obstruction tag, and the card's suggested
   refactorings. Taxonomy is never used as a severity proxy.

Also: the frontmatter description gets its final trigger phrases ("audit for
code smells", "code smell audit", "run code-smells-audit", plus stack-relevant
variants), and SKILL.md stays under 500 lines with detail offloaded to the
references.

## Acceptance criteria

- [x] A demo run scoped to the Measured Smells lens against a sample source file produces a ranked report with every field the spec requires per finding
- [x] A `diff` -target run audits only changed files; a path-target run audits only that path
- [x] The workflow instructs the verify step to cite the card definition it checked against, and dropped candidates do not appear in the report
- [x] SKILL.md is under 500 lines and its description matches on the trigger phrases
- [x] The workflow reads lens membership from the index rather than embedding its own smell list

## Blocked by

- 01 — Pilot: skill skeleton + card format proven on the Measured Smells lens

## Resolution (2026-07-30, commit aea7a2d)

Built the four-step workflow in SKILL.md (160 lines): target resolution
(path / glob / `diff` via merge-base + porcelain / whole-repo with
size-tiered sub-agent fan-out), per-lens sweep dispatched from
`references/index.md` as the sole source of lens membership, adversarial
verify that must cite the card definition sentence each finding satisfies,
and a ranked report saved to `docs/audits/` with all five per-finding
fields. Description carries the final trigger phrases.

Demo run (Measured Smells lens, sample Laravel controller in the session
scratchpad): 5 candidates → 3 findings (Long Method, Long Parameter List,
Vertical Separation, ranked), 2 dropped in verify — a 27-line flat `match`
lookup that tripped the length alarm but failed Long Method's "several
distinct steps or responsibilities", and a 3-method class that failed Large
Class's definition. Dropped candidates appear in the report only as a header
count, per the workflow rule.

Deviations from ticket wording, all judged benign in review: full cards are
read in the verify step rather than during the sweep (net-identical — every
candidate is verified, so cards still load only for candidates); invented
where the spec was silent: default report path (`docs/audits/`),
vendor/generated-code exclusions, dropped-candidate count in the header.
Also fixed a stale line in `references/index.md` ("unlinked entries are
pending card batches" — all 56 are linked now).

For ticket 08: marketplace/README registration is untouched (flagged in
review, confirmed out of scope here), and the workflow is demo-proven only —
the real-codebase smoke audit remains 08's job. Strict validation passes
(56 cards, 2697 checks).
