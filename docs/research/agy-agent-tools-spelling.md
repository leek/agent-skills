# agy agent-file tools: spelling and wrong-name behaviour

Question: Does an agy agent file tools: accept view_file-style IDs, native read_file-style names, or both, and does a wrong name hang the subagent?

## Findings

- Prior state (docs/research/agy-tool-name-mapping-and-grok-route.md lines 22, 36): website subagents doc shows view_file IDs and warns misspelled names may hang; shipped migration skill writes native names; no subagent run yet.
- Docs: `https://antigravity.google/docs/subagents` (summarizing fetch, 2026-11-17): `tools` is `string[]`, default `[]`, "Explicit list of tools permitted for this subagent"; no list of valid names, examples use `view_file`, `replace_file_content`, `grep_search`, `run_command`; warns "Specifying an unmapped or misspelled tool name in the `tools` list may cause the subagent process to hang", a "known issue" with "Enhanced schema validation and a fix ... planned".
- Shipped migration skill (`~/.gemini/antigravity-cli/builtin/skills/migrate-agent-settings/SKILL.md`, "agents/<name>.md" section) writes native names (`read_file`, `edit_file`, `write_file`, `run_command`, `manage_task`, `search_web`) and says an omitted `tools` gets only a small read-only default set.
- Live probe (agy 1.5.10, 2026-11-17, scratch workspace with `.agents/agents/probe-*.md`, frontmatter `subagent: true`, `mainAgent: false`, parent run via `agy -p "Invoke the subagent named X with the task: read note.txt ..." --output-format stream-json --dangerously-skip-permissions`, 1 turn each):
  - `tools: [read_file]` -> subagent launched, returned file content (38 s).
  - `tools: [view_file, grep_search, run_command]` -> subagent launched, returned file content, no error (28 s). So legacy IDs are accepted (resolved by alias or equivalent).
  - `tools: [read_filez]` (bogus) -> NO hang: the subagent failed immediately (17 s total run, rc 0, status SUCCESS for the parent) with `failed to construct executor: failed to resolve components: unknown component: tool "read_filez" not found in registry`, which the parent relayed. Binary strings also contain `unknown tool name: `%s``, `duplicate tool name: %s`.
- Caveats: one bogus name, one model, one `-p` print run with permissions skipped; the legacy run does not show which concrete tool the subagent called (the stream only shows the parent's `invoke_subagent`), and a mixed list (valid + invalid) was not tested. The docs' hang warning was not reproduced in 1.5.10; it may describe an older build or an interactive/App path.

## What this unblocks
Both spellings work in agy 1.5.10: native names (`read_file`, ...) and legacy IDs (`view_file`, ...) were accepted; a wrong name does not hang but fails the subagent at startup with `unknown component: tool "<name>" not found in registry`. Prefer native names in agent files (they match the shipped migration skill and what fires at runtime); a typo is a loud, fast error, not a hang.

## Follow-up: this plugin's Claude-format agents in agy (2026-11-17, agy 1.5.10)

- `agy plugin validate .` on this repo: "no plugin.json found ... This looks like a Claude Code plugin: `plugin install` converts it".
- `HOME=<scratch> agy plugin install https://github.com/leek/agent-skills` (and the same with the local path): installs 59 skills and 22 agents, writes a root `plugin.json` (`name`, `version`, `description`, `author`), and converts `hooks/hooks.json` to agy `hooks.json`: `Bash|run_terminal_command` became `run_command`, the file-write matcher became `write_to_file|write_file|replace_file_content|edit_file|multi_replace_file_content`, `${CLAUDE_PLUGIN_ROOT}/` became `./`. Skipped with a warning: `Notification` ("there is no Notification event") and any PreToolUse matcher naming no agy tool (`AskUserQuestion` alone; adding `ask_question` keeps the bell hook). Agent files are copied verbatim.
- Agent probes in a scratch workspace (`.agents/agents/pr-reviewer.md`, parent `agy -p "Invoke the subagent named pr-reviewer ..." --output-format stream-json --dangerously-skip-permissions`):
  - this repo's `agents/pr-reviewer.md` as is (`tools: Read, Grep, Glob, Bash`), with or without `subagent: true`: `subagent "pr-reviewer" not found or not allowed to be invoked`.
  - minimal file, `tools: read_file, run_command` (comma string): same "not found". So a comma-string `tools:` makes agy drop the file silently.
  - minimal file, `tools: [read_file, run_command]`: launched and returned the file content.
  - minimal file, `tools: [Read, Grep, Glob, Bash]`: failed at startup, `unknown component: tool "Read" not found in registry` (and `Grep`, `Glob`, `Bash`).
- So agy cannot run this repo's typed agents in either `tools:` form; skills keep agy on `invoke_subagent` `TypeName: "self"` (`skills/harness-tools/SKILL.md`).
