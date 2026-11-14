# Authoring skills, agents, and mods

Repo-specific rules for adding or changing a skill, a subagent (`agents/`), or the mod (`hooks/mods/`). How to write the text itself is the `writing-for-agents` skill.

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

CI fails if a skill is missing the file or the two disagree. `short_description` is a whole sentence, never one cut off with `...`. `interface.default_prompt` is optional: the prompt Codex pre-fills for a skill that takes arguments (`prune-tests`, `sweep`).

**Scripts.** A skill runs from the target repo, so a command names its script as `<this-skill-dir>/scripts/<name>.sh`; the verifier fails a bare `bash scripts/<name>.sh`. A markdown link to the script is fine as a mention, never as the command: a link followed by its arguments in a code span, or one after "run" in a file that never spells the full command, fails too. Put a script's offline test beside it as `scripts/test-<name>.sh`: the verifier runs every `skills/*/scripts/test-*.sh` with `bash` from the repo root, each under a time limit (`SKILL_TEST_TIMEOUT` seconds, default 120), and also runs `code-smells-audit`'s `validate-cards.sh`. `VERIFY_ONLY=<text> bash scripts/verify-skills-collection.sh` runs only the checks whose name contains the text.

**Portability.** Every skill must *run* in Claude Code, Codex, Grok, and agy, and still name a harness-specific feature with a fallback beside it: the rule is [`writing-for-agents`' Portability](../skills/writing-for-agents/SKILL-MECHANICS.md#portability).

**Harness tool names have one owner: [`skills/harness-tools/SKILL.md`](../skills/harness-tools/SKILL.md).** The four moves every harness does differently (dispatch and wait, dispatch in the background, follow up, stop) and the structured question live there, one row per harness, with each harness's gotchas (Codex's `fork_turns: "none"`, Grok's `background` default, agy's message-back sub-agents). A skill names the move and points there: `ask the user to choose (a structured question ([harness-tools](../harness-tools/SKILL.md)), otherwise in chat)`. A skill may name a Claude Code tool inline when it carries the skill's own detail (a typed `leek-skills:<name>` agent, `SendMessage` to a `name` it set, an `AskUserQuestion` `preview`), but never another harness's tool name, and a file that names `AskUserQuestion`, `SendMessage`, or `TaskStop` also points at `harness-tools`: the verifier fails either miss. Name the dispatch move exactly: **dispatch and wait** when the step needs every result before it goes on (parallel fan-outs included), **dispatch in the background** only when the run keeps working meanwhile. Adding a harness is one new row per table in that file, plus its name in the verifier's row check.

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
- `allowed-tools`: pre-approve only the commands the skill exists to run (`commit` → `git add/commit`, `research` → `WebFetch WebSearch`). Deny rules in settings still win. Never pre-approve a destructive command the body says to ask about first. A skill that has `allowed-tools` and names one of its own `scripts/*.sh` in `SKILL.md` or any other `.md` file of the skill (`references/`, companions) must cover that script (`Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/<skill>/scripts/<name>.sh *)`): the verifier fails otherwise, unless the script is on its `EXEMPT` list with the reason it keeps its prompt. Write the path from `${CLAUDE_PLUGIN_ROOT}`, never a leading `*`: the plugin directory holds a wildcard path for review, and Claude Code substitutes the variable in `allowed-tools` Bash rules. A copy installed without the plugin (`npx skills`) gets no substitution, so there the script asks first. Pre-approve `WebFetch` by host (`WebFetch(domain:github.com)`) unless the skill reads the open web.
- `user-invocable: false`: for a protocol other skills run that has its own user front door (`grilling` behind `grill-me`). It hides the `/` entry; the model can still invoke it.
- `compatibility`: environment the skill cannot run without (Herd on macOS, a CLI on PATH). Documentation only.
- `model` / `effort`: only on one-turn, user-invoked skills whose work is mechanical (`which-skill`, `wait-what`, `commit`, `panel`, `scratch-status`), or whose only judgment is ranking or reporting what its subagents return (`chatter-scout`, `browser-test`). The override lasts the rest of the turn, so never on a skill other skills chain into, and never on interviews. For a `context: fork` skill, put them on the agent file instead.
- `context: fork` + `agent: leek-skills:<name>` + `background: false`: only on a skill whose body is the whole task and never needs the conversation (`research`, `dependency-audit`). Everything else reads the conversation and stays inline; see Subagents below.
- Not adopted, on purpose: `when_to_use` (Codex and `npx skills` read only `description`, so triggers stay there), `paths`/`hooks` (no skill has a fact that needs them yet).

Note `disable-model-invocation: true` also stops a skill running when a Claude Code scheduled task fires with the skill as its prompt. The loop skill (`dependency-audit`) is driven by user-typed `/loop`, which is unaffected.

