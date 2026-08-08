# Issue tracker: Linear

Issues and specs for this repo live in Linear, via the `mcp__*Linear__*` MCP tools. Team/project: _(fill in — which Linear team and project this repo maps to)_.

## Conventions

- **Create an issue**: `save_issue` with `title`, `team`, body as `description`
- **Read an issue**: `get_issue` (comments via `list_comments`)
- **List issues**: `list_issues` with team/project/label/assignee filters
- **Comment**: `save_comment`
- **Labels**: `create_issue_label` (check `list_issue_labels` first — skip ones that exist)
- **Close**: `save_issue` with `state: "Done"` (or the team's completed state)

## Levels

The pipeline nests three levels, named for their agile equivalents. Each is a Linear issue:

| Agile name | Issue | Made by | Holds |
|---|---|---|---|
| **epic** | labelled `wayfinder:map` | `wayfinder` | many features |
| **feature** | the spec (PRD) description | `to-spec` | many stories |
| **story** | a sub-issue of the feature | `to-tickets` | one session of build work |

Small work starts at the feature level and never has an epic.

## When a skill says "publish to the issue tracker"

`save_issue` into the team/project above, with `parentId` set when the level has a parent.

## When a skill says "fetch the relevant ticket"

`get_issue` by id, plus `list_comments`.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with native sub-issues as decision tickets.

- **Map**: `save_issue` labelled `wayfinder:map`, holding the Destination / Notes / Decisions-so-far / Handed-off / fog body
- **Child ticket**: `save_issue` with `parentId: <map id>` and its `wayfinder:<type>` label (`research`/`prototype`/`grilling`/`task`)
- **Blocking**: `save_issue` update with `blockedBy: [<ids>]` — native relations, append-only
- **Claim**: `save_issue` update with `assignee: "me"` — the session's first write
- **Frontier**: `list_issues` with `parentId: <map>`, `assignee: "null"`, open state; drop any whose `blockedBy` relations contain an open issue
- **Resolve**: `save_comment` with the resolution, then `save_issue` to the completed state, then append the context pointer to the map's Decisions so far
- **Hand off**: `to-spec` creates the feature issue with `parentId: <map id>` and appends one line to the map's Handed off section. The map stays open — close it only after its last feature is handed off
- **Status**: `list_issues` with `parentId: <feature id>` per handed-off feature, counted by state. The map never stores build state
- **Assets**: `links: [{url, title}]` on the ticket
