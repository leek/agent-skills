# Spec: code-smells-audit skill

Status: ready-for-agent
Source session: grill-me-plus, 2026-07-28
Upstream: https://github.com/Luzkan/smells (MIT, 56 smells, last push 2026-05-01)

## Problem Statement

I want to audit codebases for classic code smells with the rigor of a real
catalog, not ad-hoc reviewer memory. The best available catalog — Luzkan's
codesmells.org (56 smells, four-axis taxonomy, typed relation graph, academic
provenance) — exists only as a website with Python-flavored examples. My
existing skills cover adjacent ground (technical-debt does inventory and
prioritization, code-slop detects AI patterns, clean-code-principles is
reference-only) but none does systematic, catalog-driven smell detection, and
none speaks the catalog's vocabulary.

## Solution

A new standalone skill, `code-smells-audit`, in this repo's marketplace. It
vendors the Luzkan catalog as 56 distilled, detection-oriented reference cards
tuned to PHP/Laravel and TS/React, and wraps them in an audit workflow: sweep a
target (path, glob, diff, or whole repo) through nine occurrence-axis detection
lenses, adversarially verify each candidate finding against the smell's card
definition, and emit a ranked markdown findings report with the catalog's
suggested refactorings.

## User Stories

1. As a developer, I want to run `code-smells-audit` with no arguments and get a whole-repo sweep, so that I get a full health picture without configuring anything.
2. As a developer, I want to pass a path or glob to scope the audit, so that I can spot-check one module cheaply.
3. As a developer, I want to pass `diff` to audit only the current branch's changes, so that the skill works as a PR-review companion.
4. As a developer, I want detection guidance phrased in PHP/Laravel and TS/React terms, so that findings reference patterns I actually see (Eloquent chains, controllers, components, hooks) instead of generic OO prose.
5. As a developer, I want every finding verified against the smell's actual catalog definition before it reaches the report, so that I don't wade through false positives — the known weakness of smell heuristics.
6. As a developer, I want the report ranked by judged severity/leverage rather than category membership, so that the top of the report is what to fix first.
7. As a developer, I want each finding to carry the smell name, location, why it qualifies, its obstruction category, and the catalog's suggested refactorings, so that every finding is actionable without opening the catalog.
8. As a developer, I want the report saved as a durable markdown artifact, so that I can compare audits over time and hand findings to other pipeline skills.
9. As a reader of a finding, I want to open the smell's reference card and see its definition, aliases, related smells, and provenance, so that I can judge edge cases myself.
10. As the skill's maintainer, I want a validation script that structurally checks the card set, so that a future upstream re-sync or careless edit can't silently ship a broken catalog.
11. As the skill's maintainer, I want upstream attribution (MIT notice, Springer citation) shipped inside the skill, so that redistribution stays clean.
12. As an agent running the audit, I want an index grouping all 56 smells by occurrence lens with one-line definitions, so that each detection pass loads only the cards it needs (progressive disclosure).

## Implementation Decisions

- **Standalone skill** named `code-smells-audit`, following this repo's skill
  conventions (SKILL.md under 500 lines, specific trigger-phrase description,
  progressive disclosure into a references directory). Registered in the
  marketplace manifest and the README like every other skill. Chosen over
  extending `technical-debt` to keep that skill scoped to inventory and
  prioritization; the two may cross-reference.
- **Content: distilled cards, all 56 smells.** One card per smell, kebab-case
  slug matching upstream. Card structure (settled during grilling):
  - Title + taxonomy line: `expanse · obstruction · occurrence`
  - One-paragraph definition (rewritten, not copied prose)
  - Detection heuristics, split into agnostic core, PHP/Laravel
    manifestations, and TS/React manifestations
  - Refactorings (from upstream `refactors` frontmatter, names normalized)
  - Related smells with typed edges (causes / caused / family / co-exist /
    antagonistic), rendered as links to sibling cards
  - Known-as aliases where upstream has them
- **Example rewriting.** Upstream examples are illustrative Python (100 blocks
  across 46 files); cards get PHP or TS examples instead. The 7 smells with no
  upstream example (base-class-depends-on-subclass, dead-code, duplicated-code,
  global-data, incomplete-library-class, large-class, long-method) get examples
  authored from the definition.