The invariant that follows (a user-invoked skill is never reachable from another skill, so shared reference goes in a file both point at) is in [`writing-for-agents`' Invocation](../skills/writing-for-agents/SKILL-MECHANICS.md#invocation).

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

`agents/<name>.md` at the repo root are [Claude Code subagent definitions](https://code.claude.com/docs/en/sub-agents). They are **typed shells for work the skills already delegate**: read-only tool sets, a cheaper model where the thinking happens elsewhere, preloaded vocabulary via `skills:`, and cross-session `memory:`. Claude Code and Grok load them as `leek-skills:<name>` when the plugin is installed. Codex never sees the directory.

Rules:

- **Skills stay the source of truth and degrade gracefully.** A skill names its agent as the Claude Code branch of an existing "if the harness has sub-agents … otherwise inline" sentence, never as the only path. The verifier fails a skill file that names an agent without a fallback clause in the same paragraph.
- **Agents carry no procedure of their own.** An agent body states its role, its standing rules (read-only, output shape), and how to use its memory; the brief it receives from the skill is the task. The exception is a skill with `context: fork`, whose SKILL.md body *is* the prompt: keep that body an actionable task, not guidelines.
- **Reference by scoped name** (`leek-skills:module-designer`), both in `subagent_type` and in a skill's `agent:` field. Preloaded skills are scoped too (`skills: [leek-skills:codebase-design]`), and only model-invoked skills can be preloaded.
- **`tools:` takes bare tool names**, not permission patterns; scope Bash with the skill's `allowed-tools` instead. Plugin agents cannot set `hooks`, `mcpServers`, or `permissionMode`. A guard an agent needs goes in the plugin's `hooks/hooks.json`, and its script exits 0 unless the hook input's `agent_type` names that agent (verified: the main session sends no `agent_type`, a plugin agent sends `leek-skills:<name>`). The hook runs on every matching tool call in every session, so the non-matching path must stay instant. Three exist. Two are dispatched and parsed through `hooks/shell_guard.py` (which enforces both bash and zsh syntax rules in one Python invocation per Bash call, and blocks the call when a guard crashes): `browser-test`'s guard, and `hooks/guard-review-agents.py`, which holds `finding-verifier` and `pr-reviewer` to read-only commands because both read untrusted review text. The third, `hooks/memory_write_guard.py`, runs on the file-write tools: `memory:` gives an agent Write and Edit even when its `tools:` line has neither, so every read-only agent with `memory:` goes in its `MEMORY_ONLY` set (a test fails when one is missing).
- **Extra frontmatter is safe** (verified: Codex's `SkillFrontmatter` has no `deny_unknown_fields`, `npx skills` copies SKILL.md verbatim, Grok reads Claude skills as-is). `context: fork` therefore changes only Claude Code, where the body runs in the named agent with `$ARGUMENTS` but without the conversation.
- **`.claude-plugin/plugin.json` pins the plugin name** so agents namespace as `leek-skills:` under `--plugin-dir` as well as a marketplace install. It also carries `version`, which the Claude plugin directory requires; `release` bumps it together with `marketplace.json`, and the verifier fails when the two differ.
- `memory: project` writes under the *target* repo's `.claude/agent-memory/`; say so in the skill when the agent uses it. Skills that commit always include those notes (`commit`, `release`, `implement`), so the user never commits them by hand.

## Mods (`hooks/mods/`)

A [mod](https://code.claude.com/docs/en/plugins/mods/overview) is TypeScript that runs inside Claude Code (terminal and Desktop Code tab): panes, the band above the prompt, instant `/commands`, and observation of tool calls, turns, and subagent spawns. `hooks/hooks.json` names the one module under `modules`; other harnesses never load it.

- **Polish over a skill that already works.** A mod shows or speeds up what a skill does; it never holds the only copy of a rule or a step. `/scratch` is the live, turn-free view of `scratch-status` (it reads `.scratch/` and runs read-only `git ls-files` and `git log` for file ages), which still owns the commit checks; the workers band shows the subagents a fan-out skill dispatched, which still reports their results in chat; the ticket board pane shows each ticket, then the review stage and findings, then the work still open, of a multi-ticket run (`implement-spec`, `implement <spec> all`, `wayfinder <map> all`) reports through the mod's `ticket_board` tool, per `wayfinder/references/ticket-board.md`, and the tool's reply tells the skill when to post its chat progress lines instead. Where nothing draws (VS Code chat, `claude -p`), a command answers with text.
- **One module, every `$` in it.** The engine never follows `$` across an import, so every hook lives in `hooks/mods/register.tsx`; imported files are pure (`scratch-scan.ts`, `workers-model.ts`) and carry the logic worth testing. One `tool.call` hook per module: features share it.
- **Observers never block.** A hook on a gating event (`tool.call`, `agent.spawn`, `prompt.submit`, `ui.close`) ends with `.catch(($, e, next) => next(e))`, so a mod failure lets the event through.
- **Check before committing:** `claude plugin validate .` and `claude plugin test .` (tests are `hooks/mods/*.test.ts[x]`). CI installs the Claude Code CLI and runs both in `scripts/verify-skills-collection.sh`. State keys live in `types/index.d.ts`, named in `.claude-plugin/plugin.json` as `types`.
