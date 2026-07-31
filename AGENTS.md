# AGENTS.md

Guidance for AI coding agents (Claude Code, Cursor, Copilot, etc.) working in this repository.

## Repository Overview

Personal collection of agent skills. Skills are packaged instructions, scripts, and references that extend agent capabilities.

This repo also doubles as a [Claude Code plugin marketplace](https://docs.claude.com/en/docs/claude-code/plugins) via `.claude-plugin/marketplace.json`.

## Layout

```
.claude-plugin/marketplace.json   # Claude Code plugin manifest
skills/<skill-name>/SKILL.md      # one folder per skill
template/SKILL.md.example         # starting point; renamed so installers do not treat it as a real skill
spec/                             # (optional) skill specs / docs
```

## Creating a New Skill

Start from the example template:

```bash
mkdir -p skills/<skill-name>
cp template/SKILL.md.example skills/<skill-name>/SKILL.md
```

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
description: <see invocation policy below>
disable-model-invocation: true   # only on user-invoked flows
---

# <Skill Title>

What the skill does and the rules that make it predictable. Ordered steps for
processes (each ending on a checkable completion criterion); flat reference
sections for material consulted on demand; anything only some runs need goes
behind a pointer to a file in references/.
```

**Invocation policy** — decide it per skill, deliberately:

- **Model-invoked** (default): the agent may reach for it autonomously, and other skills can invoke it. The `description` pays for itself in every context window, so it earns rich trigger phrasing — but **one trigger per branch**; synonyms restating the same branch are duplication.
- **User-invoked** (`disable-model-invocation: true`): for flows with side effects (publishing issues, committing, interviewing the user) or that only make sense when the human asks. The `description` becomes a human-facing one-liner — no trigger lists.

The test: *could the model usefully reach for this on its own?* Reuse by other skills is a reason to keep it model-invoked; being a big deliberate workflow is a reason not to.

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

Skills load on-demand — only `name` + `description` load at startup. The full `SKILL.md` loads only when the agent decides the skill is relevant. A skill exists to wrangle determinism out of a stochastic system: the same *process* every run. Everything below serves that. (The full authoring reference is the `writing-great-skills` skill.)

- **Short beats complete.** Most upstream skills this repo ports from are 10–130 lines. Prune sentence-by-sentence: when one part of a sentence is a no-op, delete the whole sentence. Length that restates what the model already holds (via leading words like *seam*, *frontier*, *red → green*) is sediment.
- **One job per skill.** Same lifecycle, different entity → one skill. A skill doing an interview *and* tool plumbing *and* session routing is three skills.
- **Single source of truth.** A protocol referenced by several skills lives in exactly one (e.g. the question shape in `grilling`, tracker operations in `setup`'s seeds) — others point at it, never restate it.
- **Progressive disclosure.** Inline what every run needs; push what only some runs need behind a pointer to `references/`. File references work one level deep from `SKILL.md`.
- **Prefer scripts over inline code.** Script execution does not consume context — only its stdout does.
- **No dead references.** Every skill a skill mentions must exist in this repo (or be a documented harness built-in). Check before committing.

## Script Requirements

- `#!/bin/bash` shebang
- `set -e` for fail-fast
- Status messages → stderr (`echo "msg" >&2`)
- Machine-readable output (JSON) → stdout
- Cleanup trap for temp files

## Distribution Notes

- Each skill folder is self-contained — users can copy a single `skills/<skill-name>/` into `~/.claude/skills/`.
- Network access for skills running in claude.ai must be allowlisted at `claude.ai/settings/capabilities`.
