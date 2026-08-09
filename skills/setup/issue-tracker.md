# Issue tracker: Markdown files

Every map, spec, and ticket for this repo lives as a markdown file in `.scratch/` — there is no external tracker (gitignore `.scratch/` or commit it, following the repo's existing convention; ask once if there is none).

## Conventions

**One effort, one directory, one of each artifact.**

```
.scratch/<slug>/
  map.md            # /wayfinder — decisions only; omit for small work
  decisions/        # /wayfinder — one file per decision ticket
    01-<slug>.md
  spec.md           # /to-spec — exactly one, written once
  issues/           # /to-tickets — one file per build ticket
    01-<slug>.md
```

The pipeline runs straight through it: `/wayfinder` writes `map.md` and `decisions/`, `/to-spec` writes `spec.md` once and closes the map, `/to-tickets` writes `issues/`, `/implement` works one file in `issues/` per session.

- Small, already-clear work skips `map.md` and `decisions/` and starts at `spec.md`
- `decisions/` holds questions; `issues/` holds build work. Nothing in `decisions/` is ever built, and nothing in `issues/` is ever a question
- Build tickets are one file each, numbered from `01` in dependency order — never a single combined tickets file
- Triage state is a `Status:` line near the top of each file (see `triage-labels.md` for the role strings)
- Comments and conversation history append under a `## Comments` heading

## When a skill says "publish" a map, spec, or ticket

Create a new file at the level's path above, creating directories as needed.

## When a skill says "fetch the relevant ticket"

Read the file at the referenced path. The user will normally pass the path or the ticket title/number directly.

## Wayfinding operations

Used by `/wayfinder`. The **map** is the index; its decision tickets are one file each under `decisions/`.

Map file format:

```markdown
---
title: <map title>
---

<the map body defined by `wayfinder`>
```

Decision ticket format:

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
- **Hand off**: once every ticket is closed, `to-spec` writes `spec.md` in the same directory and appends `**Status:** closed` to `map.md`. It runs once per map
- **Assets**: relative links to files in the repo or scratch folder
