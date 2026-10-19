# Panel CLI invocations

Per-CLI detail behind the invocation table in `SKILL.md`. Read this only when a CLI
misbehaves, when you want a hard read-only guarantee, or when the panel roster changes.
`SKILL.md` holds the canonical command for each CLI; this file explains the flags and
the alternatives; it does not restate the canonical command.

Three rules hold for every CLI:

- **No `--model`.** Each CLI must run as its own latest/default model.
- **Literal words only.** Worktree isolation refuses a command whose words are computed
  at runtime, so `TASK=$(cat …) && cli "$TASK"` and `--cd "$PWD"` are both refused inside
  a panelist's worktree. Hand each CLI the task file by absolute path: on stdin (`claude`,
  `codex`) or as `--prompt-file` (`grok`). `agy` alone takes the task text inline, as one
  single-quoted literal with each `'` written as `'\''`, so the shell expands nothing. A
  CLI that does not read the task on stdin gets `< /dev/null`, so it does not block there.
- **Headless needs auto-approval.** A headless run cannot answer a permission prompt, so
  each command carries that CLI's bypass flag. The read-only options below vary in
  quality; the working-tree check in `SKILL.md` step 3 (not a flag) is what enforces
  review-only.

## claude

- Headless: `-p` / `--print` runs one prompt and exits. With no prompt argument it reads
  the prompt from stdin, which is how the row passes the task file.
- Auto-approve: `--dangerously-skip-permissions`.
- Read-only variant: keep `--dangerously-skip-permissions` (so it stays non-interactive)
  and drop the edit tools: `--disallowedTools Edit Write NotebookEdit`. Those three are
  the real tool names: `MultiEdit` is not one and triggers a warning.
- Structured output: `--output-format json` (default is text, which the subagent distills).

## codex

- Headless: the `exec` subcommand is non-interactive.
- Working dir: `-C` / `--cd <dir>`: pass the worktree's absolute path, written out (not
  `"$PWD"`), so codex reads the right repo.
- Auto-approve: `--dangerously-bypass-approvals-and-sandbox`.
- Read-only variant: `codex exec --sandbox read-only --cd WORKTREE - < TASK_FILE`: the
  `read-only` sandbox blocks writes while still running non-interactively. Drop the
  bypass flag when you use it; the two are mutually exclusive.
- Prompt position: trailing positional, after all flags. `-` (or no prompt) reads the
  prompt from stdin.
- Structured output: `--output-schema <file>` plus `-o` / `--output-last-message <file>`.

## agy

- Headless: `-p` / `--print` runs one prompt and exits. It has no prompt-file flag, and
  `-p` with no value prints help rather than reading stdin (stdin is read only with
  `--input-format stream-json`), so the task goes inline as a single-quoted literal.
- **Always pass `--print-timeout 30m`.** The default is 5m, and a code review takes longer
  than that, so without it agy dies with `Error: timeout waiting for response` after five
  minutes and the seat returns nothing. Put it before `-p` like every other flag.
- Flag order: `-p` / `--print` consumes the NEXT token as its prompt value, so put every
  other flag **before** `-p` and give the task as `-p`'s value last, 
  `agy --dangerously-skip-permissions -p '<task text>'`. Putting `-p` first (`agy -p
  --dangerously-skip-permissions '<task text>'`) makes it swallow `--dangerously-skip-permissions`
  as the prompt: the flag is silently dropped (permissions never skipped) and the real
  task is discarded as an ignored trailing positional, so no review runs.
- Auto-approve: `--dangerously-skip-permissions`.
- Read-only: agy has no clean review read-only flag. Do **not** use `--mode plan` for a
  review: plan mode hijacks the run into "planning mode" and ignores the task. Keep
  auto-approve and rely on the working-tree check in `SKILL.md` step 3.
- Structured output: `--output-format json` and `--json-schema <schema>`.

## grok

- Headless: `-p` / `--single <PROMPT>` runs one prompt and exits; `--prompt-file <PATH>`
  does the same with the prompt read from a file, which is how the row passes the task.
- Auto-approve: `--always-approve`.
- Read-only variant: grok has `--sandbox <profile>` (also `GROK_SANDBOX` env) plus
  `--deny <rule>` permission rules. Run `grok --help` for the profile names on this
  machine before relying on one; they are grok-specific and not fixed here.
- Structured output: `--json-schema <schema>` (implies `--output-format json`).

## Absent vs errored

- **Absent**: `command -v <cli>` prints nothing. Drop the CLI from the run and name it
  in the report. Absent CLIs never count toward the consensus grades.
- **Errored**: the CLI is installed but the run failed: non-zero exit, empty output, an
  auth error, or a timeout. The subagent returns `status: errored` with the one-line
  cause. An errored CLI also does not count toward the grades, but the report names it so
  the user knows the panel was short a voice.

## Auth

Each CLI authenticates on its own (its own login, API key, or config). The panel does not
manage credentials. An auth failure surfaces as an `errored` result, not a crash.
