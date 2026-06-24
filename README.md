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

### weekly-composer-dependency-audit

Run a weekly Composer dependency audit for PHP projects. Checks outdated direct dependencies, runs `composer audit`, groups updates by risk, and produces a safe upgrade summary.

**Use when:**

- Auditing Composer or PHP dependencies
- "Run composer audit", "check outdated Composer packages", "review Laravel package upgrades"
- Planning safe PHP dependency upgrades without applying changes yet

### grill-me-plus

Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree. Uses Claude Code's `AskUserQuestion` or Codex's `request_user_input` when available, with tool-specific schemas, recommended options, trade-offs, and fallbacks.

**Use when:**

- Stress-testing a plan or design before building
- "Grill me on this", "poke holes in my approach", "interview me about this plan"
- Resolving interdependent design decisions one branch at a time in Claude Code, Codex, or chat fallback

### housekeeper

Run a conservative code-project housekeeping pass. Finds one proven low-risk cleanup at a time, makes the smallest coherent change, verifies behavior, and defers uncertain or approval-required candidates.

**Use when:**

- Cleaning dead code, stale files or comments, unused dependencies, duplicated logic, broken links, inconsistent names, or confusing structure
- "Run housekeeper", "run the housekeeper loop", "do a safe repository cleanup", "find low-risk cleanup opportunities"
- Improving project hygiene while protecting unrelated, uncommitted, generated, active, or uncertain work

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
