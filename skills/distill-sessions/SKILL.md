---
name: distill-sessions
description: Mine recent AI-coding session logs for reusable patterns and propose concrete improvements.
disable-model-invocation: true
---

# Distill Sessions

Turn raw session transcripts into a ranked list of concrete improvements. Read-only analysis of the logs; **never modify the log files**. Output a numbered proposal list with one verbatim (redacted) evidence line per finding, then let the user pick which to apply.

## Where the logs live

- **Claude Code:** `~/.claude/projects/<slug>/*.jsonl` (top-level sessions). Per-session subagent transcripts are under `<uuid>/subagents/agent-*.jsonl` — **skip these** when counting "sessions"; they're part of a parent.
- **Codex:** `~/.codex/sessions/<year>/<month>/<day>/rollout-*.jsonl`.

Both are JSONL — one event per line.

## 1. Pick the N most recent sessions

Default N = 50 unless the user gives a number. `date`/`strftime` may be missing from the shell — use `perl` for timestamps.

```bash
{ find ~/.claude/projects -name '*.jsonl' -type f | grep -v '/subagents/'; \
  find ~/.codex/sessions -name 'rollout-*.jsonl' -type f; } \
| xargs stat -f '%m %z %N' | sort -rn | head -50 \
| perl -lane 'use POSIX qw(strftime); my($m,$s,@p)=@F; printf "%s %7dKB %s\n", strftime("%Y-%m-%d %H:%M",localtime($m)), $s/1024, join(" ",@p)'
```

## 2. Extract signal (use jq — do NOT cat whole files)

Files are large and full of tool-output noise. `jq` is the right tool. Two schemas:

**Claude Code**
```bash
# human-typed messages (string form)
jq -rc 'select(.type=="user" and (.message.content|type=="string")) | .message.content' FILE
# human messages (array form; skip <command-name>/system-reminder noise by eye)
jq -rc 'select(.type=="user" and (.message.content|type=="array")) | .message.content[]? | select(.type=="text") | .text' FILE
# bash commands the assistant ran
jq -rc 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="Bash") | .input.command' FILE
# tool errors
jq -rc 'select(.type=="user") | .message.content[]? | select(.type=="tool_result" and .is_error==true) | (.content|if type=="array" then (map(.text//"")|join(" ")) else tostring end)' FILE
```

**Codex**
```bash
# human messages (the FIRST is an AGENTS.md preamble — ignore it)
jq -rc 'select(.type=="event_msg" and .payload.type=="user_message") | .payload.message' FILE
# shell commands
jq -rc 'select(.type=="response_item" and .payload.type=="function_call") | .payload.arguments' FILE
# command outputs (grep for errors)
jq -rc 'select(.type=="response_item" and .payload.type=="function_call_output") | (.payload.output|tostring)' FILE | grep -iE 'error|not found|exception|fatal|denied' | head
```

Surface corrections fast by grepping extracted human messages:
`grep -iE "no,|actually|that.?s wrong|don.?t |stop |instead|you should have|i told you|revert|why did you|wrong"`

## 3. Fan out — one subagent per batch

50 sessions won't fit one context. Split the file list into ~7 round-robin batches (so big files spread out) and dispatch one subagent per batch **in parallel**, each with the jq cheat-sheet above and an identical brief. Each subagent returns a structured findings list; the orchestrator dedupes across batches and synthesizes. Round-robin assignment:
```bash
awk '{print $NF}' top.txt | awk '{ b=((NR-1)%7)+1; print > ("batch_" b ".txt") }'
```

## 4. What to find (four categories)

1. **Corrections** — the user pushed back ("no", "actually", "that's wrong", "don't do that", reverting/redoing). Highest value — capture every one.
2. **Repeated / errored commands** — a command or tool that errored, or was retried several times before working. Note what finally fixed it.
3. **Repeated setup steps** — the same setup/config/env/login/build/cache-clear rediscovered across more than one session.
4. **Content moments** — something worth an article, tweet, tutorial, diagram, prompt, product idea, or example.

## 5. Redaction (mandatory)

In every quoted evidence line, replace emails, API keys, tokens, secrets, passwords, and bearer strings with `[REDACTED]`. Keep quotes short.

## 6. Output — a numbered proposal list

For each finding, give: the proposal, **the one verbatim (redacted) evidence line it came from** (with session basename), the destination, and a one-sentence why. Destinations:

- a content idea to draft / add to the idea library
- a line to add to `CLAUDE.md` / `AGENTS.md` (name the file)
- a slash command or skill to add or update (name it)
- a hook that should run automatically
- a tool or CLI that should be fixed
- a config or settings change
- **or nothing**, if it was a genuine one-off

**Do not change anything.** Present the list and let the user choose which to apply. Lead with the cross-cutting themes (patterns that recurred across 3+ sessions are the highest-value to act on).
