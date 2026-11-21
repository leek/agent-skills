---
name: harness-tools
description: The tool each agent harness (Claude Code, Codex, Grok, agy) uses to start, follow up with, or stop a sub-agent, and to ask the user a structured question. Use when a skill names one of these moves and points here, or when you are not sure which tool your harness has for it.
user-invocable: false
---

# Harness Tools

Skills name a **move** (dispatch and wait, dispatch in the background, follow up, stop, structured question) and point here for the tool. This file holds what every harness shares: what each move means, its fallback, and the rules for every sub-agent. The tools are in one file per harness. Read only yours:

| Harness | File |
|---|---|
| Claude Code | [references/claude-code.md](references/claude-code.md) |
| Codex | [references/codex.md](references/codex.md) |
| Grok | [references/grok.md](references/grok.md) |
| agy | [references/agy.md](references/agy.md) |

Use your harness's tool with the skill's own content (the brief, the agent type, the options), and use the move's fallback below when that tool is not in your tool list. A harness with no file here: use its own tool for the move if it has one, otherwise the fallback. The fallback is always a complete path.

## Every sub-agent

- **Brief it in full.** A sub-agent starts with none of your conversation. Put every path, ref, and rule it needs in the brief.
- **Typed agents.** A skill may name a typed agent, `leek-skills:<name>`, often in its Claude Code clause. Your harness file says whether it can run them. Where it cannot, start a general sub-agent with the same brief, and hold it to the typed agent's rules (read-only, output shape) through the brief.
- **Its own background commands.** Every brief for a sub-agent you dispatch in the background carries this rule, with the script's absolute path: "Never end your turn while a command you started is still running. Run tests in the foreground. If the shell tool moves a command to the background (it does at its timeout), wait for it in the foreground: `bash <this-skill-dir>/scripts/wait-task-output.sh <the output file it named>`, and run that again while it prints `running`." Nothing wakes a sub-agent that ends its turn on a running command.
- **Model tier.** Where the skill asks for a cheaper or stronger model, your harness file names the parameter. Where it names none, inherit.

## The moves

**Dispatch and wait.** Start one or more sub-agents and use every result before you go on. For several, start them all in one message first, then wait for all of them. Fallback: do the work inline, and say so.

**Dispatch in the background.** Start sub-agents and keep working on something else; collect each result when it lands. Keep each returned name or id against the skill's label for it, so you can follow up or stop it. Fallback: run them inline one after another.

**Follow up.** Send more work to a sub-agent that is running or has finished, so it keeps its context. Fallback: brief a fresh sub-agent with everything the follow-up needs (paths, the finding, the failure output).

**Stop.** Fallback: leave it running and say so in the report.

**Structured question.** A click-to-answer question: the recommended option first and marked as recommended, real options only, and a free-text Other that the harness adds. When the skill asks for more questions or options than your tool takes, split them over further calls; when it asks for multi-select and your tool has none, ask that question in chat. Fallback: the same shape in chat: the question, the numbered options with the recommendation first, then wait for the answer.

## While background sub-agents run

Each wake either changes the run's state or does not. A repeat of a report you already used gets no reply: end the turn without text. An idle notice or completion from an agent that has not delivered its report is a **stall**, even when it explains itself: it says it is waiting on a background run, a test, or a notice, or it carries no report and no new commit. Follow up with it at once: "Nothing will wake you. Wait for that run in the foreground with `wait-task-output.sh`, then finish and report." A wake that changes state gets one status line with the count and the names still running (`4 of 7 done; waiting on billing-export, fax-cover`), so the user never has to ask for status.

A sub-agent's handle dies at `/clear`, at session end, and at compaction. In anything durable (tickets, comments, hand-off text), refer to its output by file path, never by task id.

## Workspaces

A skill that makes its own git worktree passes that path in the brief, so the sub-agent works there.
