---
name: research-plus
description: Investigate a question against high-trust primary sources and capture the findings as a cited Markdown file, run as a background subagent so the main session keeps working. Use when the user wants a topic researched, docs or package facts gathered, reading legwork delegated, or a wayfinder-plus research ticket resolved.
---

# Research Plus

Spin up a **background subagent** to do the research, so the main session keeps working while it reads. In Claude Code that is the Agent tool run in the background — `Explore` for read-only source sweeps, `general-purpose` when the research needs web fetches or other tool calls. In harnesses without subagents, do the research inline and say so.

The subagent's job:

1. Investigate the question against **primary sources** — official docs, package source (`vendor/` for Composer, `node_modules/` for npm), specs, first-party APIs — never a secondary write-up of them. Follow every claim back to the source that owns it. In a Laravel project with Boost, prefer the `search-docs` MCP tool over web search for framework and package questions — it returns version-pinned ecosystem docs.
2. Write the findings to a single Markdown file, citing each claim's source — a URL, a file path, or `package@version`.
3. Save it where the repo already keeps such notes; match the existing convention. If there is none, put it somewhere sensible (`.scratch/research/<slug>.md` is a fine default) and say where.

The final report back to the main session is the answer plus the file path — not a re-paste of the whole document.

## Wayfinder integration

When resolving a `wayfinder-plus` research ticket, **claim it first**: before launching the subagent, the dispatching session assigns the ticket to the driving dev and sets it In Progress, so a concurrent session reading the frontier can't pick it up mid-flight. Then commit the findings file to a throwaway `research/<ticket-slug>` branch and post the answer with a pointer to that branch as the ticket's resolution comment, then close the ticket. Research tickets are the one type a charting session may fire in parallel — one subagent per ticket, one branch each.

## When you're done

A background subagent has no live session to print into, so the direction goes **in the findings file** — last section, and repeated in the ticket resolution comment when there is a ticket. Write it whether the research answered the question or not.

```markdown
## What this unblocks

Pipeline: **decide** → spec → slice → build   (research feeds decide)

<the answer in one or two lines, or what stayed unanswered and why>

Next:
- <condition> → /<skill> <ref>
```

On harnesses without slash commands, write the command as plain phrasing (`run grill-me-plus on <ref>`). List only the conditions that actually apply, most likely first:

- **Answered, and a decision was waiting on it** → `/grill-me-plus` on that decision, naming it
- **Answered a `wayfinder-plus` ticket** → `/wayfinder-plus <map>` for the next frontier ticket
- **Answered, and it changes a published spec** → `/to-spec-plus` to revise, naming which section is now wrong
- **Unanswerable from primary sources** → say so plainly; `/to-questionnaire-plus` if a person holds the answer
- **Answered, but surfaced a new unknown** → `/research-plus` on the new question, stated as a question
