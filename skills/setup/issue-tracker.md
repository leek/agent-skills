# Issue tracker: Markdown files

Every epic, feature, and story for this repo lives as a markdown file in `.scratch/` — there is no external tracker (gitignore `.scratch/` or commit it, following the repo's existing convention; ask once if there is none).

## Levels

The pipeline has three artifact levels, named for their agile equivalents:

| Agile name | Artifact | Made by | Holds |
|---|---|---|---|
| **epic** | `map.md` and its decision tickets | `wayfinder` | many features |
| **feature** | `spec.md` | `to-spec` | many stories |
| **story** | one file under `issues/` | `to-tickets` | one session of build work |

Small work starts at the feature level and never has an epic. An epic holds **decisions**, never build work.

## Conventions

A feature with no epic:

```
.scratch/<feature-slug>/
  spec.md
  issues/
    01-<slug>.md
```

An epic and the features it hands off:

```
.scratch/<epic-slug>/
  map.md
  decisions/                # the epic's decision tickets
    01-<slug>.md
  specs/
    01-<feature-slug>/
      spec.md
      issues/               # that feature's stories
        01-<slug>.md
```

- `issues/` is always a sibling of the `spec.md` it belongs to, at either level
- Stories are one file per story, numbered from `01` in dependency order — never a single combined tickets file
- Triage state is a `Status:` line near the top of each story file (see `triage-labels.md` for the role strings)
- Comments and conversation history append under a `## Comments` heading

## When a skill says "publish to the issue tracker"

Create a new file at the level's path above, creating directories as needed.

## When a skill says "fetch the relevant ticket"

Read the file at the referenced path. The user will normally pass the path or the issue number directly.

## Wayfinding operations

Used by `/wayfinder`. The **map** is the epic's index; its decision tickets are one file each under `decisions/`.

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
- **Hand off**: `to-spec` writes the feature to `specs/<NN>-<feature-slug>/spec.md` and appends one line to `map.md`'s Handed off
- **Status**: read every `specs/*/issues/*.md` and count stories by `Status:`; the map itself never stores build state
- **Assets**: relative links to files in the repo or scratch folder
