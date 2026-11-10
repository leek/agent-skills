# Panelist brief

The brief every panelist subagent gets in [`SKILL.md`](../SKILL.md) step 3, beside the
path of the **same** task file. Give it in full on every run.

- **Launch with the launcher script, literal paths only.** Run your CLI **once**, from
  the repo root (or your worktree), with `bash LAUNCHER <cli> TASK_FILE SCRATCH/panel-<cli>.out`,
  where `LAUNCHER` is this skill's [`scripts/launch.sh`](../scripts/launch.sh), and every path is
  absolute and written out in full: worktree isolation refuses a command whose words are
  computed at runtime (`$(cat …)`, `$TASK`, `$PWD`). The script holds each CLI's headless
  command and flags (no `--model`, ever) and writes all its output to the `.out` file. If a
  guard still refuses the launch, that is a launch-form problem, not a CLI error: say
  which word it refused; `bash LAUNCHER --print <cli> …` prints the plain command to run instead.
- **Run it detached: never let one time out.** These CLIs take many minutes, past the
  shell tool's 10-minute foreground ceiling, which kills a run before it reports. Launch
  with the Bash tool's `run_in_background: true`; your turn pauses and you are re-invoked
  when the CLI exits; then read the `.out` file. Where the shell tool has no background
  mode and rejects `&` (Grok CLI), run it in the foreground with the tool's timeout set to
  its maximum (for example `timeout: 900000`), never its default.
- **Wait with one call, never poll.** No `sleep`, `ps`, `pgrep`, or repeated reads of
  the output file while the CLI runs: each check spends a turn, and the turn cap ends the
  subagent while its CLI is still running.
- Distill the output into a short, normalized result. For each point the CLI makes,
  capture three things: a one-line **claim**, a **location** (`file:line`, or
  `general`), and a one-line **reason**. Drop the CLI's logs, thinking, and prose.
- Return `{ cli, status, points[] }`. `status` is `responded`, or `errored` with a
  one-line cause (a non-zero exit or an empty `.out`). Return the object only, no narration.
