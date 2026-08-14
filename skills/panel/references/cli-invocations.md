# Panel CLI invocations

Per-CLI detail behind the invocation table in `SKILL.md`. Read this only when a CLI
misbehaves, when you want a hard read-only guarantee, or when the panel roster changes.
`SKILL.md` holds the canonical command for each CLI; this file explains the flags and
the alternatives — it does not restate the canonical command.

Two rules hold for every CLI:

- **No `--model`.** Each CLI must run as its own latest/default model.
- **Headless needs auto-approval.** A headless run cannot answer a permission prompt, so
  each command carries that CLI's bypass flag. The read-only variants below trade that
  bypass for a sandbox the CLI cannot escape.

## claude

- Headless: `-p` / `--print` runs one prompt and exits.
- Auto-approve: `--dangerously-skip-permissions`.
- Read-only variant: `claude -p "<task>" --permission-mode plan` — plan mode reads freely
  but does not edit. Prefer this in review shape when a stray write would be unacceptable.
- Structured output: `--output-format json` (default is text, which the subagent distills).

## codex

- Headless: the `exec` subcommand is non-interactive.
- Working dir: `-C` / `--cd <dir>` — pass `"$PWD"` so codex reads the right repo.
- Auto-approve: `--dangerously-bypass-approvals-and-sandbox`.
- Read-only variant: `codex exec --sandbox read-only --cd "$PWD" "<task>"` — the
  `read-only` sandbox blocks writes while still running non-interactively. Drop the
  bypass flag when you use it; the two are mutually exclusive.
- Prompt position: trailing positional, after all flags.
- Structured output: `--output-schema <file>` plus `-o` / `--output-last-message <file>`.

## agy

- Headless: `-p` / `--print` runs one prompt and exits (`--print-timeout` defaults to 5m).
- Auto-approve: `--dangerously-skip-permissions`.
- Read-only variant: `agy -p "<task>" --mode plan` — plan mode does not modify files.
  Add `--sandbox` for terminal restrictions on top.
- Structured output: `--output-format json` and `--json-schema <schema>`.

## grok

- Headless: `-p` / `--single <PROMPT>` runs one prompt and exits.
- Auto-approve: `--always-approve`.
- Read-only variant: grok has `--sandbox <profile>` (also `GROK_SANDBOX` env) plus
  `--deny <rule>` permission rules. Run `grok --help` for the profile names on this
  machine before relying on one — they are grok-specific and not fixed here.
- Structured output: `--json-schema <schema>` (implies `--output-format json`).

## Absent vs errored

- **Absent** — `command -v <cli>` prints nothing. Drop the CLI from the run and name it
  in the report. Absent CLIs never count toward the consensus grades.
- **Errored** — the CLI is installed but the run failed: non-zero exit, empty output, an
  auth error, or a timeout. The subagent returns `status: errored` with the one-line
  cause. An errored CLI also does not count toward the grades, but the report names it so
  the user knows the panel was short a voice.

## Auth

Each CLI authenticates on its own (its own login, API key, or config). The panel does not
manage credentials. An auth failure surfaces as an `errored` result, not a crash.
