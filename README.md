# Agent Skills

Personal collection of agent skills for coding agents (Claude Code, Cursor, Grok, and others).

Skills follow the [Agent Skills](https://agentskills.io/) format.

[![skills.sh](https://skills.sh/b/leek/agent-skills)](https://skills.sh/leek/agent-skills)

## Available Skills

Skills marked **user** are user-invoked only (`/name`); the rest the agent can reach for on its own. Many are adapted from [Matt Pocock's skills](https://github.com/mattpocock/skills), tuned for Laravel/PHP repos.

The engineering pipeline is one straight line (**decide → spec → tickets → build**) over one directory per effort:

```
.scratch/<slug>/
  map.md        # /wayfinder: the decisions (skip it for small, clear work)
  decisions/    # /wayfinder: one file per decision ticket
  spec.md       # /to-spec: exactly one, written once
  tickets/      # /to-tickets: one file per build ticket
```

`/implement` then builds one file from `tickets/` per run. `triage` is the other on-ramp. There is no external issue tracker; every artifact is a markdown file.

| Skill | Invocation | What it does |
|---|---|---|
| `architecture-satisfaction` | user | Run a bounded architectural refactor loop. |
| `autopilot` | user | Drive an existing wayfinder map, spec, or set of tickets to completion through fresh top-level Claude Code, Codex, or Grok sessions. |
| `browser-test` | user | Test a web app from a start URL and a plain-language prompt: a planner splits it into cases, cheap parallel browser workers run them, and one verdict table comes back. Read-only unless you confirm a write. |
| `chatter-scout` | user | Sweep the web for new chatter on a topic, skip what earlier runs saw, verify the rest in cheap parallel subagents, and write one ranked, cited findings file for a blog post or digest. |
| `closeout` | user | Check whether this session is safe to close: uncommitted or unpushed work, running jobs, open PRs, unanswered questions, and post-merge steps. Each open item names the skill or command that clears it, and closeout runs the fixes you pick. |
| `code-review` | model | Review the changes since a fixed point (commit, branch, tag, or merge-base) along three axes: Correctness (would it break: bugs, failure modes, security, missing tests), Standards (does the diff follow this repo's documented conventions, including colocated CLAUDE.md rules?) and Spec (does it implement what the originating ticket/PRD asked?). |
| `code-smells-audit` | model | Audit a codebase, path, glob, or branch diff for classic code smells using the 56-smell Luzkan catalog, with detection heuristics tuned to PHP/Laravel and TS/React: sweep nine occurrence lenses, adversarially verify every candidate against the smell's card definition, emit a ranked markdown findings report. |
| `codebase-design` | model | Shared vocabulary for designing deep modules in any codebase. |
| `commit` | user | Commit the work done in this session, skipping files a parallel session also touched. |
| `dependency-audit` | user | Run a Composer or npm dependency audit and propose a safe upgrade plan. |
| `diagnosing-bugs` | model | Diagnosis loop for hard bugs and performance regressions. |
| `domain-modeling` | model | Build and sharpen a project's domain model: challenge terms against the glossary, resolve fuzzy language, stress-test concepts with concrete scenarios, and record GLOSSARY.md entries and ADRs the moment decisions land. |
| `fix-ci-failures` | user | Read a branch's latest failed CI runs, triage each failure from its existing logs, and fix the real ones. |
| `fix-github-issues` | user | Verify, triage, fix, and close review-bot GitHub issues one finding at a time. |
| `fix-nightwatch-issues` | user | Triage open Laravel Nightwatch production issues by root cause, fix the legit ones, and resolve them with evidence. |
| `fix-posthog-issues` | user | Triage active PostHog error-tracking issues by root cause, fix the legit ones, and resolve or suppress the rest. |
| `grill-me` | user | Run a grilling session: the user wants their plan, decision, or idea stress-tested one question at a time. |
| `grill-with-docs` | user | Run a grilling session with domain-modeling alongside, capturing terms in GLOSSARY.md and decisions as ADRs while they land. |
| `grilling` | model | Interview the user one decision at a time until reaching shared understanding, resolving each branch of the decision tree with recommended options and trade-offs. |
| `handoff` | user | Compact the current conversation into a handoff document for another agent to pick up. |
| `harness-tools` | model | Which tool each harness (Claude Code, Codex, Grok, agy) uses to start, follow up with, or stop a sub-agent, and to ask a structured question. The one place skills look these up. |
| `housekeeper` | user | Run a conservative code-project housekeeping pass. |
| `implement` | user | Implement one work item end to end: scope and claim it when trackable, TDD at agreed seams, commit, review, verify, and resolve it. |
| `implement-spec` | user | Build a whole spec fast: parallel implementer subagents work the ticket frontier, each in its own worktree, merging onto one integration branch; then one review, one verification pass, and one PR or a stack of PRs (it asks). Cuts the tickets first when the spec has none. |
| `improve-codebase-architecture` | user | Scan a codebase for deepening opportunities, present them as a visual HTML report, then grill through whichever one you pick. |
| `laravel-herd-worktrees` | model | Create, serve, or remove git worktrees for Laravel projects served by Laravel Herd on macOS. |
| `panel` | user | Convene a panel of agent CLIs (grok, claude, codex, agy) on a prompt or a code review, each in its own headless subagent, then report one consensus grouped by how much they agree. |
| `pr` | model | The pull request body format, built for fast human review: the smallest visual of the change, before/after evidence, and a one-way or two-way door call with its blast radius. |
| `prototype` | model | Build a throwaway prototype to answer a design question. |
| `prune-tests` | user | Delete low-signal tests one test area at a time, keeping coverage within 2%, and open one PR per area. Earlier runs' areas are excluded. |
| `release` | model | Commit this session's work, bump the version, tag, push, and publish a GitHub release with grouped notes. |
| `repository-cleanup` | user | Audit and clean Git repository state, including the local databases old worktrees left behind. |
| `research` | model | Investigate a question against high-trust primary sources and capture the findings as a cited Markdown file. |
| `resolve-review-comments` | model | Triage, fix or rebut, then reply-and-resolve every review comment on a PR (including AI-review bot findings). |
| `resolving-merge-conflicts` | model | Resolve an in-progress git merge or rebase conflict while preserving both sides' intent. |
| `retro` | user | Mine Claude Code, Codex (including compressed rollouts), Grok, and agy parent sessions for corrections and workflow friction; compare current guidance and loaded versions before proposing fixes. |
| `run-after` | user | Run this session's waiting steps (a backfill after deploy, a command after commit or merge) once their trigger lands: start the deploy, run it, and it confirms the steps, watches the deploy, and runs them. |
| `scratch-cleanup` | user | Sweep a dusty .scratch/: file research into docs/, remove finished efforts, and report the work still open. |
| `scratch-status` | user | Report what is still open across `.scratch/`: every effort's open tickets and decisions, what blocks it, how stale it is, and the next skill to run. Read-only. |
| `setup` | user | Configure this repo for the engineering skills: the markdown issue tracker layout, triage label vocabulary, and domain doc layout. |
| `sweep` | user | Dig for one problem nobody has noticed yet, prove it, fix it, and open one PR per problem. Every run finds something new: earlier PRs (open, merged, or declined) are excluded, never a reason to stop. |
| `tdd` | model | The red → green loop for any stack: seams, what a good test is, and the anti-patterns to refuse. |
| `teach` | user | Teach the user a new skill or concept, within this workspace. |
| `to-questionnaire` | user | Turn a decision the user can't fully answer into a Markdown questionnaire for someone else to fill in, async or over a meeting. |
| `to-spec` | model | Turn the current conversation into a spec (PRD) and save it as markdown under .scratch/: no interview, just synthesis, with Laravel test seams chosen from the tdd ranking rules rather than asked about. |
| `to-tickets` | model | Break a spec into tracer-bullet vertical-slice tickets with explicit blocking edges, settle the build's open decisions, and save one markdown file per ticket beside the spec. |
| `triage` | user | Move issues and external PRs through a state machine of triage roles: categorise, verify, grill if needed, and write agent-ready briefs. |
| `triage-github-pr` | user | Review and merge a pull request with up to two fix rounds, carrying later findings into a follow-up PR. |
| `ui-design` | model | Your UI/UX design rules, each with its reason and a check. Agents apply them when building a page or component, review against them (via the `ui-reviewer` subagent), and add a new rule whenever you state a preference. |
| `upgrade-plan` | user | Plan a library or framework upgrade from the installed version to the latest: cheap parallel subagents read the changelogs and scan the code, and one plan sorts what breaks, which local patches and workarounds can go, and what to adopt into must do, should do, and do later. Follows the dependencies that have to move too. |
| `verify` | model | Exercise a change end to end in the running application (hit the route, run the command, click through the page) and report what actually happened. |
| `wait-what` | user | Stop; that last message did not land. Re-pitch it. |
| `wayfinder` | user | Plan work too big for one agent session as a map of decision tickets in markdown under .scratch/, then resolve them one per session, or all in one run with `/wayfinder <map> all`, until the route to the destination is clear. |
| `which-skill` | user | Not sure which skill to reach for? Name the situation and get routed to one. |
| `wizard` | model | Generate an interactive bash wizard that walks a human through steps only they can perform: provisioning, dashboard credentials, CI secrets, one-off migrations or cutovers. |
| `writing-for-agents` | model | Reference for writing documents an agent consumes: skills, AGENTS.md/CLAUDE.md, and reference docs reached by a pointer. |

## Subagents

Installing the Claude Code or Grok plugin also loads the subagents in [`agents/`](./agents) as `leek-skills:<name>`. The skills dispatch them where they already fan out work: `code-review` → `pr-reviewer` + `standards-reviewer` + `spec-reviewer`, `codebase-design` (design-it-twice) → `module-designer`, `improve-codebase-architecture` → `deepening-scout`, `retro` → `session-miner`, `panel` → `panelist`, `browser-test` → `browser-test-planner` + `browser-tester` + `browser-writer`, `chatter-scout` → `chatter-sweeper` + `chatter-verifier`, `code-smells-audit` → `smell-sweeper`, `prune-tests` → `test-auditor`, `fix-github-issues` + `triage-github-pr` + `resolve-review-comments` → `finding-verifier`, `triage-github-pr` → `pr-reviewer`, `upgrade-plan` → `release-notes-collector` + `upgrade-impact-scout`, `ui-design` → `ui-reviewer`; `research` and `dependency-audit` fork into `researcher` and `dependency-auditor`, and `wayfinder` map runs dispatch `researcher` too. The plugin hooks in [`hooks/hooks.json`](./hooks/hooks.json) hold the agents that read untrusted input to read-only work: `browser-tester` and `browser-test-planner` run only read-only browser commands, `finding-verifier` and `pr-reviewer` run only read-only git, gh, rg, and text commands, and read-only agents with memory write only under `.claude/agent-memory/`. Two more hooks are conveniences: a notice in a bare Laravel worktree, and a terminal bell in Ghostty when Claude waits on you. Codex does not load the directory; its skills fall back to inline or generic sub-agents. Conventions in [`docs/authoring.md`](./docs/authoring.md#subagents-agents).

## Mods (Claude Code)

The plugin also ships a [mod](https://code.claude.com/docs/en/plugins/mods/overview) ([`hooks/mods/`](./hooks/mods)), which loads with the plugin in the Claude Code terminal and Desktop Code tab:

- **`/scratch [effort]`**: a live pane of every `.scratch/` effort (open tickets, blockers, claims, staleness, next command), opened instantly, even mid-turn, and refreshed whenever a tool writes under `.scratch/`. `scratch-status` adds the commit checks.
- **Workers band**: above the prompt, every subagent a fan-out skill dispatched (`implement-spec`, `autopilot`, `browser-test`, `panel`, `chatter-scout`, `code-review`, ...), with its tool count, latest tool, elapsed time, and outcome.
- **Ticket board**: while `implement-spec`, `implement <spec> all`, or `wayfinder <map> all` runs, a pane lists every ticket's status (ready, blocked, running, built or merged, resolved, released, closed), beside the live tool count of the sub-agent working it. Once the tickets are merged, it shows the review stage (review round, fix pass, final checks, verify) and each finding's status (open, fixing, fixed, asking, deferred). The skill reports each change through the mod's `ticket_board` tool. The mod registers that tool and answers every call to it itself, in its `tool.call` hook (`hooks/mods/register.tsx`), with a one-line reply that says whether the pane shows the run. It answers no other tool in place of the tool. Without the mod, the skill posts progress lines in chat as before. `/ticket-board` reopens a closed pane.

Other harnesses, and Claude Code surfaces that don't draw, run the same skills without it.

## What runs on your machine

Nothing below makes a network call or sends data anywhere. Everything the hooks and the mod read stays on your machine and in your Claude Code session.

### Hooks (`hooks/hooks.json`)

| Event | Script | What it does | What it changes |
|---|---|---|---|
| `SessionStart` | `hooks/bare-worktree-notice.sh` | Checks whether the project directory is a linked git worktree (a `.git` file) of a Laravel app (`artisan` and `composer.json`) with no `vendor/` yet. | When all three hold, it adds one line of session context pointing the agent at `laravel-herd-worktrees`' bootstrap. Otherwise nothing. It writes no files. |
| `PreToolUse` on `Bash` | `hooks/shell_guard.py` | Reads the tool call from stdin. For the `browser-tester`, `browser-test-planner`, `finding-verifier`, and `pr-reviewer` agents, it parses the shell command and checks it against a read-only allowlist. | It blocks a non-read-only command from those four agents (exit 2 with the reason). It never rewrites a command, and every other caller passes untouched. |
| `PreToolUse` on `Write`, `Edit`, `MultiEdit` | `hooks/memory_write_guard.py` | For the read-only agents that keep `memory:` (`deepening-scout`, `dependency-auditor`, `finding-verifier`, `release-notes-collector`, `session-miner`, `standards-reviewer`, `upgrade-impact-scout`), it resolves the target path. It reads `CLAUDE_CONFIG_DIR` only to find a profile's `agent-memory/` folder. | It blocks a write outside `.claude/agent-memory/` (project), `~/.claude/agent-memory/`, or `$CLAUDE_CONFIG_DIR/agent-memory/`. Every other caller passes untouched. |
| `PreToolUse` on `AskUserQuestion`, and `Notification` | `hooks/terminal-bell.sh` | Only when `TERM_PROGRAM` is `ghostty`: runs `ps` to find the terminal the session runs in. | It writes one bell character to that terminal, so the Ghostty tab shows 🔔 while Claude waits on you. It does nothing in any other terminal. |

### Mod (`hooks/mods/register.tsx`)

**What it sends, and where:** nothing leaves your machine. The mod makes no network calls. What it shows (the `.scratch/` board, the workers band, the ticket board) is held in Claude Code's plugin state for the session.

**Programs it runs,** through `process.run`, in the session's working directory. Both use fixed arguments, and both run only when `/scratch` runs or its pane is open:

- `git ls-files -z .scratch`: which `.scratch/` files are tracked.
- `git -c core.quotePath=false log --relative --format=%x00%ct --name-only -- .scratch`: the last commit time of each tracked file, so the board can mark stale tickets. A file git does not track falls back to its modified time.

The mod parses their output into timestamps for the pane and sends it nowhere.

**Files it reads:** `.scratch/` under the session's working directory (`fs.list`, `fs.read`), to draw the board.

**Hooks, and what each one reads and changes:**

- `session.start`: registers the `/scratch` and `/ticket-board` commands and the `ticket_board` tool. Changes nothing else.
- `command.run`: answers only the mod's own two commands, `/scratch` and `/ticket-board`. It opens the pane and replies with a one-line summary, or with the table where no pane draws. It never sees or changes another command.
- `tool.call`:
  - It **stands in for one tool only,** `mcp__leek-skills__ticket_board`, which the mod itself registers. No other tool sits behind it. When `implement-spec`, `implement <spec> all`, or `wayfinder <map> all` reports ticket progress, the hook records the update, draws the pane, and returns a one-line reply that says whether the pane showed it.
  - For every other tool, it observes only. It reads the tool name and input to count a subagent's tool calls and show its latest tool on the workers band. Then it calls `next` with the call unchanged and returns that result unchanged. After a write whose path or command names `.scratch/`, it rescans the open board.
- `agent.spawn`: reads the new subagent's name, type, and description, and the agent id from the result, to add a row to the workers band. It passes the spawn and returns its result unchanged.
- `turn.complete`: records a subagent's outcome on the band.
- `prompt.submit`: never reads the prompt's text. When no subagent is still running, it clears the workers band. The prompt passes unchanged.
- `ui.close`: remembers that you closed a pane, so later updates leave it closed.
- `ui.render`: draws the band and the two panes.

### Scripts the skills run

Skills run their own `skills/<name>/scripts/*.sh` by literal path, and each skill's `allowed-tools` pre-approves only those scripts by their path under `${CLAUDE_PLUGIN_ROOT}`. Two scripts deserve a note:

- `skills/upgrade-plan/scripts/versions.sh` downloads package metadata JSON from `repo.packagist.org` and `registry.npmjs.org` with `curl` and reads it with `jq`. It never runs what it downloads.
- `skills/autopilot/scripts/lib/tmux.sh` starts detached agent CLI sessions in tmux. A tmux session starts with the tmux server's environment, so the launcher passes on the variables those CLIs read (`PATH`, `CLAUDE_CONFIG_DIR`, `CODEX_HOME`, `GROK_HOME`, and the Anthropic, OpenAI, and xAI key and base-URL variables). It writes them to an owner-only temp file, which the child reads once and deletes. It never puts them on a command line or in a log, and never sends them anywhere else.

### Services the skills contact

The plugin declares no connectors and runs no server of its own. Nothing goes to the plugin's author. Some skills reach these outside services, always with your own tools and logins:

| Service | Skills | What goes there |
|---|---|---|
| GitHub (`gh` CLI) | `closeout`, `fix-ci-failures`, `fix-github-issues`, `implement`, `implement-spec`, `prune-tests`, `release`, `resolve-review-comments`, `run-after`, `scratch-cleanup`, `scratch-status`, `sweep`, `triage-github-pr` | Reads of PRs, issues, review comments, and CI runs. Writes only what the skill exists to make: PR replies and thread resolves, issue comments and closes, branches and PRs, release pages. |
| PostHog, Laravel Nightwatch (your own MCP servers) | `fix-posthog-issues`, `fix-nightwatch-issues` | Issue reads, comments, and resolve calls on your own project. |
| Packagist, npm registry | `upgrade-plan` (`versions.sh`), `dependency-audit` (`composer` and `npm` commands) | Package names, to read version metadata. |
| The web (Claude Code's WebFetch and WebSearch) | `research`, `chatter-scout`, `upgrade-plan`, `dependency-audit` | Search queries and the pages fetched. |
| Other agent CLIs (`claude`, `codex`, `grok`, `agy`) | `panel`, `autopilot` | The task prompt and, for a review, the diff. Each CLI sends them to its own provider under your account. |
| The app you name | `browser-test` | The browser visits the start URL you give. |

The `test-*.sh` files are the scripts' own tests. Only this repo's verifier (`scripts/verify-skills-collection.sh`) and CI run them, never a skill.

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

This copies the skills only. The typed subagents in [`agents/`](./agents) come with the Claude Code or Grok plugin, so in a repo that has the skills from `npx skills` and no plugin, a dispatch to `leek-skills:<name>` has no such agent and the skill takes its general sub-agent path. Install the plugin as well to get the cheaper, read-only typed agents. Codex's plugin does not load `agents/`.

### Claude Code (plugin marketplace)

```
/plugin marketplace add leek/agent-skills
/plugin install leek-skills@leek-agent-skills
```

### Codex (plugin marketplace)

Codex reads the same `.claude-plugin/marketplace.json`:

```bash
codex plugin marketplace add leek/agent-skills
codex plugin add leek-skills@leek-agent-skills
```

Codex lists the model-invoked skills as `leek-skills:<name>` and loads the plugin's `hooks/hooks.json`. It does not load `agents/` or the mod; the skills fall back to Codex's own sub-agents or run inline, per [`harness-tools`](./skills/harness-tools/SKILL.md). Pick one route per machine: if you already installed with `npx skills`, the plugin lists those skills a second time.

### Grok (plugin marketplace)

Grok reads the same `.claude-plugin/marketplace.json`:

```bash
grok plugin marketplace add leek/agent-skills
grok plugin install leek-skills --trust
```

Grok loads the plugin's skills, `agents/` as `leek-skills:<name>`, and `hooks/hooks.json`. It does not load the mod. Each harness's sub-agent and question tools are in [`harness-tools`](./skills/harness-tools/SKILL.md).

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
    SKILL.md            # required: frontmatter + instructions
    agents/openai.yaml  # required: the same metadata for Codex
    scripts/         # optional: helper scripts
    references/      # optional: supporting docs
```

The `SKILL.md` frontmatter requires only two fields (Claude Code reads a few optional ones such as `argument-hint` and `allowed-tools`; other harnesses ignore them, see [`docs/authoring.md`](./docs/authoring.md)):

```markdown
---
name: my-skill
description: One sentence, what it does and when Claude should use it.
---

# My Skill

Instructions here.
```

See [`template/SKILL.md.example`](./template/SKILL.md.example) for a starting point and [`docs/authoring.md`](./docs/authoring.md) for full conventions.

## Creating a Skill

1. Copy `template/SKILL.md.example` to `skills/<skill-name>/SKILL.md`.
2. Fill in `SKILL.md`: follow the authoring principles in AGENTS.md and the writing-for-agents skill.
3. Add `skills/<skill-name>/agents/openai.yaml` ([format](./docs/authoring.md#2-directory-structure)); the verifier fails without it.
4. Add the skill to `.claude-plugin/marketplace.json` under the `leek-skills` plugin.
5. Update the **Available Skills** section above.
6. Run `bash scripts/verify-skills-collection.sh`, then open a PR.

## License

MIT
