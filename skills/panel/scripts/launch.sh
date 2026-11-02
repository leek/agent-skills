#!/bin/bash
# Run one panel CLI once, headless, on the task file, from the current directory (the repo
# root or the panelist's worktree), and write everything it prints to the output file.
# The per-CLI command lives here and nowhere else. Never adds --model: each CLI runs as
# its own default model.
#
# Usage: launch.sh <claude|codex|agy|grok> <task file> <output file>
#        launch.sh --print <cli> <task file> <output file>   print the command, run nothing
# Exit: the CLI's own exit status (2 for a usage error).

set -e

print=0
if [ "${1:-}" = "--print" ]; then print=1; shift; fi
cli=${1:-}; task=${2:-}; out=${3:-}
[ -n "$cli" ] && [ -n "$task" ] && [ -n "$out" ] || { echo "Usage: launch.sh [--print] <cli> <task file> <output file>" >&2; exit 2; }
[ -f "$task" ] || { echo "No task file: $task" >&2; exit 2; }
wt=$(pwd -P)

# stdin: the task file for CLIs that read it there, /dev/null for the rest, so none blocks.
case "$cli" in
  claude) cmd=(claude -p --dangerously-skip-permissions); in=$task ;;
  codex)  cmd=(codex exec --dangerously-bypass-approvals-and-sandbox --cd "$wt" -); in=$task ;;
  # agy has no prompt-file or stdin form, and -p takes the NEXT token as its prompt, so
  # every flag goes before -p. The default 5m print timeout kills a review mid-run.
  agy)    cmd=(agy --dangerously-skip-permissions --print-timeout 30m -p "$(cat "$task")"); in=/dev/null ;;
  grok)   cmd=(grok --prompt-file "$task" --always-approve); in=/dev/null ;;
  *) echo "Unknown CLI: $cli (claude, codex, agy, grok)" >&2; exit 2 ;;
esac

if [ "$print" = 1 ]; then
  printf '%q ' "${cmd[@]}"; printf '< %q > %q 2>&1\n' "$in" "$out"
  exit 0
fi

command -v "$cli" >/dev/null || { echo "$cli is not on PATH" >&2; exit 127; }
echo ">> $cli started in $wt; output in $out" >&2
status=0
"${cmd[@]}" < "$in" > "$out" 2>&1 || status=$?
echo ">> $cli exited $status" >&2
exit "$status"
