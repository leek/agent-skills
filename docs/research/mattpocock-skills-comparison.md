# Comparison with `mattpocock/skills`

## Auditable baseline

- Upstream compared: `mattpocock/skills` `main` at commit [`6654f6b60cd9d5be8b54c6fafe44346dabeb3b76`](https://github.com/mattpocock/skills/commit/6654f6b60cd9d5be8b54c6fafe44346dabeb3b76), committed `2026-08-24T15:19:57+01:00` (`2026-08-24T14:19:57Z`). A live `git ls-remote` check on 2026-08-30 returned the same SHA.
- Local compared: `leek/agent-skills` `main` at `98c57bb7c4e951d31e9bc369d6a10cf0f7afd540` (`2026-08-18T14:30:32-04:00`), with a clean tracked worktree before this report.
- Scope: upstream `main`, including its promoted, in-progress, misc, and deprecated buckets. Upstream has 37 skills total, but only the 25 under `engineering/` and `productivity/` are shipped in its plugin; the bucket rules explicitly exclude drafts and misc skills from distribution. [Upstream repository rules at the pinned SHA](https://github.com/mattpocock/skills/blob/6654f6b60cd9d5be8b54c6fafe44346dabeb3b76/AGENTS.md)

## Executive conclusion

Do **not** wholesale-sync upstream. This repository is a real fork, not a stale mirror: its Markdown-only tracker, one-ticket-per-session Laravel implementation loop, end-to-end verification, safe research lifecycle, dirty-worktree handling, and richer local-only skills are deliberate and often stronger for its actual use. The lineage is explicit in `README.md:11` and local commit `50b38864a756148d1d4ab4385505840a4c5be0ff`, which ported the upstream suite and then adapted it.

There are, however, four concrete defects or omissions worth fixing first:

1. Codex invocation metadata is absent from all 35 local skills.
2. Cross-skill invocation is expressed inconsistently, and six skills violate the repo's own single-folder portability promise by linking into `wayfinder`.
3. `diagnosing-bugs` missed upstream's secret-redaction guardrail.
4. The local verifier currently fails because `skills/.DS_Store` exists, and it does not check the three drift classes above.

After those, the best capability additions are a local router, the upstream `wizard` concept, and broadening `writing-great-skills` into a model-invoked reference for every agent-facing document. The latest upstream `retro` should influence `distill-sessions`, not become a second overlapping skill.

## Inventory and lineage

The collections share 20 exact skill names. Two more are obvious conceptual descendants rather than exact-name matches:

| Upstream | Local | Disposition |
|---|---|---|
| `setup-matt-pocock-skills` | `setup` | Intentional local rewrite around `.agents/*.md` and a Markdown-only `.scratch/` tracker. Keep local. |
| `writing-for-agents` | `writing-great-skills` | Same lineage, but upstream has since broadened and renamed it. Pull the broader scope, not necessarily the name verbatim. |

The 15 local-only names are not evidence of drift. They include substantial capabilities upstream does not have: `autopilot`, `verify`, `resolve-review-comments`, `repository-cleanup`, `commit`, `panel`, `code-smells-audit`, Laravel Herd worktrees, dependency audits, and maintenance loops. The local catalog is listed at `README.md:25-61`.

Conversely, 17 upstream names do not exist locally, but only three promoted capabilities are genuinely absent after accounting for renamed descendants: a router (`ask-matt`), `wizard`, and `wait-what`. Most of the other names are upstream-only beta or personal/niche work.

## Priority findings

### P0: encode invocation mode for Codex

Every upstream skill has `agents/openai.yaml`; user-invoked skills pair Claude's `disable-model-invocation: true` with Codex's `policy.allow_implicit_invocation: false`. Upstream calls the two fields a synchronization invariant. [Upstream invocation policy](https://github.com/mattpocock/skills/blob/6654f6b60cd9d5be8b54c6fafe44346dabeb3b76/.agents/invocation.md) [Example user-invoked metadata](https://github.com/mattpocock/skills/blob/6654f6b60cd9d5be8b54c6fafe44346dabeb3b76/skills/engineering/ask-matt/agents/openai.yaml)

Local reality:

- 35 `SKILL.md` files.
- 22 declare `disable-model-invocation: true`.
- 0 have `agents/openai.yaml`.
- `AGENTS.md:64-69` promises a user/model invocation split across a harness-agnostic collection, but only encodes the Claude side.

Recommendation: add `agents/openai.yaml` to every skill, with `display_name` and `short_description`, and add `policy.allow_implicit_invocation: false` to the 22 user-invoked skills. Generate or verify it from frontmatter so the two harness policies cannot drift. Upstream added this systematically in [`697d4ce`](https://github.com/mattpocock/skills/commit/697d4ce9742da558fd1ba6697c8e9775e2e302dd).

### P0: make cross-skill calls operative and portable

Upstream changed operative dependencies from bare slash-name prose to explicit instructions to call the Skill tool, because a name alone has a lower activation rate. It also forbids a skill from calling a user-invoked skill; only the human can launch one. [Cross-skill invocation change](https://github.com/mattpocock/skills/commit/d28dfdc39beadc3142a33359b5cfa4765dcbd0bc) [User-invoked dependency correction](https://github.com/mattpocock/skills/commit/1dab98299c3b81f560026c01b7ebf55ed5d91373)

Local operative sites still say things such as:

- `skills/grill-me/SKILL.md:9`: run `grilling`.
- `skills/grill-with-docs/SKILL.md:9`: run `grilling` with `domain-modeling`.
- `skills/implement/SKILL.md:41-73`: run or consult `tdd`, `code-review`, and `verify`.
- `skills/triage/SKILL.md:77`: run `grilling` and `domain-modeling`.
- `skills/improve-codebase-architecture/SKILL.md:13,64-71`: run four named skills, still using slash syntax.

Those targets are model-invoked, so the fix is straightforward: say `Call the Skill tool with "tdd"` (one call per skill), while leaving `/name` only in user-facing routing text.

There is one genuine invocation-type bug: `skills/diagnosing-bugs/SKILL.md:124-134` automatically hands off to `improve-codebase-architecture`, but that target is user-invoked. Change this to a recommendation for the human, or make the architecture skill model-invoked only if autonomous invocation is actually wanted.

There is also a packaging contradiction. `AGENTS.md:106` says each skill folder can be copied alone, yet these six local skills link to `../wayfinder/references/pipeline-end-block.md`:

- `skills/grill-me/SKILL.md:13`
- `skills/to-spec/SKILL.md:105`
- `skills/to-tickets/SKILL.md:112`
- `skills/implement/SKILL.md:93`
- `skills/code-review/SKILL.md:106`
- `skills/to-questionnaire/SKILL.md:61`

A single-skill install of any of them has a dead reference. Choose one coherent model:

1. Make routing a small model-invoked reference skill and call it explicitly.
2. Declare and install `wayfinder` as a hard dependency of those skills.
3. Drop the shared block, as upstream did.

The current state tries to have both independent folders and undeclared cross-folder imports.

### P0: port secret redaction into `diagnosing-bugs`

Upstream now requires secrets to be redacted from commands, outputs, captured traces, and artifacts, keeps credentials in environment variables, and treats auth headers as sensitive. [Pinned upstream `diagnosing-bugs`](https://github.com/mattpocock/skills/blob/6654f6b60cd9d5be8b54c6fafe44346dabeb3b76/skills/engineering/diagnosing-bugs/SKILL.md#L11-L17) [Originating security change](https://github.com/mattpocock/skills/commit/efce423018fc6468a3239621f1c1bcaacc723801)

Local `skills/diagnosing-bugs/SKILL.md:12-60` asks the agent to paste commands and output, capture HAR/log/core artifacts, and replay traces, but has no redaction instruction. This is a direct safety regression, not a stylistic difference.

Recommendation: add upstream's short redaction section, then thread “redacted” into the artifact request and Phase 1 completion evidence. Keep the local Laravel-specific loop and post-mortem; only pull the safety delta.

### P0: repair and broaden collection verification

The live local verifier failed one check: `skills/.DS_Store` exists, even though `scripts/verify-skills-collection.sh:30-32` forbids it. The file is ignored by `.gitignore`, which is why `git status` still appeared clean. Remove it in the follow-up implementation.

`claude plugin validate . --strict` passes on Claude Code 2.1.251, so the existing marketplace manifest is **not invalid**. The immediate failure is the junk file, not plugin packaging.

Extend `scripts/verify-skills-collection.sh` to check:

- every skill has valid, parseable YAML frontmatter;
- every skill has matching `agents/openai.yaml`, including policy parity;
- no `SKILL.md` has an undeclared cross-skill relative link;
- explicit Skill-tool wording is used at operative dependencies;
- README invocation/description entries agree with frontmatter;
- `claude plugin validate . --strict` passes when Claude is installed.

README drift already exists: `README.md:51` carries upstream's old quoted one-line description for `resolving-merge-conflicts`, while `skills/resolving-merge-conflicts/SKILL.md:3` has the local, richer description.

### P1: add a local router

Upstream's promoted `ask-matt` is a user-invoked map over its flows, on-ramps, vocabulary skills, standalones, and phase boundaries. [Pinned router](https://github.com/mattpocock/skills/blob/6654f6b60cd9d5be8b54c6fafe44346dabeb3b76/skills/engineering/ask-matt/SKILL.md) [Phase-boundary decision tree](https://github.com/mattpocock/skills/blob/6654f6b60cd9d5be8b54c6fafe44346dabeb3b76/skills/engineering/ask-matt/PHASE-BOUNDARIES.md)

This repository has 22 user-invoked skills, and its own authoring reference says a router is the cure when user-invoked skills exceed what a human can remember (`skills/writing-great-skills/SKILL.md:20`). It has no router.

Recommendation: add `ask-skills`, `which-skill`, or another local name. Do not copy `ask-matt` literally: its tracker, prototype-branch, and context-window flow disagree with local behavior. Generate the inventory from the local catalog where possible, then hand-author only the relationships and decision boundaries. At minimum it should route:

- decide: `grill-me`, `grill-with-docs`, `wayfinder`;
- synthesize/build: `to-spec`, `to-tickets`, `implement`, `autopilot`;
- incoming work: `triage`, `resolve-review-comments`;
- diagnose/verify/review: `diagnosing-bugs`, `verify`, `code-review`, `panel`;
- maintenance: `housekeeper`, `repository-cleanup`, `dependency-audit`, `nightly-docs-sweep`, `distill-sessions`.

### P1: broaden `writing-great-skills` into `writing-for-agents`

Upstream renamed and expanded the skill from skill-only authoring to every document an agent consumes: skills, `AGENTS.md`, `CLAUDE.md`, and pointed-at reference docs. It moved skill mechanics into a companion file and made the general writing discipline model-invoked so other skills can use it. [Rename/restructure commit](https://github.com/mattpocock/skills/commit/17f22a371b664caa1fc0dd53cc8f0d4ea0e9ef25) [Pinned general reference](https://github.com/mattpocock/skills/blob/6654f6b60cd9d5be8b54c6fafe44346dabeb3b76/skills/productivity/writing-for-agents/SKILL.md) [Pinned skill mechanics](https://github.com/mattpocock/skills/blob/6654f6b60cd9d5be8b54c6fafe44346dabeb3b76/skills/productivity/writing-for-agents/SKILL-MECHANICS.md)

Local `skills/writing-great-skills/SKILL.md:1-83` is still user-invoked and skill-specific, while `AGENTS.md` itself contains substantial agent-facing writing policy. Preserve the local glossary, which is richer than upstream's current companion, but adopt the broader model:

- universal reference: context pointers, context vs cognitive load, information hierarchy, completion criteria, caches of environment truth, leading words, pruning;
- disclosed companion: skill frontmatter, invocation, and router mechanics;
- model-invoked description covering edits to skills and agent instruction docs.

This would also give upstream's new `retro` rubric a reusable writing discipline without duplicating it.

### P1: add `wizard`

Upstream's promoted `wizard` generates a human-operated Bash script for work the agent truly cannot perform: external dashboards, credentials, secrets, and one-off cutovers. It ships a reusable template with stage progress, URL opening, hidden input, idempotent `.env` writes, GitHub secret/variable helpers, and confirmation gates. [Pinned `wizard`](https://github.com/mattpocock/skills/blob/6654f6b60cd9d5be8b54c6fafe44346dabeb3b76/skills/engineering/wizard/SKILL.md) [Pinned template](https://github.com/mattpocock/skills/blob/6654f6b60cd9d5be8b54c6fafe44346dabeb3b76/skills/engineering/wizard/template.sh)

No local skill owns this boundary. `to-questionnaire` gathers knowledge, `autopilot` drives agent-executable work, and `setup` configures this skill suite; none turns manual provisioning into a repeatable, checked script.

Recommendation: port the concept and template, then adapt its script to this repo's shell policy and safety rules. Keep it model-invoked only for genuinely human-only steps; the agent should still perform everything it is authorized and able to do.

### P1: merge `retro`'s environment rubric into `distill-sessions`

The latest upstream commit adds an **Information access** category to a new in-progress `retro` skill. Its full rubric covers navigation, automated checks, coding standards, global agent instructions, tool economy, no-ops, and missing read-only information access. [Pinned `retro`](https://github.com/mattpocock/skills/blob/6654f6b60cd9d5be8b54c6fafe44346dabeb3b76/skills/in-progress/retro/SKILL.md) [Latest commit](https://github.com/mattpocock/skills/commit/6654f6b60cd9d5be8b54c6fafe44346dabeb3b76)

Local `distill-sessions` is stronger at log discovery, batching, redaction, evidence, multi-session recurrence, and destination selection (`skills/distill-sessions/SKILL.md:9-88`), but its analysis categories are narrower: corrections, command failures, setup repetition, and content moments.

Recommendation: do not add a second overlapping `retro` skill yet. Add upstream's environment-improvement lenses to `distill-sessions` and keep the local evidence bar. In particular, “information the agent could not access” is distinct from a repeated setup step and would catch missing log tees, absent read-only service access, and hidden operational state.

### P2: consider `wait-what`

Upstream's promoted `wait-what` is only one operative sentence: re-pitch the previous message with missing context, Simplified Technical English, and the relevant domain vocabulary. [Pinned `wait-what`](https://github.com/mattpocock/skills/blob/6654f6b60cd9d5be8b54c6fafe44346dabeb3b76/skills/productivity/wait-what/SKILL.md)

It is genuinely missing, cheap, and composable. Add it if this correction happens often enough to justify another user-invoked name. Otherwise the planned router and normal conversational correction are sufficient; do not add it merely for parity.

### P2: offer a shareable HTML logic-prototype branch

Local logic prototypes are project-runtime terminal apps (`skills/prototype/SKILL.md:12-25`; `skills/prototype/LOGIC.md:1-79`). Upstream changed this branch to a single self-contained HTML file with domain-language labels, free play, and guided edge-case scenarios, specifically so a non-developer can double-click and evaluate it. [Prototype change](https://github.com/mattpocock/skills/commit/6bcbcb09e2f1ed5fa20b4e890c732ecbb58c6b64) [Pinned HTML logic branch](https://github.com/mattpocock/skills/blob/6654f6b60cd9d5be8b54c6fafe44346dabeb3b76/skills/engineering/prototype/LOGIC.md)

This is not a universal replacement. A PHP/Artisan TUI is better when liftable Laravel code is the primary outcome; HTML is better when a PM, designer, or domain expert must feel the model. Make it a branch selected by audience. Keep the local rule that preserves the prototype as a clearly named file; do not pull upstream's throwaway-branch lifecycle into a shared dirty-worktree workflow.

## Structural practices worth considering

### Separate maturity from installation

Upstream buckets skills into promoted, in-progress, misc, and deprecated, and its plugin ships only promoted skills. [Bucket rules](https://github.com/mattpocock/skills/blob/6654f6b60cd9d5be8b54c6fafe44346dabeb3b76/AGENTS.md) Local `.claude-plugin/marketplace.json:17-52` installs every local skill.

This is not automatically wrong for a personal collection. It becomes valuable if experimental skills are being added frequently: introduce an explicit maturity field or directories, and keep drafts out of the plugin without hiding their source. Avoid adopting upstream's nested directory layout unless the installer and local symlink workflow need it; a flat promoted `skills/` directory remains simpler for cross-harness discovery.

### Split plugin identity from marketplace listing

Upstream uses `.claude-plugin/plugin.json` for plugin identity, version, metadata, and the curated skills array, while `.claude-plugin/marketplace.json` only lists the plugin source. It syncs the plugin version from `package.json`. [Pinned plugin manifest](https://github.com/mattpocock/skills/blob/6654f6b60cd9d5be8b54c6fafe44346dabeb3b76/.claude-plugin/plugin.json) [Version sync script](https://github.com/mattpocock/skills/blob/6654f6b60cd9d5be8b54c6fafe44346dabeb3b76/scripts/sync-plugin-version.mjs)

Local's inline marketplace form currently validates, so migration is not urgent. Adopt the split if the collection is moving toward official marketplace distribution or automated releases; it provides a clearer version source of truth and richer plugin metadata.

### Add human-facing discoverability, but keep it proportional

Upstream gives every promoted skill a docs page with four useful reader-facing questions: what it does, when to reach for it, common questions, and observable signs it is working. [Pinned docs policy](https://github.com/mattpocock/skills/blob/6654f6b60cd9d5be8b54c6fafe44346dabeb3b76/.agents/writing-docs.md)

Maintaining 35 separate pages is probably too much for this personal repo. The high-leverage subset is:

1. add the router;
2. generate/check the README catalog from frontmatter;
3. document only complex public flows (`autopilot`, `wayfinder`, `implement`, `triage`) if users besides the maintainer need them.

### Keep these local divergences

Do not pull the following upstream behavior merely because it is newer:

- **External tracker as system of record.** Local `README.md:13-23` deliberately defines one `.scratch/<slug>/` Markdown effort tree. Replacing it would unravel `setup`, `wayfinder`, `to-spec`, `to-tickets`, `implement`, `triage`, and `autopilot` together.
- **Always-background research.** Local `research` requires the sub-agent to finish in-session, handles harnesses without sub-agents, requires citations, persists one known path, and prevents dead task handles. It is materially safer than upstream's 12-line background-only version. Compare `skills/research/SKILL.md:7-38` with [upstream research](https://github.com/mattpocock/skills/blob/6654f6b60cd9d5be8b54c6fafe44346dabeb3b76/skills/engineering/research/SKILL.md).
- **Thin upstream `implement`.** Upstream's promoted implementation skill is 15 lines; local `skills/implement/SKILL.md:1-110` has the actual Laravel, concurrency, TDD, review, verification, and resolution contract. Keep local.
- **Upstream's multi-question grilling rounds.** Local intentionally promises one decision at a time (`README.md:37-39` and `skills/grilling/SKILL.md`). The upstream horizontal-rule update supports multiple questions in a round; it conflicts with the local interaction contract.
- **No-em-dash style rule.** Upstream removed them repo-wide, but this is house style, not a correctness update. Local prose uses them deliberately; do not create a 119-file churn-only change.
- **Prototype branches.** Upstream retains prototypes on throwaway branches. Local's no-new-branch/shared-worktree choices are integrated with its concurrency and dirty-tree safety. Pull the artifact idea selectively, not the branch policy.

## Upstream skills not worth importing wholesale

| Upstream status | Skill | Local assessment |
|---|---|---|
| In progress | `implement-spec` | Overlaps `autopilot` plus `implement`. Its frontier/worktree/sub-agent idea is useful comparative input, but local already has a more mature observable runner. Do not duplicate. [Source](https://github.com/mattpocock/skills/blob/6654f6b60cd9d5be8b54c6fafe44346dabeb3b76/skills/in-progress/implement-spec/SKILL.md) |
| In progress | `claude-handoff` | Local `handoff` is portable across harnesses; direct `claude --bg` launch could be an optional mode, not a new Claude-only front door. [Source](https://github.com/mattpocock/skills/blob/6654f6b60cd9d5be8b54c6fafe44346dabeb3b76/skills/in-progress/claude-handoff/SKILL.md) |
| In progress | `setup-ts-deep-modules` | A good dependency-cruiser enforcement skill, but outside the collection's Laravel center. Import only if TypeScript package-boundary work recurs. [Source](https://github.com/mattpocock/skills/blob/6654f6b60cd9d5be8b54c6fafe44346dabeb3b76/skills/in-progress/setup-ts-deep-modules/SKILL.md) |
| In progress | `loop-me`, `writing-beats`, `writing-fragments`, `writing-shape` | Personal workflow/article-writing tools, unrelated to the local engineering suite. |
| Misc | `git-guardrails-claude-code` | Useful only if Claude-specific hooks are wanted. The repository already has strong procedural Git safety, though hooks would provide enforcement. Evaluate separately. [Source](https://github.com/mattpocock/skills/blob/6654f6b60cd9d5be8b54c6fafe44346dabeb3b76/skills/misc/git-guardrails-claude-code/SKILL.md) |
| Misc | `setup-pre-commit`, `migrate-to-shoehorn`, `scaffold-exercises` | Narrow TypeScript/course-authoring utilities. No reason to import for parity. |

## Recommended pull plan

1. **Correctness patch:** remove `skills/.DS_Store`; port redaction into `diagnosing-bugs`; add and verify `agents/openai.yaml`; repair operative cross-skill calls; resolve cross-folder pipeline-block dependencies; fix README drift.
2. **Discoverability patch:** add a local router and generate or validate its skill inventory against disk/frontmatter.
3. **Authoring patch:** broaden `writing-great-skills` into a model-invoked agent-document reference while retaining the local glossary.
4. **Capability patch:** add an adapted `wizard`; merge `retro`'s rubric into `distill-sessions`.
5. **Optional experiments:** add audience-selected HTML logic prototypes; trial `wait-what`; evaluate TypeScript boundary enforcement only when a real repo needs it.

Each patch should be separate. The first is mostly mechanical and safety-critical; the others require product decisions and should not be smuggled into an “upstream sync” commit.

## What this unblocks

This makes the next action decidable: take the correctness patch first, then choose whether the collection should grow through a router/authoring upgrade and `wizard`, without overwriting the local Laravel and Markdown workflow that is already stronger than upstream for its intended use.

---

## Delta check, 2026-09-22

- Upstream `main` now at `c55ee46073ed923f86ce59a5eb3b6d895095d1b7` (2026-09-18). 12 non-merge commits since the `6654f6b` baseline; 9 files changed outside `docs/`.
- Local `main` at `912dcfe`. Of the Aug 30 plan, everything landed except `wizard`: `agents/openai.yaml` on all 38 skills, redaction in `diagnosing-bugs`, `which-skill` router, `wait-what`, `writing-for-agents`, HTML logic prototypes, `plugin.json`, `distill-sessions` environment lenses incl. Information access, verifier passes clean.

### What changed upstream

1. **New `pr` skill** (in-progress, model-invoked). PR-body format: Summary as the smallest visual (pseudocode / call tree / component tree / file tree / Mermaid / diff), Evidence as before/after pairs (screenshots S-tier, execution output A-tier), Merge Danger as one-way/two-way door plus blast radius. Content credited to Dex Horthy's `show-me` (Humanlayer), copied in with a `CREDITS.md`. No local owner for PR bodies: `commit`/`implement` commit only, `nightly-docs-sweep` says "clear title and body". Candidate to adopt as a model-invoked format reference; `nightly-docs-sweep` and `autopilot` deploy gates would point at it. Keep the CREDITS.md pattern.
2. **`retro` coding-standards lens sharpened**: classify a violation as mechanical (fixed pattern, banned API, import shape, file location) → build a deterministic check (linter rule, pre-commit hook, CI job) instead of writing a prose rule; reserve standards docs for judgement calls. Automated-checks lens: read the repo's existing check command first; a repo with no guardrail at all is itself a finding. Local `distill-sessions` lenses 6 and 7 lack both refinements. Cheap to fold in (two sentences each).
3. `link-skills.sh` stops linking `misc/`; CLAUDE.md updated to match. Not applicable: local layout is flat and ships via marketplace.
4. `.agents/*.md` (invocation, writing-docs) unchanged since baseline.

---

## Delta check, 2026-10-05

- Upstream `main` now at `4588b32ecab9ecc9fc8cc6b6c5e7d675b6004b0d` (2026-10-05). 25 non-merge commits since `c55ee46`; 46 files changed outside `docs/`.
- Local `main` at `5304db1`. Neither Sept 22 item landed: no `pr` skill, and `distill-sessions` lenses 6–7 still lack the deterministic-check refinements.

### What changed upstream

1. **`pr`, `retro`, `implement-spec` graduated to `engineering/`.** `pr` is unchanged in substance (model-invoked PR-body template: Summary visual, before/after Evidence, Merge Danger door + blast radius; credits Dex Horthy's `show-me`). `retro` now closes the main flow in `ask-matt`.
2. **`CONTEXT.md` / `CONTEXT-MAP.md` renamed to `GLOSSARY.md` / `GLOSSARY-MAP.md`** across every skill, `CONTEXT-FORMAT.md` → `GLOSSARY-FORMAT.md`. Local still uses `CONTEXT.md` in 51 places across 16 files (`domain-modeling`, `grill-with-docs`, `setup`, `tdd`, `triage`, `to-spec`, `to-tickets`, `diagnosing-bugs`, `wait-what`, `improve-codebase-architecture`, `codebase-design`, `grilling`, `agents/module-designer.md`); `teach` already uses `GLOSSARY-FORMAT.md`, so the collection is internally split.
3. **Post-bug reflection routed to `retro`.** `ask-matt` drops the `diagnosing-bugs` → `improve-codebase-architecture` hand-off: run `/retro` in the same session after the fix; architecture only when the finding is a missing seam. Local `diagnosing-bugs` Phase 6 already recommends (not invokes) the architecture skill; it has no pointer to `distill-sessions`.
4. **`implement-spec`**: whole spec in one run via parallel implementer subagents in worktrees over the ready frontier, merged onto one integration branch, one `code-review` at the end. Local covers this with `implement/references/spec-run.md` (sequential, inline) and `autopilot` (fresh-process loop). Not imported; parallel fan-out is the only new idea.
5. **`resolving-merge-conflicts` removed** ("no longer needed"). Local keeps it; `which-skill` routes to it.
6. **`chief-of-staff`** (in-progress, user-invoked, 25 lines): long-running single session that delegates all work to subagents and suggests schedules. Experimental; no local action.
7. Docs-only: "unslop" pass over docs pages; removed promoted skills keep an archived docs page. Not applicable (no local docs pages).

### Recommended pull

1. Add `pr` as a model-invoked format reference with Laravel/PHP example visuals and a `CREDITS.md`; point `implement/references/spec-run.md` and `fix-github-issues/references/mechanics.md` PR-body lines at it.
2. Fold `retro`'s two refinements into `distill-sessions` lenses 6–7: read the repo's existing check command first; no guardrail is itself a finding; classify mechanical violations → deterministic check, judgement calls → standards doc.
3. Decide the `GLOSSARY.md` rename. If adopted, read `GLOSSARY.md` with `CONTEXT.md` as a legacy fallback so existing project repos keep working.
4. Optional: `diagnosing-bugs` Phase 6 suggests `/distill-sessions` on this session for environment fixes, beside the architecture recommendation.

### Applied, 2026-10-05

All four landed, plus two changes to the recommendation: `distill-sessions` was renamed to `retro` (with a `this` scope for the current session), and `implement-spec` was adopted after all. `autopilot` drives ticketed work through fresh sessions and `implement <spec> all` builds sequentially; neither runs the frontier in parallel. The local version keeps the tracker in the orchestrator, gives each implementer a bootstrapped worktree and its own test database, and cuts tickets first when the spec has none.

---

## Delta check, 2026-10-29

- Upstream `main` now at `a496f5513d4a4cf889bc48e189e579f4b0bdf6aa` (2026-10-29). 37 non-merge commits since `4588b32`; 43 files changed outside `docs/`. No skill added or removed; upstream is now at plugin version 1.3.2 and stops taking new-skill proposals (`SCOPE.md`, `.out-of-scope/`).
- Local `main` at `2dcc8f0`.

### Worth pulling

1. **Codex sub-agents fork the whole conversation by default.** Upstream now tells every dispatching skill to start each sub-agent "with a fresh context window" ([`7739eae`](https://github.com/mattpocock/skills/commit/7739eaed7f8f3915437a8def198a6d0d7206dbc7)). Verified locally against codex-cli 0.165.0: `spawn_agent` takes `fork_turns` (`"none"` or `"all"`), and an omitted `fork_turns` is a full-history fork. The local `AGENTS.md` Codex column says only `spawn_agent`, so every local Codex dispatch (`code-review`, `implement-spec`, `panel`, `research`, `retro`, the triage skills) currently hands its sub-agent the parent's whole transcript, which defeats the reason the sub-agent exists (an independent read). Fix in one place: the `AGENTS.md` table row becomes `spawn_agent` with `fork_turns: "none"`, then `wait_agent`; the table's "verified against Codex CLI 0.160" note moves to 0.165. Skills that name `spawn_agent` inline (`code-review/SKILL.md:72`, `implement-spec/SKILL.md:77`) get the same flag.
2. **`wizard/template.sh` fixes** ([`868c4cf`](https://github.com/mattpocock/skills/commit/868c4cf20cb7e08bc805c388ff1f305dbedd261a), [`49dd158`](https://github.com/mattpocock/skills/commit/49dd158d1076134a641b33efb035946536778336)). The local template has none of them. The ones that matter: `write_env` writes values unquoted, so a secret with a space, `#` or `$` breaks `source .env`; a new `.env` is created at the default umask (world-readable) instead of `0600`; `mv` replaces a symlinked `.env` instead of writing through it; `open_url`'s warning is inside the `>/dev/null` group, so the user never sees it; stages run at top level, so editing the script mid-run can break it (`run_wizard` wrapper). Quoting forces the `_existing` decode fix, or re-runs prefill the quotes. Merge by hand: keep the local `ask KEY "Prompt" DEFAULT` prefill (bash 4+ `read -e -i`, plain fallback for macOS bash 3.2) and add upstream's fail-at-EOF.
3. **`diagnosing-bugs` Phase 5**: after "Watch it fail", when the red was forced by mutating code or a fixture, `diff` against a pristine copy to prove the mutation landed ([`f3fc563`](https://github.com/mattpocock/skills/commit/f3fc5632f401156837ee3872f14fe33ccf1024ea)). Local `skills/diagnosing-bugs/SKILL.md:127` lacks it. One sentence.
4. **`handoff` temp dir**: name it (`$TMPDIR`, else `/tmp`; `%TEMP%` on Windows) ([`4f4e943`](https://github.com/mattpocock/skills/commit/4f4e9433bbb7c4957ef33b1ea26686fb7c2a4cf4)). Local `skills/handoff/SKILL.md:8` is the old wording; `improve-codebase-architecture` already uses the new one.
5. **`teach`**: workspace paths resolve from the directory `/teach` ran in, only `*-FORMAT.md` links from the skill folder; and vary which position holds the correct quiz answer ([`ad5400b`](https://github.com/mattpocock/skills/commit/ad5400b930b297b0c0cb231ff1ffe42a7da666aa)). Local `skills/teach/SKILL.md:12` has neither.
6. **`which-skill`**: read a skill's `SKILL.md` before stating what it does or advising a step be skipped; the route summaries are orientation only ([`954ee7f`](https://github.com/mattpocock/skills/commit/954ee7f)). Local runs on `sonnet`/`low`, which makes stale one-line summaries more likely to be trusted, not less.

### Optional

7. **`tdd` seams**: each proposed seam gets a one-line note on what it catches and what it misses ([`3f59913`](https://github.com/mattpocock/skills/commit/3f599139104dfceabc7754eeb91319802f85e042)). Local already states seams with a one-line *why* (`implement`, `to-spec`); swapping "why" for "catches / misses" is a cheap sharpening.
8. **`setup` legacy rename**: offer to `git mv` a legacy `CONTEXT.md` / `CONTEXT-MAP.md` to its `GLOSSARY` name ([`ed0de59`](https://github.com/mattpocock/skills/commit/ed0de59eb5de8c2730a650cc69f588ffa64c1040)). *Correction on applying: local `setup/SKILL.md` Section C already drafts this rename; nothing to do.*

### Already covered or not applicable

- `code-review` standards search and foreground sub-agents: local already lists `AGENTS.md`, `CONTRIBUTING.md`, `CODING_STANDARDS.md` and colocated rule files (`code-review/SKILL.md:40-47`) and launches foreground sub-agents.
- `implement-spec` "a fresh implementer per ticket": local already runs one named implementer per ticket (`<slug>--<NN>`); only the Codex fork default (item 1) applies.
- `grilling` "word each question so yes accepts the recommendation": local asks through `AskUserQuestion` with the recommendation as the first option, and numbered options in chat; there is no yes/no to misread.
- GitHub/GitLab tracker template fixes, `to-tickets` sub-issues, `wayfinder` label and placeholder-id rules, `implement` ticket fetch: tracker-backend changes; local is Markdown-only under `.scratch/`.
- `chief-of-staff` (still in-progress): now keeps memory in a dated, commit-cited wiki ("write history, not the present"). No local equivalent and no action; the dated-claim rule is worth remembering if a local long-running coordinator appears.
- Repo governance (`SCOPE.md`, `.out-of-scope/`, issue forms, triage workflows, changesets, `install-block`): public-project process. One record conflicts with local by design: upstream refuses the harness's native question tool for grilling; local uses `AskUserQuestion` deliberately. Keep local.

### Recommended pull

One correctness patch: items 1–6. Item 1 first, since it silently changes the behaviour of every Codex sub-agent dispatch. Items 7–8 only if wanted.

### Applied, 2026-10-29

Items 1–7 landed; item 8 was already in place.

- **Codex fork default**: `fork_turns: "none"` is in the `AGENTS.md` table row, with the rule beside it (the verified version is now Codex CLI 0.165), and at the `spawn_agent` dispatch sites. *Correction after a four-CLI panel review of `0e522b9`: that commit missed `implement-spec`'s verifier and every site whose fallback said only "elsewhere, any sub-agent"; a follow-up named Codex at all of them (`browser-test`, `chatter-scout`, `code-smells-audit`, `codebase-design`, `fix-github-issues`, `improve-codebase-architecture`, `resolve-review-comments`, `retro`, `triage-github-pr`, `upgrade-plan`).* `closeout` only names `spawn_agent` in a list of jobs, so it is unchanged.
- **`wizard/template.sh`**: all of upstream's library fixes, merged with the local prefilled `DEFAULT`. `ask` reads with Readline at a terminal on bash 3.2 too, and the prefill still needs bash 4+. Two local deviations from upstream: `RED` stays for stage authors, and `_existing` replaces the escaped quote through a variable, because upstream's `\'` replacement keeps the backslash on macOS `/bin/bash` 3.2. Checked on bash 5 and 3.2: a value with `'`, `#`, `$`, spaces and `"` survives `source .env` and the re-run prefill; a new `.env` is `0600`; writes go through a symlink; `ask` and `ask_secret` return 1 at EOF; `open_url` with no opener shows its warning; the example wizard runs end to end; shellcheck is clean (a file-wide `SC2329` disable covers the helpers a given wizard never calls, now that they sit beside `run_wizard`).
- **`wizard/template.sh`, after the panel review**: the shell-style `'\''` escape broke phpdotenv (it throws) and Node's `parseEnv` (it truncates). `write_env` now single-quotes, double-quotes a value holding `'` and nothing expandable, and refuses (listing the key for the human) a value no quoting carries; phpdotenv, Node and `source` all read both forms back exactly. A line `_existing` cannot read back (escapes, `$`, comments) is kept as is on Enter instead of overwritten. Writes go through a `0600` temp file beside the real target and `mv` into place, following a symlink, cleaned up on failure and on `INT`/`TERM`; an unreadable file or unwritable directory leaves `.env` untouched.
- **`diagnosing-bugs`, `handoff`, `teach`, `which-skill`**: ported as upstream worded them, adapted to local wording.
- **Seams**: `tdd`, `implement` and `to-spec` now state each seam with what it catches and what it misses, instead of a one-line why.
