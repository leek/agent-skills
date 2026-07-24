# Agent Skills

Personal collection of agent skills for Claude Code, claude.ai, and the Claude API.

Skills follow the [Agent Skills](https://agentskills.io/) format.

[![skills.sh](https://skills.sh/b/leek/agent-skills)](https://skills.sh/leek/agent-skills)

## Available Skills

### aws-cli

Run AWS CLI commands safely. Enforces identity verification, scoped queries with JMESPath, region/profile hygiene, and confirmation gates on destructive ops. Includes per-service references for S3, EC2, IAM, Lambda, and CloudWatch Logs.

**Use when:**

- Invoking `aws ...` for any service
- "List S3 buckets", "describe EC2 instances", "tail Lambda logs", "what AWS account am I in"
- Reviewing or proposing AWS infrastructure changes from the CLI

### architecture-satisfaction

Run a bounded architectural refactor loop. Defines what satisfactory means, makes one reviewable architecture change at a time, live-tests affected behavior, runs an independent review, commits verified checkpoints, and records progress in `/tmp/refactor-{projectname}.md`.

**Use when:**

- Refactoring toward a stated architecture or untangling module boundaries
- Fixing dependency direction, code organization, or long-running architectural drift
- "Refactor until the architecture is right", "run the architecture satisfaction loop", "checkpoint this refactor as we go"

### weekly-composer-dependency-audit

Run a weekly Composer dependency audit for PHP projects. Checks outdated direct dependencies, runs `composer audit`, groups updates by risk, and produces a safe upgrade summary.

**Use when:**

- Auditing Composer or PHP dependencies
- "Run composer audit", "check outdated Composer packages", "review Laravel package upgrades"
- Planning safe PHP dependency upgrades without applying changes yet

### grill-me-plus

Interview the user relentlessly about a plan, decision, or idea until reaching shared understanding, resolving each branch of the decision tree. Uses Claude Code's `AskUserQuestion` or Codex's `request_user_input` when available, with tool-specific schemas, recommended options, trade-offs, and fallbacks.

**Use when:**

- Stress-testing a plan, decision, or idea before acting
- "Grill me on this", "poke holes in my approach", "interview me about this plan"
- Resolving interdependent design decisions one branch at a time in Claude Code, Codex, or chat fallback

### to-questionnaire-plus

Turn a decision the user can't fully answer into a Markdown questionnaire for someone else to fill in, async or over a meeting. Grills the send (who it goes to, what's needed back) via `AskUserQuestion`, then writes discovery questions aimed at the gap between what the recipient knows and what the user needs. Adapted from [Matt Pocock's to-questionnaire](https://github.com/mattpocock/skills).

**Use when:**

- A grilling branch is blocked on knowledge someone else holds
- "To questionnaire", "draft questions for the vendor", "what should I ask compliance"
- Pulling decisions or facts out of a stakeholder, vendor, or compliance contact

### domain-modeling-plus

Build and sharpen a project's domain model as you design — challenge terms against the `CONTEXT.md` glossary, resolve fuzzy language via `AskUserQuestion`, stress-test concepts with concrete scenarios, cross-reference terms against the Laravel codebase (models, enums, migrations, Filament labels), and record glossary entries and ADRs the moment decisions land.

**Use when:**

- Pinning down domain terminology or a ubiquitous language
- Recording an architectural decision worth an ADR
- Running alongside `grill-me-plus`, `wayfinder-plus`, or `to-spec-plus` sessions where terms get decided

### codebase-design-plus

Shared vocabulary for designing deep modules in a PHP/Laravel codebase — module, interface, seam, adapter, depth, leverage, locality — with a Laravel mapping (container bindings, framework fakes, actions over Eloquent), a deepening playbook by dependency category, and a design-it-twice parallel sub-agent pattern.

**Use when:**

- Designing or improving a class or module's interface
- Deciding where a seam goes or whether a container binding is justified
- Finding deepening opportunities or exploring alternative interfaces with parallel sub-agents

### wayfinder-plus

Plan work too big for one agent session as a shared map of decision tickets on the project's issue tracker (GitHub, Linear, or local markdown), then resolve them one per session — grilling, research, prototype, or task tickets — until the route to the destination is clear. Adapted from [Matt Pocock's wayfinder](https://github.com/mattpocock/skills) with fast-path tracker resolution, `grill-me-plus` integration, parallel `research-plus` subagents, and Laravel-flavored prototypes.

**Use when:**

- A loose idea is too large or foggy to spec in one sitting
- "Chart a map", "run wayfinder", "work the map", "take the next frontier ticket"
- Coordinating multi-session planning where humans and agents share one tracker

### research-plus

Investigate a question against high-trust primary sources — official docs, package source, specs, first-party APIs — and capture the findings as a cited Markdown file. Runs as a background subagent so the main session keeps working; prefers Laravel Boost's `search-docs` for framework and package questions. Resolves `wayfinder-plus` research tickets on throwaway `research/<slug>` branches.

**Use when:**

- Delegating reading legwork to a background agent
- "Research this", "check the docs for", "does package X support Y"
- Burning down `wayfinder-plus` research tickets in parallel

### to-spec-plus

Turn the current conversation into a spec (PRD) and publish it to the project's issue tracker — no interview, just synthesis of what was already discussed. Proposes Laravel test seams (HTTP, Livewire/Filament, command, job, action, model) and confirms them via `AskUserQuestion` before writing.

**Use when:**

- A grilling session is done and needs a durable artifact
- "Write this up as a spec", "to spec", "turn this into a PRD"
- Publishing a `ready-for-agent` spec issue for later implementation

### to-tickets-plus

Break a plan, spec, or conversation into tracer-bullet vertical-slice tickets with explicit blocking edges — Laravel slices cut migration → model → behavior → route → feature test. Approves granularity and edges via `AskUserQuestion`, sequences wide refactors as expand–contract, and publishes blockers-first to GitHub, Linear, or local markdown.

**Use when:**

- Slicing a spec into implementable, demoable tickets
- "Break this into tickets", "to tickets", "create the issues for this plan"
- Sequencing a wide refactor (column rename, shared type change) safely

### implement-plus

Implement one ticket or spec end to end in a Laravel codebase: claim it, TDD at pre-agreed seams with Pest/PHPUnit, run static analysis and Pint, review on two axes (standards + spec), verify the real flow, commit with explicit staging, and close the ticket. Includes a Laravel TDD reference (seam ladder, factories, fakes, anti-patterns).

**Use when:**

- Implementing a `ready-for-agent` ticket or an approved spec
- "Implement this ticket", "work the next frontier ticket", "build this spec"
- Working one vertical slice per session with a clean context between slices

### housekeeper

Run a conservative code-project housekeeping pass. Finds one proven low-risk cleanup at a time, makes the smallest coherent change, verifies behavior, and defers uncertain or approval-required candidates.

**Use when:**

- Cleaning dead code, stale files or comments, unused dependencies, duplicated logic, broken links, inconsistent names, or confusing structure
- "Run housekeeper", "run the housekeeper loop", "do a safe repository cleanup", "find low-risk cleanup opportunities"
- Improving project hygiene while protecting unrelated, uncommitted, generated, active, or uncertain work

### repository-cleanup

Audit and clean Git repository state. Inventories branches, pull requests, commits, stashes, and worktrees; recovers valuable work; removes only proven stale state; and repeats until remaining repo state is intentional.

**Use when:**

- Cleaning stale local or remote branches, old pull requests, unmerged commits, forgotten stashes, or obsolete worktrees
- "Run repository cleanup", "clean up old branches", "audit worktrees", "recover abandoned branch work"
- Organizing Git state while protecting uncommitted changes, unpushed commits, dirty worktrees, and uncertain ownership

### laravel-herd-worktrees

Run multiple branches of a Laravel project in parallel via git worktrees, each served by Laravel Herd at its own `*.test` URL. Helper scripts handle worktree creation, `.env` rewrites (`APP_URL`, DB, cache/session/redis prefixes), per-worktree DB provisioning, dependency install, and clean teardown. Includes Herd CLI reference, isolation rationale, and DB strategy guide.

**Use when:**

- Creating a worktree for a Laravel app served by Herd
- Debugging cross-branch `.env`/cache/session/DB collisions
- Wanting per-branch URLs like `myapp-feat.test` without manual config
- Running the same Laravel project on multiple PHP versions simultaneously

### weekly-npm-dependency-audit

Run a weekly npm dependency audit for JavaScript and TypeScript projects. Checks outdated npm packages, runs `npm audit` when lockfile data is available, groups updates by risk, and produces a safe upgrade summary.

**Use when:**

- Auditing npm, JavaScript, or TypeScript dependencies
- "Run npm audit", "check outdated npm packages", "review package.json upgrades"
- Planning safe npm dependency upgrades without applying changes yet

### nightly-docs-sweep

Run a documentation sweep for a codebase. Compares docs against the current implementation, updates stale material, verifies commands and examples, and leaves a reviewable change set or pull request.

**Use when:**

- Auditing documentation drift after implementation changes
- Refreshing READMEs, setup guides, API references, examples, architecture notes, or runbooks
- "Run an overnight docs sweep", "make docs match the code", "open a docs cleanup PR"

## Installation

### `npx skills` (any agent)

Install the whole collection:

```bash
npx skills add leek/agent-skills
```

Install a single skill:

```bash
npx skills add https://github.com/leek/agent-skills --skill aws-cli
```

Re-run either command to update.

### Claude Code (plugin marketplace)

```
/plugin marketplace add leek/agent-skills
/plugin install leek-skills@leek-agent-skills
```

### Claude Code (manual copy)

```bash
cp -r skills/<skill-name> ~/.claude/skills/
```

### claude.ai

Upload the skill folder via [skill settings](https://support.claude.com/en/articles/12512180-using-skills-in-claude), or paste the `SKILL.md` contents into a project's knowledge.

### Claude API

See the [Skills API Quickstart](https://docs.claude.com/en/api/skills-guide#creating-a-skill).

## Skill Structure

Each skill is a folder under `skills/`:

```
skills/
  <skill-name>/
    SKILL.md         # required — frontmatter + instructions
    scripts/         # optional — helper scripts
    references/      # optional — supporting docs
```

The `SKILL.md` frontmatter requires only two fields:

```markdown
---
name: my-skill
description: One sentence — what it does and when Claude should use it.
---

# My Skill

Instructions here.
```

See [`template/SKILL.md.example`](./template/SKILL.md.example) for a starting point and [`AGENTS.md`](./AGENTS.md) for full conventions.

## Creating a Skill

1. Copy `template/SKILL.md.example` to `skills/<skill-name>/SKILL.md`.
2. Fill in `SKILL.md` — keep it under 500 lines; offload reference material to sibling files.
3. Add the skill to `.claude-plugin/marketplace.json` under the `leek-skills` plugin.
4. Update the **Available Skills** section above.
5. Open a PR.

## License

MIT
