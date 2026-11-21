#!/bin/sh
# PreToolUse on a structured question (AskUserQuestion, Grok ask_user_question,
# Codex request_user_input, agy ask_question), and Notification: ring the terminal bell so a
# Ghostty tab badges itself (🔔 in the title) while Claude waits on the user.
# Ghostty only: other terminals beep, which nobody opted into.
# Hooks have no controlling tty (/dev/tty fails), so walk up to the first ancestor that has one.
[ "$TERM_PROGRAM" = ghostty ] || exit 0

p=$$
while :; do
  case "$p" in ''|*[!0-9]*) exit 0 ;; esac
  [ "$p" -gt 1 ] || exit 0
  t=$(ps -o tty= -p "$p" 2>/dev/null | tr -d ' \t\n')
  if [ -n "$t" ] && [ "$t" != "??" ] && [ "$t" != "?" ] && [ -w "/dev/$t" ]; then
    { printf '\a' > "/dev/$t"; } 2>/dev/null || true
    exit 0
  fi
  next=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' \t\n')
  [ "$next" != "$p" ] || exit 0
  p=$next
done
