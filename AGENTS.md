# AGENTS.md

Guidance for AI coding agents (Claude Code, Cursor, Copilot, Grok, etc.) working in this repository.

## Repository Overview

Personal collection of agent skills. Skills are packaged instructions, scripts, and references that extend agent capabilities across coding agents.

This repo also doubles as a [Claude Code plugin marketplace](https://docs.claude.com/en/docs/claude-code/plugins) via `.claude-plugin/marketplace.json` for Claude Code installs; the skill folders themselves are harness-agnostic.

## Layout

```
.claude-plugin/marketplace.json   # Claude Code plugin manifest
skills/<skill-name>/SKILL.md      # one folder per skill
agents/<agent-name>.md            # Claude Code subagents the skills dispatch (see Subagents)
template/SKILL.md.example         # starting point; renamed so installers do not treat it as a real skill
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
  agents/openai.yaml  # required: Codex-facing metadata (see below)
  scripts/            # optional: bash scripts (preferred)
    <name>.sh
  references/         # optional: supporting docs read on demand
  *.md                # optional: skill-root companions (formats, seeds, short branch docs)
```

**Harness metadata.** `SKILL.md` frontmatter is what Claude Code and `npx skills` read; `agents/openai.yaml` is the same two facts for Codex:

```yaml
interface:
  display_name: "Which Skill"
  short_description: "Not sure which skill to reach for? Name the situation and get routed to one"
policy:
  allow_implicit_invocation: false   # must be the inverse of disable-model-invocation
```

CI fails if a skill is missing the file or the two disagree. Keep the skill bodies themselves harness-neutral: name a specific tool only with a stated fallback ("`AskUserQuestion` where available, otherwise ask in chat"), since an instruction naming a tool the running harness lacks is unfollowable, not merely unused.

**Companion files.** Prefer `references/` for material only some runs need. Skill-root `.md` companions (one level deep from `SKILL.md`) are allowed for formats, setup seeds, and short branch docs that every related path may open: e.g. `setup/issue-tracker.md`, `teach/MISSION-FORMAT.md`, `prototype/LOGIC.md`. Do not nest companions more than one level below `SKILL.md`.

### 3. `SKILL.md` format

```markdown
---
name: <skill-name>
description: <see invocation policy below>
disable-model-invocation: true   # only on user-invoked flows
argument-hint: "What the user passes"   # optional, see below
---

# <Skill Title>

What the skill does and the rules that make it predictable. Ordered steps for
processes (each ending on a checkable completion criterion); flat reference
sections for material consulted on demand; anything only some runs need goes
behind a pointer to a companion file or references/.
```

**Invocation policy**: decide it per skill, deliberately:

- **Model-invoked** (default): the agent may reach for it autonomously, and other skills can invoke it. The `description` pays for itself in every context window, so it earns rich trigger phrasing, but **one trigger per branch**; synonyms restating the same branch are duplication.
- **User-invoked** (`disable-model-invocation: true`): for flows with side effects (publishing issues, committing, interviewing the user) or that only make sense when the human asks. The `description` becomes a human-facing one-liner, no trigger lists.

The test: *could the model usefully reach for this on its own?* Reuse by other skills is a reason to keep it model-invoked; being a big deliberate workflow is a reason not to.

**Optional Claude Code fields.** Other harnesses ignore unknown frontmatter, so these cost nothing elsewhere. Full list: [frontmatter reference](https://code.claude.com/docs/en/skills#frontmatter-reference). Use the ones that carry a real fact about the skill:

- `argument-hint`: on any skill that takes input. Say what the input is, and what happens when it is omitted.
- `allowed-tools`: pre-approve only the commands the skill exists to run (`commit` → `git add/commit`, `research` → `WebFetch WebSearch`). Deny rules in settings still win. Never pre-approve a destructive command the body says to ask about first.
- `user-invocable: false`: for a protocol other skills run that has its own user front door (`grilling` behind `grill-me`). It hides the `/` entry; the model can still invoke it.
- `compatibility`: environment the skill cannot run without (Herd on macOS, a CLI on PATH). Documentation only.
- `model` / `effort`: only on one-turn, user-invoked skills whose work is mechanical (`which-skill`, `wait-what`, `commit`, `panel`). The override lasts the rest of the turn, so never on a skill other skills chain into, and never on interviews. For a `context: fork` skill, put them on the agent file instead.
- `context: fork` + `agent: leek-skills:<name>` + `background: false`: only on a skill whose body is the whole task and never needs the conversation (`research`, `dependency-audit`). Everything else reads the conversation and stays inline; see Subagents below.
- Not adopted, on purpose: `when_to_use` (Codex and `npx skills` read only `description`, so triggers stay there), `paths`/`hooks` (no skill has a fact that needs them yet).

Note `disable-model-invocation: true` also stops a skill running when a Claude Code scheduled task fires with the skill as its prompt. The loop skills (`dependency-audit`, `nightly-docs-sweep`) are driven by user-typed `/loop`, which is unaffected.

**The invariant that follows: a user-invoked skill can never be reached by another skill**, not by name, not through any harness's skill-invocation tool. A skill that tells the agent to invoke one is broken; have it *recommend* the flow to the user instead. Shared reference two user-invoked skills both need can live in neither, so it goes in a file they both point at.

### 4. Register in the marketplace

Add the skill path to `.claude-plugin/marketplace.json` under the `leek-skills` plugin:

```json
"skills": [
  "./skills/<skill-name>"
]
```

### 5. Update the README

Add a short section to `README.md` under **Available Skills**.

## Subagents (`agents/`)

`agents/<name>.md` at the repo root are [Claude Code subagent definitions](https://code.claude.com/docs/en/sub-agents). They are **typed shells for work the skills already delegate**: read-only tool sets, a cheaper model where the thinking happens elsewhere, preloaded vocabulary via `skills:`, and cross-session `memory:`. Claude Code loads them as `leek-skills:<name>`; every other harness never sees the directory.

Rules:

- **Skills stay the source of truth and stay harness-neutral.** A skill names its agent as the Claude Code branch of an existing "if the harness has sub-agents … otherwise inline" sentence, never as the only path. The verifier fails a skill that names an agent without a fallback clause.
- **Agents carry no procedure of their own.** An agent body states its role, its standing rules (read-only, output shape), and how to use its memory; the brief it receives from the skill is the task. The exception is a skill with `context: fork`, whose SKILL.md body *is* the prompt: keep that body an actionable task, not guidelines.
- **Reference by scoped name** (`leek-skills:module-designer`), both in `subagent_type` and in a skill's `agent:` field. Preloaded skills are scoped too (`skills: [leek-skills:codebase-design]`), and only model-invoked skills can be preloaded.
- **`tools:` takes bare tool names**, not permission patterns; scope Bash with the skill's `allowed-tools` instead. Plugin agents cannot set `hooks`, `mcpServers`, or `permissionMode`.
- **Extra frontmatter is safe** (verified: Codex's `SkillFrontmatter` has no `deny_unknown_fields`, `npx skills` copies SKILL.md verbatim, Grok reads Claude skills as-is). `context: fork` therefore changes only Claude Code, where the body runs in the named agent with `$ARGUMENTS` but without the conversation.
- **`.claude-plugin/plugin.json` pins the plugin name** so agents namespace as `leek-skills:` under `--plugin-dir` as well as a marketplace install; the version stays in `marketplace.json` only.
- `memory: project` writes under the *target* repo's `.claude/`; say so in the skill when the agent uses it.

## Best Practices

**How to write one is the `writing-for-agents` skill**: it is model-invoked, so reach for it rather than working from this file. Only what is specific to *this repo* lives here:

- **Where the shared protocols live.** A protocol several skills need has exactly one owner, and the others point at it: the question shape and STE rules in `grilling`, tracker operations in `setup`'s seeds, the end-of-session banner in `wayfinder/references/pipeline-end-block.md`.
- **Length.** Most skills here are 10–130 lines. Treat anything longer as owing an explanation.
- **Prefer scripts over inline code.** Script execution does not consume context: only its stdout does.
- **No dead references.** Every skill a skill mentions must exist in this repo (or be a documented harness built-in). Check before committing.

## Script Requirements

- `#!/bin/bash` shebang
- `set -e` for fail-fast
- Status messages → stderr (`echo "msg" >&2`)
- Machine-readable output (JSON) → stdout
- Cleanup trap for temp files

## Distribution Notes

- Each skill folder is self-contained: users can copy a single `skills/<skill-name>/` into their agent's skills directory (e.g. `~/.claude/skills/`, or the equivalent for their harness).
- **One documented exception:** the pipeline skills (`grill-me`, `wayfinder`, `to-spec`, `to-tickets`, `implement`, `to-questionnaire`, `code-review`) are one unit, not seven. They read each other's artifacts under `.scratch/<slug>/` and share the end-of-session banner in `wayfinder/references/pipeline-end-block.md` via a `../` reference. Copying one alone leaves that pointer dangling. Install the set, or accept that nothing depends on the banner and the skill still runs. Duplicating the banner into all seven would cost more than the caveat does; the verifier asserts the shared pointer stays in place.
- Network access for skills running in claude.ai must be allowlisted at `claude.ai/settings/capabilities`.
