# Agent Skills

Personal collection of agent skills for coding agents (Claude Code, Cursor, Grok, and others).

Skills follow the [Agent Skills](https://agentskills.io/) format.

[![skills.sh](https://skills.sh/b/leek/agent-skills)](https://skills.sh/leek/agent-skills)

## Available Skills

Skills marked **user** are user-invoked only (`/name`); the rest the agent can reach for on its own. Many are adapted from [Matt Pocock's skills](https://github.com/mattpocock/skills), tuned for Laravel/PHP repos.

The engineering pipeline is one straight line — **decide → spec → tickets → build** — over one directory per effort:

```
.scratch/<slug>/
  map.md        # /wayfinder  — the decisions (skip it for small, clear work)
  decisions/    # /wayfinder  — one file per decision ticket
  spec.md       # /to-spec    — exactly one, written once
  issues/       # /to-tickets — one file per build ticket
```

`/implement` then builds one file from `issues/` per fresh session. `triage` is the other on-ramp. There is no external issue tracker — every artifact is a markdown file.

| Skill | Invocation | What it does |
|---|---|---|
| `architecture-satisfaction` | user | Run a bounded architectural refactor loop. |
| `autopilot` | user | Drive an existing wayfinder map, spec, or set of tickets to completion through fresh top-level Claude Code or Codex sessions. |
| `code-review` | model | Review the changes since a fixed point (commit, branch, tag, or merge-base) along two axes — Standards (does the diff follow this repo's documented conventions, including colocated CLAUDE.md rules?) and Spec (does it implement what the originating ticket/PRD asked?). |
| `code-smells-audit` | model | Audit a codebase, path, glob, or branch diff for classic code smells using the 56-smell Luzkan catalog, with detection heuristics tuned to PHP/Laravel and TS/React — sweep nine occurrence lenses, adversarially verify every candidate against the smell's card definition, emit a ranked markdown findings report. |
| `codebase-design` | model | Shared vocabulary for designing deep modules in a PHP/Laravel codebase. |
| `commit` | user | Commit the work done in this session, skipping files a parallel session also touched. |
| `dependency-audit` | user | Run a weekly Composer or npm dependency audit and propose a safe upgrade plan. |
| `diagnosing-bugs` | model | Diagnosis loop for hard bugs and performance regressions. |
| `distill-sessions` | user | Mine your recent AI-coding session logs (Claude Code + OpenAI Codex) for reusable patterns — corrections you gave, commands that errored or were retried, setup steps rediscovered across sessions, and content-worthy moments — then propose where each belongs (CLAUDE.md/AGENTS.md line, slash command/skill, hook, tool fix, config change, or content idea). |
| `domain-modeling` | model | Build and sharpen a project's domain model — challenge terms against the glossary, resolve fuzzy language, stress-test concepts with concrete scenarios, and record CONTEXT.md entries and ADRs the moment decisions land. |
| `grill-me` | user | Run a grilling session — the user wants their plan, decision, or idea stress-tested one question at a time. |
| `grill-with-docs` | user | Run a grilling session with domain-modeling alongside, capturing terms in CONTEXT.md and decisions as ADRs while they land. |
| `grilling` | model | Interview the user one decision at a time until reaching shared understanding, resolving each branch of the decision tree with recommended options and trade-offs. |
| `handoff` | user | Compact the current conversation into a handoff document for another agent to pick up. |
| `housekeeper` | user | Run a conservative code-project housekeeping pass. |
| `implement` | user | Implement one Laravel work item end to end — scope and claim it when trackable, TDD at agreed seams, commit, review, verify, and resolve it. |
| `improve-codebase-architecture` | user | Scan a codebase for deepening opportunities, present them as a visual HTML report, then grill through whichever one you pick. |
| `laravel-herd-worktrees` | model | Use when working with Laravel projects served by Laravel Herd alongside git worktrees on macOS. |
| `nightly-docs-sweep` | user | Run a documentation sweep for a codebase. |
| `panel` | user | Convene a panel of agent CLIs (grok, claude, codex, agy) on a prompt or a code review, each in its own headless subagent, then report one consensus grouped by how much they agree. |
| `prototype` | model | Build a throwaway prototype to answer a design question. |
| `repository-cleanup` | user | Audit and clean Git repository state. |
| `research` | model | Investigate a question against high-trust primary sources and capture the findings as a cited Markdown file. |
| `resolve-review-comments` | model | Triage, fix or rebut, then reply-and-resolve every review comment on a PR (including AI-review bot findings). |
| `resolving-merge-conflicts` | model | "Use when you need to resolve an in-progress git merge/rebase conflict." |
| `setup` | user | Configure this repo for the engineering skills — the markdown issue tracker layout, triage label vocabulary, and domain doc layout. |
| `tdd` | model | The red → green loop tuned for Pest/PHPUnit in a Laravel codebase — seams, what a good test is, and the anti-patterns to refuse. |
| `teach` | user | Teach the user a new skill or concept, within this workspace. |
| `to-questionnaire` | user | Turn a decision the user can't fully answer into a Markdown questionnaire for someone else to fill in, async or over a meeting. |
| `to-spec` | user | Turn the current conversation into a spec (PRD) and save it as markdown under .scratch/ — no interview, just synthesis, with Laravel test seams chosen from the tdd ranking rules rather than asked about. |
| `to-tickets` | user | Break a spec into tracer-bullet vertical-slice tickets with explicit blocking edges, take one green light on the breakdown, and save one markdown file per ticket beside the spec. |
| `triage` | user | Move issues and external PRs through a state machine of triage roles — categorise, verify, grill if needed, and write agent-ready briefs. |
| `verify` | model | Exercise a change end to end in the running application — hit the route, run the command, click through the page — and report what actually happened. |
| `wayfinder` | user | Plan work too big for one agent session as a map of decision tickets in markdown under .scratch/, then resolve them one per session until the route to the destination is clear. |
| `writing-great-skills` | user | Reference for writing and editing skills well — the vocabulary and principles that make a skill predictable. |

## Installation

### `npx skills` (any agent)

Install the whole collection:

```bash
npx skills add leek/agent-skills
```

Install a single skill:

```bash
npx skills add https://github.com/leek/agent-skills --skill code-review
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
2. Fill in `SKILL.md` — follow the authoring principles in AGENTS.md and the writing-great-skills skill.
3. Add the skill to `.claude-plugin/marketplace.json` under the `leek-skills` plugin.
4. Update the **Available Skills** section above.
5. Open a PR.

## License

MIT
