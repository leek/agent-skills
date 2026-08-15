# Issue tracker: Markdown files

Every map, spec, and ticket for this repo lives as a markdown file in `.scratch/` — there is no external tracker. Whether `.scratch/` is committed or gitignored is the repo's own convention; no skill needs to detect or care which.

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
- Build tickets are one file each, numbered from `01`; where a dependency is known give the blocker the lower number. Numbers only tie-break the frontier — `blocked-by` is what actually gates work
- **Every tracker file carries YAML frontmatter** with at least `title` and `status`; tickets also carry `claimed-by` and `blocked-by`. Status is that frontmatter field — never a `**Status:**` line in the body
- Comments and conversation history append under a `## Comments` heading

## Status values

`status` is a YAML frontmatter field on every file. Which values are legal depends on the file:

| File | `status` values |
| --- | --- |
| Map (`map.md`) | `open` → `closed` (closed by `/to-spec`, or by a spec-less `/to-tickets`) |
| Decision ticket (`decisions/`) | `open` → `closed` |
| Spec (`spec.md`), build ticket (`issues/`) | a triage role from `triage-labels.md` (`ready-for-agent` at publish), then `in-progress` (claimed) → `closed` (resolved) |

`in-progress` and `closed` are the build lifecycle, not triage roles; they are always legal on a spec or build ticket even though `triage-labels.md` lists only the triage roles.

## When a skill says "publish" a map, spec, or ticket

Create a new file at the level's path above, creating directories as needed.

## When a skill says "fetch the relevant ticket"

Read the file at the referenced path. The user will normally pass the path or the ticket title/number directly.

## Working in parallel — one checkout, no branches

Unblocked, unclaimed tickets may be worked by concurrent sessions in the **same checkout**. No skill creates a branch or a worktree; isolation comes from three rules:

- **One file per unit.** Each ticket, issue, and spec is its own file, so sessions on different units never write the same file.
- **Claim is compare-after-write.** To claim, set `claimed-by` to a value unique to *this session* — your name plus a short session-unique suffix, never the bare name (two of your own sessions would share it). Save, then re-read the file: if `claimed-by` is not your value, another session won the race — pick a different ticket. This is advisory, not a lock; a rare double-claim wastes at most one session and is caught at Resolve, when the second finder sees the ticket already closed.
- **Shared files are derived or explicit-path.** The map's "Decisions so far" is *derived* from the closed tickets, never hand-appended (see Resolve). Code work stages only its own files by explicit path and reviews only those paths, so concurrent commits on the one branch neither capture nor review each other's changes.

## Wayfinding operations

Used by `/wayfinder`. The **map** is the index; its decision tickets are one file each under `decisions/`.

Map file format:

```markdown
---
title: <map title>
status: open        # closed once /to-spec (or a spec-less /to-tickets) consumes it
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

<appended on Resolve; a ticket closed out of scope or superseded gets a
`## Closed` note with the reason instead, and never appears in Decisions so far>
```

- **Create map / ticket**: write the file with its stable human-readable `title`; number tickets from `01`, blockers lower than what they block. Set each ticket's `blocked-by` as you create it (wire any remaining cross-edges in a second pass) so no ticket sits on the frontier mis-wired
- **Wire blocking**: `blocked-by:` frontmatter; a ticket is unblocked when every listed ticket is `status: closed`
- **Claim**: compare-after-write per *Working in parallel* above — set `claimed-by` to a session-unique value, save, re-read to confirm you won
- **Release**: clear `claimed-by` to hand a ticket back to the frontier — when you stop without resolving, or when parking a ticket to wait on outside input (a questionnaire's answers); leave a `## Comments` note saying what it waits on
- **Frontier**: open, unblocked tickets that are unclaimed (or whose claim is stale — its session's work is abandoned); first by number wins. Resume a ticket you already claimed by naming it, so an in-flight claim never strands it
- **Resolve**: append `## Resolution`, set `status: closed`. The decision now lives in the ticket; the map's **Decisions so far** is *derived* from the closed, resolved tickets — regenerate it from them when you need to read or show it, never hand-append (so parallel resolves can't clobber a shared list)
- **Close (out of scope / superseded)**: set `status: closed` with a `## Closed` note giving the reason. Record an out-of-scope close in the map's **Out of scope**; a superseded close names the ticket that replaces it. A Close carries no `## Resolution`, so it stays out of Decisions so far
- **Hand off**: once every ticket is closed, `/to-spec` writes `spec.md` in the same directory and sets `map.md`'s frontmatter to `status: closed`. It runs once per map. On a spec-less handoff, `/to-tickets` closes the map instead
- **Assets**: relative links to files in the repo or scratch folder
