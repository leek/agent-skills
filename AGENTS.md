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
hooks/hooks.json                  # Claude Code plugin hooks, each keyed to its agent types (see Subagents), plus the mod module (see Mods)
hooks/mods/register.tsx           # the plugin's one Claude Code mod module, pure helpers and tests beside it (see Mods)
types/index.d.ts                  # the mod's $.state contract
hooks/*.py                        # guard scripts shared by more than one skill, with their tests
hooks/bare-worktree-notice.sh     # SessionStart notice for a bare Laravel worktree (see Worktrees)
hooks/terminal-bell.sh            # Ghostty-only bell when Claude asks a question or waits on the user
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

CI fails if a skill is missing the file or the two disagree.

**Use what the harness offers; degrade gracefully.** Every skill must *run* in any harness, but that is a floor, not a ceiling: never drop a harness-specific feature (a Claude Code subagent, mod, hook, or tool) just because other harnesses lack it. Name it with a stated fallback ("`AskUserQuestion` where available, otherwise ask in chat"), since an instruction naming a tool the running harness lacks is unfollowable, not merely unused. The fallback is the complete path; the feature is the better one.

Where Codex has its own tool for the same job, name it in the same sentence (verified against Codex CLI 0.160's model-visible tools):

| Job | Claude Code | Codex |
|---|---|---|
| Start a sub-agent | `Agent` (typed `leek-skills:<name>` agents) | `spawn_agent`, then `wait_agent` for its result |
| Follow up with a running one | `SendMessage` to its `name` | `followup_task` (new turn) or `send_message` (no turn) |
| Stop one | `TaskStop` | `interrupt_agent` |
| Structured question | `AskUserQuestion` | `request_user_input`, only when listed for that turn (Codex offers it in some modes and for optional questions), so the chat fallback stays the main Codex path |

Codex never loads `agents/` or the mod, so a Codex sub-agent gets the same brief a generic one would.

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
- `model` / `effort`: only on one-turn, user-invoked skills whose work is mechanical (`which-skill`, `wait-what`, `commit`, `panel`), or whose only judgment is ranking what its subagents return (`chatter-scout`). The override lasts the rest of the turn, so never on a skill other skills chain into, and never on interviews. For a `context: fork` skill, put them on the agent file instead.
- `context: fork` + `agent: leek-skills:<name>` + `background: false`: only on a skill whose body is the whole task and never needs the conversation (`research`, `dependency-audit`). Everything else reads the conversation and stays inline; see Subagents below.
- Not adopted, on purpose: `when_to_use` (Codex and `npx skills` read only `description`, so triggers stay there), `paths`/`hooks` (no skill has a fact that needs them yet).

Note `disable-model-invocation: true` also stops a skill running when a Claude Code scheduled task fires with the skill as its prompt. The loop skill (`dependency-audit`) is driven by user-typed `/loop`, which is unaffected.

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

- **Skills stay the source of truth and degrade gracefully.** A skill names its agent as the Claude Code branch of an existing "if the harness has sub-agents … otherwise inline" sentence, never as the only path. The verifier fails a skill that names an agent without a fallback clause.
- **Agents carry no procedure of their own.** An agent body states its role, its standing rules (read-only, output shape), and how to use its memory; the brief it receives from the skill is the task. The exception is a skill with `context: fork`, whose SKILL.md body *is* the prompt: keep that body an actionable task, not guidelines.
- **Reference by scoped name** (`leek-skills:module-designer`), both in `subagent_type` and in a skill's `agent:` field. Preloaded skills are scoped too (`skills: [leek-skills:codebase-design]`), and only model-invoked skills can be preloaded.
- **`tools:` takes bare tool names**, not permission patterns; scope Bash with the skill's `allowed-tools` instead. Plugin agents cannot set `hooks`, `mcpServers`, or `permissionMode`. A guard an agent needs goes in the plugin's `hooks/hooks.json`, and its script exits 0 unless the hook input's `agent_type` names that agent (verified: the main session sends no `agent_type`, a plugin agent sends `leek-skills:<name>`). The hook runs on every matching tool call in every session, so the non-matching path must stay instant. Two exist: `browser-test`'s guard, and `hooks/guard-review-agents.py`, which holds `finding-verifier` and `pr-reviewer` to read-only commands because both read untrusted review text. Both are Python, not bash, because they parse shell words.
- **Extra frontmatter is safe** (verified: Codex's `SkillFrontmatter` has no `deny_unknown_fields`, `npx skills` copies SKILL.md verbatim, Grok reads Claude skills as-is). `context: fork` therefore changes only Claude Code, where the body runs in the named agent with `$ARGUMENTS` but without the conversation.
- **`.claude-plugin/plugin.json` pins the plugin name** so agents namespace as `leek-skills:` under `--plugin-dir` as well as a marketplace install; the version stays in `marketplace.json` only.
- `memory: project` writes under the *target* repo's `.claude/agent-memory/`; say so in the skill when the agent uses it. Skills that commit always include those notes (`commit`, `release`, `implement`), so the user never commits them by hand.

## Mods (`hooks/mods/`)

A [mod](https://code.claude.com/docs/en/plugins/mods/overview) is TypeScript that runs inside Claude Code (terminal and Desktop Code tab): panes, the band above the prompt, instant `/commands`, and observation of tool calls, turns, and subagent spawns. `hooks/hooks.json` names the one module under `modules`; other harnesses never load it.

- **Polish over a skill that already works.** A mod shows or speeds up what a skill does; it never holds the only copy of a rule or a step. `/scratch` is the live, turn-free view of `scratch-status`, which still owns the commit checks; the workers band shows the subagents a fan-out skill dispatched, which still reports their results in chat; the ticket board pane shows each ticket, then the review stage and findings, of a multi-ticket run (`implement-spec`, `implement <spec> all`, `wayfinder <map> all`) reports through the mod's `ticket_board` tool, per `wayfinder/references/ticket-board.md`, and the tool's reply tells the skill when to post its chat progress lines instead. Where nothing draws (VS Code chat, `claude -p`), a command answers with text.
- **One module, every `$` in it.** The engine never follows `$` across an import, so every hook lives in `hooks/mods/register.tsx`; imported files are pure (`scratch-scan.ts`, `workers-model.ts`) and carry the logic worth testing. One `tool.call` hook per module: features share it.
- **Observers never block.** A hook on a gating event (`tool.call`, `agent.spawn`, `prompt.submit`, `ui.close`) ends with `.catch(($, e, next) => next(e))`, so a mod failure lets the event through.
- **Check before committing:** `claude plugin validate .` and `claude plugin test .` (tests are `hooks/mods/*.test.ts[x]`). CI has no `claude` CLI and only checks that the module path exists. State keys live in `types/index.d.ts`, named in `.claude-plugin/plugin.json` as `types`.

## Worktrees

Only six kinds of skill create a worktree: the dirty-tree recipes in `triage-github-pr` and `fix-ci-failures`; `fix-github-issues`, on every run, so the main checkout never moves; `to-spec`, briefly, to commit a spec onto its own branch when `HEAD` carries another session's unpushed commits; `implement`'s PR delivery when the user asks for one or the tree is dirty; `implement-spec`, one per parallel implementer; and `sweep`, one per cycle. Sessions also run in one all the time (`claude --worktree`, subagents with `isolation: worktree` such as `panel`'s panelists on a committed scope). Every skill that creates one makes it runnable through `laravel-herd-worktrees`' **Bootstrap a bare worktree** section and stops serving it through its **Remove a served worktree** section, the one owner of both recipes (built on `herd workspace`); in Claude Code, `hooks/bare-worktree-notice.sh` (SessionStart) also points a session that opens in a bare Laravel worktree at that section. It cannot run the bootstrap itself: `WorktreeCreate` replaces git's worktree creation and plugins cannot register it, and `SubagentStart` carries no working directory. A skill that creates a worktree or a scratch database registers each database in `<git-common-dir>/scratch-databases`, and removes nothing until the end of its run. Then it removes without asking what it created whose work has landed (the PR merged, or the commits are on the target or integration branch), lists each removal in the report, and asks once only about the rest: a dirty worktree git refuses without `--force`, and unmerged, unlanded, or queued work (a multi-select of what to remove where the harness has `AskUserQuestion`, otherwise one yes/no). Never `--force`, and never anything the run did not create (`triage-github-pr`, `fix-github-issues`, `fix-ci-failures`, `implement-spec`, `sweep` say how). Whatever is left (an item the user kept, a queued merge, a stopped run, a harness worktree) is `repository-cleanup`'s job, through `skills/repository-cleanup/scripts/prune-merged-worktrees.sh`, which lists by default and removes only the exact names passed to it. No hook runs it: `repository-cleanup` happens when the user asks, and every removal there is one the user selected.

## Best Practices

**How to write one is the `writing-for-agents` skill**: it is model-invoked, so reach for it rather than working from this file. Only what is specific to *this repo* lives here:

- **Where the shared protocols live.** A protocol several skills need has exactly one owner, and the others point at it: the question shape and STE rules in `grilling`, tracker operations in `setup`'s seeds, the end-of-session banner in `wayfinder/references/pipeline-end-block.md`, the ticket board in `wayfinder/references/ticket-board.md`.
- **Status marks in chat reports.** Four marks, used sparingly so a report scans fast: ✅ done, passed, or fixed · ❌ failed · ⚠️ needs the user (blocked, unsure, a risk, kept for a decision) · 👉 the next step. One mark at the start of a status line or verdict cell, in front of the plain word, which stays (`✅ fixed in abc123`), so nothing that reads the word breaks. No marks in headings, prose, or lines with no status. Chat only: never in files a skill writes, commits, PR bodies, tracker or GitHub comments, `ReportFindings` fields, subagent reports, or script output. Each skill that uses them says which, in one line beside its report format.
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
