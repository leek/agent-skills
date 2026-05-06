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
