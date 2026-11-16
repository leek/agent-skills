# Load rules

What each context source costs and when Claude Code loads it. `inventory.sh` encodes these rules; when the docs change, change both. Anything marked unverified is reported as `activation: uncertain`, never guessed.

Verified against code.claude.com docs (memory, settings, skills, sub-agents, mcp, hooks, output-styles) on 2026-11-16, Claude Code 2.1.3xx. A run on this repo matched that session's loaded context exactly.

## Instruction files

| Source | Loads | Note |
|---|---|---|
| Managed `CLAUDE.md` (`/Library/Application Support/ClaudeCode/` on macOS, `/etc/claude-code/` on Linux) | always | Cannot be excluded. |
| `<config>/CLAUDE.md` | always | `<config>` is `$CLAUDE_CONFIG_DIR`, else `~/.claude`. Under a profile, `~/.claude/CLAUDE.md` loads only when the profile's file is the same file (a symlink). |
| `CLAUDE.md`, `.claude/CLAUDE.md`, `CLAUDE.local.md` in the cwd and every directory above it, up to `/` | always | Root first, so the cwd file reads last. `CLAUDE.local.md` is supported and belongs in `.gitignore`. |
| `CLAUDE.md` below the cwd | lazy | When Claude reads, writes, or edits a file in that directory (a Bash `cat` counts). |
| `.claude/rules/**/*.md`, `<config>/rules/**/*.md` | always, or lazy with `paths:` | `paths:` (YAML list or comma string) is the only field read; it fires on Read/Write/Edit of a match. User rules load before project rules. |
| `AGENTS.md` in the cwd chain | only without a CLAUDE.md | Native since 2.1.277: read only when no `CLAUDE.md`, `.claude/CLAUDE.md`, or `CLAUDE.local.md` exists in the cwd chain. `pluginConfigs."cc-plugin-agents-md@builtin".options.instructionFiles` changes it (`claude-md-or-agents-md` is the default). Nested `AGENTS.md`: unverified. |
| `@path` imports | with the importing file | Relative to the importing file. Four hops at most. Imports inside code spans and fences are skipped; a markdown link `[x](AGENTS.md)` imports nothing. An import saves no context: the file loads in full. |
| `.cursorrules`, `.cursor/rules/`, `.windsurfrules`, `.clinerules`, `GEMINI.md`, `.github/copilot-instructions.md` | never | Other tools' files. Claude Code reads them only through an import. |

`claudeMdExcludes` (absolute-path globs, any settings scope, arrays merge) drops matching files. `/memory` lists the instruction files Claude Code sees; `/doctor prompt-audit` checks them for conflicts.

## Memory

- **Auto memory**: `<config>/projects/<slug>/memory/`, where the slug is the repository root path with every non-alphanumeric character replaced by `-` (worktrees share it; the encoding is observed, not documented). `autoMemoryDirectory` moves it. `MEMORY.md` loads every session, but only its first 200 lines or 25KB, whichever comes first; topic files load only when the agent opens them. `autoMemoryEnabled: false` or `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` turns it off. Subagents do not get it (forks do).
- **Subagent memory**: `memory: user|project|local` in an agent file gives it `<config>/agent-memory/<name>/`, `.claude/agent-memory/<name>/`, or `.claude/agent-memory-local/<name>/`. That agent's `MEMORY.md` (first 200 lines or 25KB) joins its system prompt each time it runs.

## Every turn

- **Skills**: name and description (description plus `when_to_use`, capped at 1,536 characters) for every model-invoked skill. The whole listing is budgeted at 1% of the context window; past it, descriptions of the least-invoked skills are dropped. `disable-model-invocation: true` removes the description entirely. The body loads on invocation.
- **Subagents**: every agent's description, every turn. There is a startup warning above 15,000 tokens combined.
- **Skill overrides**: `skillOverrides` in settings maps a skill name to `off` (hidden from the model), `user-invocable-only` (no description), or `name-only` (name listed, no description). Plugin skills ignore it: only disabling the plugin hides them.
- **MCP**: tool names and server instructions. Servers come from `.mcp.json`, the config dir's `.claude.json` (under `CLAUDE_CONFIG_DIR`, the profile's own file, not `~/.claude.json`), plugins, claude.ai account connectors, and tools a plugin registers at runtime. The last two appear in no local file, so the session's own context is the only inventory of them. Tool schemas are deferred while tool search is on (the default). `ENABLE_TOOL_SEARCH=false`, or a server's `alwaysLoad: true`, loads them upfront.
- **Output style**: the selected style's text joins every request. The default adds nothing.
- **Hooks**: nothing by default. `additionalContext` from SessionStart, UserPromptSubmit, and similar hooks is injected, capped at 10,000 characters.

Settings files (managed > `--settings` > `.claude/settings.local.json` > `.claude/settings.json` > `<config>/settings.json`) add no text, but they decide most of the above.

## Measuring

`inventory.sh` estimates tokens as bytes/4. `claude plugin details <plugin@marketplace>` prints a plugin's component inventory and projected always-on and on-invoke tokens per component: read-only, so the configuration lens runs it for each enabled plugin. The real per-item figures for the session come from `/context all` (memory files, skills, MCP tools), `/skills` (press `t` to sort by tokens), and `/skill-doctor`. Ask the user to run `/context all` and paste the Memory files and Skills rows when exact numbers matter for a decision.

## Other harnesses

Codex reads `AGENTS.md` files and its own `~/.codex/AGENTS.md`; Grok and agy have their own rules. This script does not model them. Outside Claude Code, the inventory still lists every file. Set each one's activation from what your own context shows loaded at session start, and mark the rest `uncertain`.
