# Issue tracker: Local Markdown

Issues and specs (you may know a spec as a PRD) for this repo live as markdown files in `.scratch/` (gitignore it or commit it — follow the repo's existing convention; ask once if there is none).

## Conventions

- One feature per directory: `.scratch/<feature-slug>/`
- The spec is `.scratch/<feature-slug>/spec.md`
- Implementation issues are one file per ticket at `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, numbered from `01` in dependency order — never a single combined tickets file
- Triage state is a `Status:` line near the top of each issue file (see `triage-labels.md` for the role strings)
- Comments and conversation history append under a `## Comments` heading

## When a skill says "publish to the issue tracker"

Create a new file under `.scratch/<feature-slug>/` (creating the directory if needed).

## When a skill says "fetch the relevant ticket"

Read the file at the referenced path. The user will normally pass the path or the issue number directly.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a file with one **child** file per ticket, under `.scratch/<effort-slug>/`:

```
.scratch/<effort-slug>/
  map.md                 # the map — Destination / Notes / Decisions so far / fog
  tickets/
    01-<slug>.md
    02-<slug>.md
```

Map file format:

```markdown
---
title: <map title>
---

<the map body defined by `wayfinder`>
```

Ticket file format:

```markdown
---
title: <ticket title>
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

- **Create map / ticket**: write the file with its stable human-readable `title`; number tickets from `01` in dependency order
- **Wire blocking**: `blocked-by:` frontmatter; a ticket is unblocked when every listed ticket is `status: closed`
- **Claim**: set `claimed-by:` to the dev's name and save before any work
- **Frontier**: open, unclaimed tickets whose blockers are all closed; first by number wins
- **Resolve**: append `## Resolution`, set `status: closed`, add the one-line pointer to `map.md`'s Decisions so far
- **Assets**: relative links to files in the repo or scratch folder
