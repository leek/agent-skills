#!/bin/sh
# PreToolUse on a structured question (AskUserQuestion, Grok ask_user_question,
# Codex request_user_input, agy ask_question), and Notification: ring the terminal bell so a
# Ghostty tab badges itself (🔔 in the title) while Claude waits on the user.
# Ghostty only: other terminals beep, which nobody opted into.
# Hooks have no controlling tty (/dev/tty fails), so walk up to the first ancestor that has one.
[ "$TERM_PROGRAM" = ghostty ] || exit 0

p=$$
while [ "$p" -gt 1 ]; do
  t=$(ps -o tty= -p "$p" | tr -d ' ')
  if [ -n "$t" ] && [ "$t" != "??" ]; then
    printf '\a' > "/dev/$t"
    exit 0
  fi
  p=$(ps -o ppid= -p "$p" | tr -d ' ')
done
