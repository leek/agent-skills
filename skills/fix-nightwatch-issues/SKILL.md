---
name: fix-nightwatch-issues
description: Triage open Laravel Nightwatch production issues by root cause, fix the legit ones, and resolve them with evidence.
disable-model-invocation: true
argument-hint: "Optional issue numbers or a type filter (exception, route, job, command, scheduled_task); defaults to all open issues"
compatibility: "Requires the Laravel Nightwatch MCP server"
---

# Fix Nightwatch Issues

Open Nightwatch issues are exceptions, and slow routes, jobs, commands, and scheduled tasks. Many are stale, ops problems, or third-party blips.

Follow the shared [production triage](../diagnosing-bugs/references/production-triage.md) frame: its ground rules, then its steps 1–5 in order. This file adds only what is specific to Nightwatch, under the same step numbers. The project-context file is `.agents/nightwatch.md`: the application and environment names, the deploy model, the infra paths, and the known false premises.

## 0. Resolve the target

Read [`references/nightwatch-mcp.md`](references/nightwatch-mcp.md) before your first Nightwatch call. It covers finding the application and the production environment, the issue tools, an issue that will not load, and the resolve calls. The working set is the `open` issues of the production environment, ordered by last seen.

An issue whose detail will not load is a problem with that one issue's payload, not with the environment. Work from its list summary and the other issues in its group, and name it as unread in the report.

An empty application list or issue list can mean collection is off, not that production is healthy. Check the project context (or the infra config) and report "collection is off" when that is the cause.

## 1. Group by root cause

Nightwatch groups issues by message text. For example, one root-run command that leaves a root-owned log file surfaces as a separate "Permission denied … while attempting to log: <message>" issue for every message it swallowed.

## 2. Classify each group

Categories, between STALE and LEGIT:

- **INFRA/OPS**: permissions, a missing or disabled PHP capability, the log sink, a container user mismatch, or an env var. Fix these in container or infra config, not app code.
- **EXTERNAL/TRANSIENT**: a third-party timeout or 5xx, or a network blip. Judge by count and spread. Add a retry only if it recurs and the retry is cheap.
- **NOISE**: bot 404s, aborted requests, and health-check probes. Filter these in Nightwatch sampling, not in code.

Examples:

- `Issue #131: STALE — last seen 2026-05-02, path fixed in a1b2c3d (deployed 2026-05-03); no occurrences since`
- `Issue #110: INFRA/OPS — root-owned daily log file; consequence of #106; fix is logging sink + entrypoint, not app code`
- `Issue #144: EXTERNAL/TRANSIENT — single queue receive timeout, 1 occurrence in 30d`
- `Issue #150: NOISE — 404 from a bot scan on /wp-login.php`

## 3. Fix each LEGIT group at the right layer

- App logic: fix the code.
- Environment or permissions: fix the container setup or the infra env config.
- A slow route, job, or command: add an index (check the schema first), eager-load, chunk, or move the work to a queue.

The commit body lists refs as `Nightwatch: #106, #107-#115`.

## 4. Resolve in Nightwatch

The working-set read is `list_issues` with status `open`. For each fixed issue still open, comment with the root cause and the fix sha, then set it to `resolved`. A LEGIT issue blocked on an operator stays `open`, with a comment naming its blocker.

## 5. Offer a deploy re-check

The re-check prompt: "With the Nightwatch MCP, read last-seen for issues #<ids>; reopen and comment on any seen after <deploy date>."
