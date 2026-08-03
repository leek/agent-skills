---
name: research
description: Investigate a question against high-trust primary sources and capture the findings as a cited Markdown file. Use when the user wants a topic researched, docs or package facts gathered, reading legwork delegated, or a wayfinder research ticket resolved.
---

# Research

Run the research in a sub-agent so the main session can keep working on unrelated branches — but the sub-agent must **finish inside this session**. A sub-agent's task handle dies at `/clear`, session end, or context compaction, and one still running when the session ends is killed mid-read. If the read is longer than the session has room for, do it inline instead. In harnesses without sub-agents, do the research inline and say so.

## Dispatching a research run

- In Claude Code, use the Agent tool — `Explore` for read-only source sweeps, `general-purpose` when the research needs web fetches or other tool calls. Hand the sub-agent the question plus **The research brief** below.
- Collect the result before the session ends or suggests `/clear` — never leave one running.
- In everything durable (tickets, resolution comments, hand-off text), reference the findings **by file path and branch, never by task ID** — a task ID written down is a dead handle the next session will poll and fail on.
- Relay the answer plus the file path to the user — not a re-paste of the whole document.

### Wayfinder integration

When resolving a `wayfinder` research ticket, follow the configured tracker's Wayfinding operations. **Claim it first** through the Claim operation so a concurrent session cannot pick it up mid-flight. Commit the findings file to a throwaway `research/<ticket-slug>` branch, then use the Resolve operation to record the answer and branch pointer and close the ticket. Research tickets are the one type a charting session may run several of in parallel — one sub-agent per ticket, one branch each, all collected before the session ends.

## The research brief

The sub-agent's job:

1. Investigate the question against **primary sources** — official docs, package source (`vendor/` for Composer, `node_modules/` for npm), specs, first-party APIs — never a secondary write-up of them. Follow every claim back to the source that owns it. In a Laravel project with Boost, prefer the `search-docs` MCP tool over web search for framework and package questions — it returns version-pinned ecosystem docs.
2. Write the findings to a single Markdown file, citing each claim's source — a URL, a file path, or `package@version`. End the file with a short **What this unblocks** section: the answer in one or two lines (or what stayed unanswered and why), and what it makes decidable — no pipeline banners or skill routing, which the dispatching session owns.
3. Save it where the repo already keeps such notes; match the existing convention. If there is none, `.scratch/research/<slug>.md` is the default — say where it landed.
4. Report back the answer plus the file path — the final message is data for the dispatcher, not prose for the user.

## When you're done

The dispatching session routes the result. List only the conditions that apply, most likely first:

- **Answered, and a decision was waiting on it** → `/grill-me` on that decision, naming it
- **Answered a `wayfinder` ticket** → `/wayfinder <map>` for the next frontier ticket
- **Answered, and it changes a published spec** → `/to-spec` to revise, naming which section is now wrong
- **Unanswerable from primary sources** → say so plainly; `/to-questionnaire` if a person holds the answer
- **Answered, but surfaced a new unknown** → `/research` on the new question, stated as a question
