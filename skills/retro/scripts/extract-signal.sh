#!/bin/bash
# Extract the signal from one session log, read-only: user-role messages, queued messages,
# the tail of each assistant text reply, shell commands, and tool errors, each with its
# source line (or SQLite step index).
# Claude Code, Codex (plain or .jsonl.zst, streamed, never decompressed in place),
# Grok, and agy (.db, opened read-only).
#
# Usage: extract-signal.sh <log path> [--max-chars N]
#   --max-chars N   truncate each text to N characters (default 600)
# Output: JSONL, one event per line: {"path","line","kind","text"}
#   kind: user (a user-role message: NOT proof of human authorship; preambles, agent
#   briefs, and relayed or quoted text also arrive here), queued (typed while a turn
#   ran), assistant (the last N characters of an assistant text reply, where its closing
#   questions and next steps sit; not agy), command (a shell command the agent ran),
#   tool_call (other tool input), error (a failed tool result; a Codex "Script completed"
#   result is never one).
# Status and coverage gaps go to stderr. An empty result from a non-empty log means the
# format changed: inspect the event types (`jq -rc .type FILE | sort | uniq -c`).

set -e

f=${1:-}
[ -n "$f" ] || { echo "Usage: extract-signal.sh <log path> [--max-chars N]" >&2; exit 2; }
shift
max=600
while [ $# -gt 0 ]; do
  case "$1" in
    --max-chars) max=$2; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done
[ -r "$f" ] || { echo "Unreadable: $f" >&2; exit 1; }

tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
errs='error|not found|exception|fatal|denied|failed|refused|no such'

emit() {  # emit [path]: wrap jq's {line, kind, text} rows with the source path and truncation
  jq -c --arg path "${1:-$f}" --argjson max "$max" 'select(.text != null and .text != "")
    | {path:$path, line, kind, text:(.text|tostring|.[0:$max])}'
}

case "$f" in
  *.db)  # agy: SQLite with protobuf payloads; step types 14 prompt, 132 tool call+result, 101 relayed
    id=$(basename "$f" .db)
    hist=~/.gemini/antigravity-cli/history.jsonl
    if [ -f "$hist" ]; then
      jq -c --arg id "$id" 'input_line_number as $n | select(.conversationId==$id) | {line:$n, kind:"user", text:.display}' "$hist" | emit "$hist"
    fi
    # -readonly needs a writable -shm beside a WAL database; immutable=1 opens without it
    # but cannot see steps still in the WAL, so say when it was used.
    db="$f"
    if ! sqlite3 -readonly "$db" "select 1 from steps limit 1" >/dev/null 2>&1; then
      echo ">> $f: opened immutable; steps still in the WAL are not visible" >&2
      db="file:$f?immutable=1"
    fi
    sqlite3 -readonly -separator ' ' "$db" "select idx, step_type, hex(step_payload) from steps where step_type in (14,101,132) order by idx" > "$tmp"
    while read -r idx t hex; do
      txt=$(printf '%s' "$hex" | xxd -r -p | LC_ALL=C strings -n 8 | LC_ALL=C tr '\n' ' ' | iconv -f utf-8 -t utf-8 -c)
      case "$t" in
        14)  kind=user ;;
        101) kind=user; txt="[relayed from another conversation] $txt" ;;
        *)   if printf '%s' "$txt" | grep -qiE "$errs"; then kind=error; else kind=tool_call; fi ;;
      esac
      jq -nc --argjson n "$idx" --arg k "$kind" --arg t "$txt" '{line:$n, kind:$k, text:$t}'
    done < "$tmp" | emit
    ;;
  *)
    case "$f" in
      *.zst) command -v zstd >/dev/null || { echo ">> $f: no zstd reader; excluded" >&2; exit 1; }
             zstd -dc -- "$f" > "$tmp" ;;
      *)     cat -- "$f" > "$tmp" ;;
    esac
    jq -c --arg errs "$errs" --argjson max "$max" '
      def txt: if type=="array" then map(.text // "") | join(" ") elif type=="string" then . else tostring end;
      def tail: if length > $max then .[-$max:] else . end;
      # Codex code-mode results open with "Script completed" or "Script failed"; the rest is
      # the script output, which often holds the word "error" without anything failing. A
      # completed script still failed when a command inside it exited non-zero.
      def codex_failed: (.output | if type=="array" then (.[0].text // "") else tostring end) as $head
        | if ($head|startswith("Script completed") or startswith("Script running")) then (.output|txt|test("\"exit_code\": ?[1-9]"))
          elif ($head|startswith("Script failed")) then true
          else (.output|tostring|test($errs; "i")) end;
      input_line_number as $n
      | if .type=="queue-operation" and .operation=="enqueue" then
          (.content | select(type=="string" and (startswith("<task-notification>")|not)) | {line:$n, kind:"queued", text:.})
        elif .type=="user" and (.message.content? != null) then   # Claude Code
          (.message.content | if type=="string" then {line:$n, kind:"user", text:.}
            else .[]? | if .type=="text" then {line:$n, kind:"user", text:.text}
              elif .type=="tool_result" and .is_error==true then {line:$n, kind:"error", text:(.content|txt)}
              else empty end end)
        elif .type=="assistant" and (.message.content? != null) then
          (.message.content[]? | if .type=="text" then {line:$n, kind:"assistant", text:(.text|tail)}
            elif .type!="tool_use" then empty
            elif .name=="Bash" then {line:$n, kind:"command", text:.input.command}
            else {line:$n, kind:"tool_call", text:(.name + " " + (.input|tostring))} end)
        elif .type=="response_item" then                           # Codex
          (.payload | if .type=="message" and .role=="user" then {line:$n, kind:"user", text:(.content|txt)}
            elif .type=="message" and .role=="assistant" then {line:$n, kind:"assistant", text:(.content|txt|tail)}
            elif .type=="custom_tool_call" or .type=="function_call" then {line:$n, kind:"command", text:((.input // .arguments)|tostring)}
            elif (.type=="custom_tool_call_output" or .type=="function_call_output") and codex_failed then {line:$n, kind:"error", text:(.output|txt)}
            else empty end)
        elif .type=="event_msg" and .payload.type=="user_message" then  # older Codex logs
          {line:$n, kind:"user", text:.payload.message}
        elif .type=="user" then                                    # Grok
          {line:$n, kind:"user", text:(.content|txt)}
        elif .type=="assistant" then                               # Grok
          ((.content | select(type=="string" and . != "") | {line:$n, kind:"assistant", text:tail}),
           (.tool_calls[]? | {line:$n, kind:"command", text:tostring}))
        elif (.type=="tool_result" or .type=="tool") and ((.content|tostring)|test($errs; "i")) then
          {line:$n, kind:"error", text:(.content|tostring)}
        else empty end' "$tmp" | emit
    ;;
esac
