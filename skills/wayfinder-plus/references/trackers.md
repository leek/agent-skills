# Tracker operations

How each supported tracker expresses the wayfinding operations: map, child tickets, labels, claiming, blocking, the frontier query, and resolution. `to-spec-plus`, `to-tickets-plus`, and `implement-plus` use the same resolution order and the create/comment/close subset of these operations.

## Linear (MCP tools)

Uses the `mcp__*Linear__*` tools. Ask which team/project the effort belongs to if not obvious from config or conversation.

| Operation | How |
|---|---|
| Labels | `create_issue_label` for `wayfinder:map`, `wayfinder:research`, `wayfinder:prototype`, `wayfinder:grilling`, `wayfinder:task` (skip ones that already exist — check `list_issue_labels`) |
| Create map | `save_issue` with `title`, `team`, `labels: ["wayfinder:map"]`, body as `description` |
| Create ticket | `save_issue` with `parentId: <map id>` and its `wayfinder:<type>` label — native sub-issues |
| Wire blocking | `save_issue` update with `blockedBy: [<ids>]` — native relations, append-only |
| Claim | `save_issue` update with `assignee: "me"` |
| Frontier | `list_issues` with `parentId: <map>`, `assignee: "null"`, open state; drop any whose `blockedBy` relations (visible via `get_issue`) contain an open issue |
| Resolve | `save_comment` with the resolution, then `save_issue` with `state: "Done"` (or the team's completed state) |
| Update map | `save_issue` on the map with the amended `description` |
| Assets | `links: [{url, title}]` on the ticket |

## GitHub (`gh` CLI)

Confirm auth with `gh auth status` before writing anything.

| Operation | How |
|---|---|
| Labels | `gh label create "wayfinder:map"` etc. (ignore already-exists errors) |
| Create map | `gh issue create --title "..." --label "wayfinder:map" --body-file <tmp>` |
| Create ticket | `gh issue create --label "wayfinder:<type>"` with `Map: #<n>` as the body's first line; then attach as a native sub-issue via the REST API (`gh api repos/{owner}/{repo}/issues/{map}/sub_issues -X POST -F sub_issue_id=<issue database id>` — fetch the database id from `gh issue view <n> --json id,number` / `gh api repos/{owner}/{repo}/issues/<n> --jq .id`). If the sub-issue API 404s on this repo/plan, the `Map: #<n>` body line is the parent link |
| Wire blocking | Native issue dependencies via REST: `gh api repos/{owner}/{repo}/issues/{n}/dependencies/blocked_by -X POST -F issue_id=<blocker database id>`. Probe once with a GET first; if dependencies aren't available, fall back to a `Blocked by: #a, #b` body line |
| Claim | `gh issue edit <n> --add-assignee "@me"` |
| Frontier | `gh issue list --state open --search "no:assignee label:wayfinder:research,wayfinder:prototype,wayfinder:grilling,wayfinder:task"` scoped to this map (`Map: #<n>` in body or sub-issue of it), then drop tickets with an open blocker |
| Resolve | `gh issue comment <n> --body-file <tmp>`, then `gh issue close <n>` |
| Update map | `gh issue edit <map> --body-file <tmp>` |
| Assets | Markdown links in the resolution comment (files committed to a branch, gists, docs) |

Verify API-shaped operations (sub-issues, dependencies) with one cheap read call before relying on them — availability varies by repo and plan. Fall back to body conventions without ceremony.

## Local markdown (no remote tracker)

For solo projects or repos without a usable remote. Everything lives under `.scratch/<effort-slug>/` (gitignore it or commit it — follow the repo's existing convention; ask once if there is none).

```
.scratch/<effort-slug>/
  map.md                 # the map — same body template as SKILL.md
  tickets/
    01-<slug>.md
    02-<slug>.md
```

Ticket file format:

```markdown
---
type: research | prototype | grilling | task
status: open | closed
claimed-by:            # empty = unclaimed
blocked-by: []         # ticket numbers, e.g. [01, 03]
---

## Question

<the decision or investigation this ticket resolves>

## Resolution

<appended on close>
```

| Operation | How |
|---|---|
| Create map / ticket | Write the file; number tickets from `01` in dependency order |
| Wire blocking | `blocked-by:` frontmatter |
| Claim | Set `claimed-by:` to the dev's name |
| Frontier | Open, unclaimed tickets whose `blocked-by` entries are all `status: closed` |
| Resolve | Append `## Resolution`, set `status: closed`, add the one-line pointer to `map.md` |
| Assets | Relative links to files in the repo or scratch folder |

## Persisting the choice

When the tracker was detected rather than configured, offer to write `docs/agents/issue-tracker.md` recording: which tracker, the team/project or repo it maps to, and any deviations (custom label names, no-dependencies fallback in use). Future sessions of every `*-plus` skill read that file first and skip detection.
