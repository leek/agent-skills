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

### grill-me-claude

Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree. Every question is posed through the `AskUserQuestion` tool — click-to-answer, with a recommended option leading each prompt.

**Use when:**

- Stress-testing a plan or design before building
- "Grill me on this", "poke holes in my approach", "interview me about this plan"
- Resolving interdependent design decisions one branch at a time

### laravel-herd-worktrees

Run multiple branches of a Laravel project in parallel via git worktrees, each served by Laravel Herd at its own `*.test` URL. Helper scripts handle worktree creation, `.env` rewrites (`APP_URL`, DB, cache/session/redis prefixes), per-worktree DB provisioning, dependency install, and clean teardown. Includes Herd CLI reference, isolation rationale, and DB strategy guide.

**Use when:**

- Creating a worktree for a Laravel app served by Herd
- Debugging cross-branch `.env`/cache/session/DB collisions
- Wanting per-branch URLs like `myapp-feat.test` without manual config
- Running the same Laravel project on multiple PHP versions simultaneously

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

See [`template/SKILL.md`](./template/SKILL.md) for a starting point and [`AGENTS.md`](./AGENTS.md) for full conventions.

## Creating a Skill

1. Copy `template/` to `skills/<skill-name>/`.
2. Fill in `SKILL.md` — keep it under 500 lines; offload reference material to sibling files.
3. Add the skill to `.claude-plugin/marketplace.json` under the `leek-skills` plugin.
4. Update the **Available Skills** section above.
5. Open a PR.

## License

MIT