- **Frontmatter handling rules** (from upstream schema quirks): treat `['---']`
  array values as empty; ignore the dead `tags` field; normalize the 103-name
  refactor vocabulary's near-duplicates (e.g. `Extract Method` /
  `Extract method` / `Extract Methods` collapse to one canonical name) —
  concrete normalization map decided at build time.
- **Index by occurrence axis.** A single index file lists all 56 smells grouped
  under the 9 occurrence lenses (Responsibility, Names, Data, Unnecessary
  Complexity, Conditional Logic, Interfaces, Measured Smells, Duplication,
  Message Calls), each with its one-line `meta.description`. Detection passes
  dispatch from this index and read full cards only for candidate matches.
- **Audit workflow** (in SKILL.md):
  1. Resolve target: argument is a path, glob, or `diff`; no argument means
     whole repo, fanning out sub-agents by size.
  2. Sweep: one detection pass per occurrence lens, each armed with that
     lens's card summaries.
  3. Verify: every candidate finding is adversarially re-checked against the
     full card's definition (does this actually meet the definition, or is it
     a near-miss?) before it may enter the report.
  4. Report: ranked by judged severity/leverage; each finding carries smell
     name, location, qualification rationale, obstruction tag, and suggested
     refactorings. Taxonomy is used for sweeping and tagging, never as a
     severity proxy.
- **Attribution.** The skill ships the upstream MIT notice
  (Copyright (c) 2022-2026 Marcel Jerzyk) and the author's requested citation
  (Jerzyk & Madeyski 2023, *Code Smells: A Comprehensive Online Catalog and
  Taxonomy*, Studies in Systems, Decision and Control vol 462, Springer,
  DOI 10.1007/978-3-031-25695-0_24) in an attribution note within the skill
  folder. Cards note they are derivative works, not upstream copies.
- **Build approach note.** Authoring 56 cards is a fan-out job (sub-agents per
  batch, sourced from the upstream clone), with a review pass focused on the
  stack-manifestation sections — that's where quality lives and where
  hallucinated heuristics would hide.

## Testing Decisions

- **Seam 1 — structural validation script** (the regression seam): a bash
  script per this repo's script conventions (`set -e`, status to stderr, JSON
  results to stdout) that checks: exactly 56 cards present with expected slugs;
  each card has the required sections; taxonomy values belong to the closed
  vocabularies (2 expanse, 10 obstruction, 9 occurrence values); every
  related-smell link resolves to an existing card; index lists all 56 exactly
  once. Runs at build time and on any future card edit or upstream re-sync.
- **Seam 2 — smoke audit**: one end-to-end run of the finished skill against a
  real PHP/Laravel or TS/React codebase before shipping; judged on report
  shape, ranking sanity, and false-positive rate of the verify pass.
- No test framework — this is a markdown-and-bash repo; the script and the
  smoke run are the whole verification story.
- Ground rule carried over from grilling: the verify pass judges findings
  against card definitions, not against taste — a finding that fails the
  definition is dropped even if the code is ugly.

## Out of Scope

- **Upstream sync automation.** Cards will drift from upstream wording by
  design; a re-sync procedure is deliberately undefined (upstream last pushed
  2026-05-01, still active — revisit if it matters).
- **Ticket handoff.** The skill ends at the ranked report; slicing findings
  into tickets stays a manual `/to-tickets-plus` decision.
- **Stacks beyond PHP/Laravel and TS/React.** The agnostic core keeps cards
  usable elsewhere, but no other stack gets manifestation sections.
- **Severity metadata.** The catalog has none; severity stays a per-finding
  judgment, not card data.
- **Catalog site features** (relation-graph browsing, filtering UI) — the
  typed edges are recorded on cards but no graph tooling is built.

## Further Notes

- A shallow clone of upstream sits in this session's scratchpad
  (`…/scratchpad/smellsrepo/`) with the content in `content/smells/`, the Zod
  schema in `src/schemas/smell.ts`, and the closed vocabularies in
  `src/lib/constants.ts`. The scratchpad is session-scoped — re-clone
  (`git clone --depth 1 https://github.com/Luzkan/smells`) if it's gone at
  build time. Upstream's `data_scraper/` emits frontmatter-only JSON per smell
  if machine extraction beats parsing YAML directly.
- Full research findings (license, section-frequency table, taxonomy counts,
  metadata vocabularies) are in the grill session transcript of 2026-07-28.
- Known build-time risks, none blocking: card quality at fan-out scale (review
  pass required), refactor-name normalization map (decide when the full 103
  names are in hand).
