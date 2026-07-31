# Issue tracker: GitHub

Issues and specs for this repo live as GitHub issues. Use the `gh` CLI for all operations; confirm auth with `gh auth status` before writing anything.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body-file <tmp>` (heredoc or file for multi-line bodies)
- **Read an issue**: `gh issue view <number> --comments`
- **List issues**: `gh issue list --state open --json number,title,body,labels` with `--label`/`--search` filters
- **Comment**: `gh issue comment <number> --body-file <tmp>`
- **Labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`; `gh label create "..."` first (ignore already-exists errors) — never apply a label that hasn't been created
- **Close**: `gh issue close <number>`

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments`.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as tickets.

- **Map**: one issue labelled `wayfinder:map` holding the Destination / Notes / Decisions-so-far / fog body
- **Child ticket**: `gh issue create --label "wayfinder:<type>"` (`research`/`prototype`/`grilling`/`task`) with `Map: #<n>` as the body's first line; then attach as a native sub-issue via `gh api repos/{owner}/{repo}/issues/{map}/sub_issues -X POST -F sub_issue_id=<database id>` (database id from `gh api repos/{owner}/{repo}/issues/<n> --jq .id`, not the `#number`). If the sub-issue API 404s, the `Map: #<n>` body line is the parent link
- **Blocking**: native issue dependencies — `gh api --method POST repos/{owner}/{repo}/issues/{child}/dependencies/blocked_by -F issue_id=<blocker database id>`. Probe once with a GET first; where unavailable, fall back to a `Blocked by: #a, #b` body line. A ticket is unblocked when every blocker is closed
- **Claim**: `gh issue edit <n> --add-assignee "@me"` — the session's first write
- **Frontier**: open, unassigned children of the map with no open blocker; first in map order wins
- **Resolve**: `gh issue comment <n> --body-file <tmp>`, then `gh issue close <n>`, then append the context pointer to the map's Decisions so far
- **Assets**: markdown links in the resolution comment (files committed to a branch, docs)

Verify API-shaped operations (sub-issues, dependencies) with one cheap read before relying on them — availability varies by repo and plan. Fall back to body conventions without ceremony.
