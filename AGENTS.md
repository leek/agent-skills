# AGENTS.md

Guidance for AI coding agents (Claude Code, Cursor, Copilot, etc.) working in this repository.

## Repository Overview

Personal collection of agent skills. Skills are packaged instructions, scripts, and references that extend agent capabilities.

This repo also doubles as a [Claude Code plugin marketplace](https://docs.claude.com/en/docs/claude-code/plugins) via `.claude-plugin/marketplace.json`.

## Layout

```
.claude-plugin/marketplace.json   # Claude Code plugin manifest
skills/<skill-name>/SKILL.md      # one folder per skill
template/SKILL.md                 # starting point
spec/                             # (optional) skill specs / docs
```

## Creating a New Skill

### 1. Naming

- **Directory**: `kebab-case` (e.g., `vercel-deploy`, `log-monitor`)
- **`SKILL.md`**: exact filename, uppercase
- **Scripts**: `kebab-case.sh`

### 2. Directory structure

```
skills/<skill-name>/
  SKILL.md            # required
  scripts/            # optional — bash scripts (preferred)
    <name>.sh
  references/         # optional — supporting docs read on demand
```

### 3. `SKILL.md` format

```markdown
---
name: <skill-name>
description: One sentence — what it does and when Claude should use it. Include trigger phrases.
---

# <Skill Title>

Brief description of what the skill does.

## How It Works

1. Step one
2. Step two

## Usage

\```bash
bash scripts/<name>.sh [args]
\```

## Output

Example output.

## Troubleshooting

Common issues + fixes.
```

### 4. Register in the marketplace

Add the skill path to `.claude-plugin/marketplace.json` under the `leek-skills` plugin:

```json
"skills": [
  "./skills/<skill-name>"
]
```

### 5. Update the README

Add a short section to `README.md` under **Available Skills**.

## Best Practices

Skills load on-demand — only `name` + `description` load at startup. The full `SKILL.md` loads only when the agent decides the skill is relevant.

- **Keep `SKILL.md` under 500 lines.** Offload detail to sibling files.
- **Write specific descriptions.** Helps the agent match correctly.
- **Progressive disclosure.** Reference supporting files; they load only when read.
- **Prefer scripts over inline code.** Script execution does not consume context — only its stdout does.
- **One level deep.** File references work one level deep from `SKILL.md`.

## Script Requirements

- `#!/bin/bash` shebang
- `set -e` for fail-fast
- Status messages → stderr (`echo "msg" >&2`)
- Machine-readable output (JSON) → stdout
- Cleanup trap for temp files

## Distribution Notes

- Each skill folder is self-contained — users can copy a single `skills/<skill-name>/` into `~/.claude/skills/`.
- Network access for skills running in claude.ai must be allowlisted at `claude.ai/settings/capabilities`.
