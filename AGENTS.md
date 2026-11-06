# AGENTS.md

Guidance for AI coding agents (Claude Code, Cursor, Copilot, Grok, etc.) working in this repository.

## Repository Overview

Personal collection of agent skills. Skills are packaged instructions, scripts, and references that extend agent capabilities across coding agents.

This repo also doubles as a [Claude Code plugin marketplace](https://docs.claude.com/en/docs/claude-code/plugins) via `.claude-plugin/marketplace.json` for Claude Code installs; the skill folders themselves are harness-agnostic.

## Layout

```
.claude-plugin/marketplace.json   # Claude Code plugin manifest
skills/<skill-name>/SKILL.md      # one folder per skill
agents/<agent-name>.md            # Claude Code subagents the skills dispatch (see docs/authoring.md)
hooks/hooks.json                  # Claude Code plugin hooks, each keyed to its agent types, plus the mod module (see docs/authoring.md)
hooks/mods/register.tsx           # the plugin's one Claude Code mod module, pure helpers and tests beside it (see docs/authoring.md)
types/index.d.ts                  # the mod's $.state contract
hooks/*.py                        # guard scripts shared by more than one skill, with their tests
hooks/bare-worktree-notice.sh     # SessionStart notice for a bare Laravel worktree (see Worktrees)
hooks/terminal-bell.sh            # Ghostty-only bell when Claude asks a question or waits on the user
template/SKILL.md.example         # starting point; renamed so installers do not treat it as a real skill
```

## Authoring

Before you add or change a skill, a subagent in `agents/`, or the mod in `hooks/mods/`, read [docs/authoring.md](docs/authoring.md): naming, directory layout and `agents/openai.yaml`, frontmatter and invocation policy, marketplace and README registration, subagent rules, and mod rules. CI (`scripts/verify-skills-collection.sh`) enforces most of it.

## Worktrees

Six kinds of skill create a worktree: `triage-github-pr` and `fix-ci-failures` (dirty-tree recipes), `fix-github-issues` (every run), `to-spec` (briefly, to commit a spec on its own branch), `implement` (PR delivery), `implement-spec` (one per implementer), and `sweep` (one per cycle). Each one bootstraps, registers databases, removes, and asks about leftovers only through [`laravel-herd-worktrees`](skills/laravel-herd-worktrees/SKILL.md) (**Bootstrap a bare worktree**, **Remove a served worktree**, **Scratch database registry**), never with git's `--force` and never on anything its run did not create. A new worktree-creating skill points there rather than restating the recipe. Anything left over is `repository-cleanup`'s, which removes only what the user selects. `hooks/bare-worktree-notice.sh` only points a bare Laravel worktree session at the bootstrap: no plugin hook can run it (`WorktreeCreate` is not plugin-registrable, and `SubagentStart` carries no working directory).

## Best Practices

**How to write one is the `writing-for-agents` skill**: it is model-invoked, so reach for it rather than working from this file. Only what is specific to *this repo* lives here:

- **Where the shared protocols live.** A protocol several skills need has exactly one owner, and the others point at it: the question shape and STE rules in `grilling`, tracker operations in `setup`'s seeds, the end-of-session banner in `wayfinder/references/pipeline-end-block.md`, the ticket board in `wayfinder/references/ticket-board.md`, and each harness's sub-agent and question tools in `harness-tools`.
- **Status marks in chat reports.** Four marks, used sparingly so a report scans fast: ✅ done, passed, or fixed · ❌ failed · ⚠️ needs the user (blocked, unsure, a risk, kept for a decision) · 👉 the next step.
- **Questions in chat.** Any question that needs the user's decision goes through the structured question ([harness-tools](skills/harness-tools/SKILL.md)), never as chat text. A `⚠️ Needs you: <text>` line is rare: only for an important side note, or an optional question the run does not need answered, last in the reply after a `---` line, at most two, never inside a code block. Most replies have none, and an unanswered one is not asked again.
- **Mark placement.** One mark at the start of a status line or verdict cell, in front of the plain word, which stays (`✅ fixed in abc123`), so nothing that reads the word breaks. No marks in headings, prose, or lines with no status. Chat only: never in files a skill writes, commits, PR bodies, tracker or GitHub comments, `ReportFindings` fields, subagent reports, or script output. Each skill that uses them says which, in one line beside its report format.
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

- Skills in this repo cross-link freely via `../<skill>/` pointers so shared protocols, templates, and references live in one place. Install the repo as a collection (or copy any linked target along with a standalone skill). The pipeline skills share one end-of-session banner, `wayfinder/references/pipeline-end-block.md`, rather than eight copies of it; the verifier asserts that file exists and that the pipeline skills still point at it.
- Network access for skills running in claude.ai must be allowlisted at `claude.ai/settings/capabilities`.
