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
