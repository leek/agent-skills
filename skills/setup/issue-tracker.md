# Issue tracker: Markdown files

Every map, spec, and ticket for this repo lives as a markdown file in `.scratch/`: there is no external tracker. Whether `.scratch/` is committed or gitignored is the repo's own convention; skills that commit it check `git check-ignore -q .scratch` first. Only committed files reach a worktree.

## Conventions

**One effort, one directory, one of each artifact.**

```
.scratch/<slug>/
  map.md            # /wayfinder: decisions only; omit for small work
  decisions/        # /wayfinder: one file per decision ticket; /to-tickets adds Build decisions
    01-<slug>.md
  spec.md           # /to-spec: exactly one, written once
  tickets/          # /to-tickets: one file per build ticket
    01-<slug>.md
```

The pipeline runs straight through it: `/wayfinder` writes `map.md` and `decisions/`, `/to-spec` writes `spec.md` once and closes the map, `/to-tickets` writes `tickets/`, `/implement` works one file in `tickets/` per session.

- Small, already-clear work skips `map.md` and starts at `spec.md`; its `decisions/` holds only `to-tickets`' Build decisions ticket
- `decisions/` holds questions; `tickets/` holds build work. Nothing in `decisions/` is ever built, and nothing in `tickets/` is ever a question
- There is no `issues/` folder
- Build tickets are one file each, numbered from `01`; where a dependency is known give the blocker the lower number. Numbers only tie-break the frontier: `blocked-by` is what actually gates work
- The last build ticket is the **delivery ticket** (`delivery: true`), blocked by every other ticket: it proves the spec shipped whole and holds the after-deploy steps. It sits at `ready-for-human` between merge and those steps (see `to-tickets`' `DELIVERY-TICKET.md`)
- **Every tracker file carries YAML frontmatter** with at least `title` and `status`; tickets also carry `claimed-by` and `blocked-by`. Status is that frontmatter field, never a `**Status:**` line in the body. Write `title` in double quotes always (`title: "SLA report: LAT"`): a bare title that holds `: ` or starts with `[`, `{`, `#`, `*`, `&`, `!`, `|`, `>`, `%` or `@` is invalid YAML, and a bare title that holds ` #` is cut at the `#`. Inside the quotes, write a `"` as `'`
- Comments and conversation history append under a `## Comments` heading

## Status values

`status` is a YAML frontmatter field on every file. Which values are legal depends on the file:

| File | `status` values |
| --- | --- |
| Map (`map.md`) | `open` → `closed` (closed by `/to-spec`, or by a spec-less `/to-tickets`) |
| Decision ticket (`decisions/`) | `open` → `closed` |
| Spec (`spec.md`), build ticket (`tickets/`) | a triage role from `triage-labels.md` (`ready-for-agent` at publish), then `in-progress` (claimed) → `closed` (resolved) |

`in-progress` and `closed` are the build lifecycle, not triage roles; they are always legal on a spec or build ticket even though `triage-labels.md` lists only the triage roles.

The **Set status** operation refuses a value that is not legal for the file, and **Lint** reports each one already on disk. On an older file, `done`, `resolved`, `declined`, and `duplicate` still read as closed everywhere, but they are not legal to write, and Lint flags them.

## When a skill says "publish" a map, spec, or ticket

Create a new file at the level's path above, creating directories as needed.

## When a skill says "fetch the relevant ticket"

Read the file at the referenced path. The user will normally pass the path or the ticket title/number directly.

## Working in parallel: one checkout, no branches

Unblocked, unclaimed tickets may be worked by concurrent sessions in the **same checkout**. The tracker operations below never create a branch or a worktree (PR delivery and `implement-spec` do, for code); isolation comes from three rules:

- **One file per unit.** Each ticket and spec is its own file, so sessions on different units never write the same file.
- **Claim is compare-after-write.** The **Claim** operation writes the claim and reads the file again. Give it an id unique to *this session*: your name plus a short session-unique suffix, never the bare name (two of your own sessions would share it). A refused claim means another session holds the ticket: pick a different one. This is advisory, not a lock; a rare double-claim wastes at most one session and is caught at Resolve, which refuses a ticket that is already closed.
- **Shared files are derived or explicit-path.** The map's "Decisions so far" is *derived* from the closed tickets, never hand-appended (see Resolve). Code work stages only its own files by explicit path and reviews only those paths, so concurrent commits on the one branch neither capture nor review each other's changes.

## Wayfinding operations

Used by `/wayfinder`; Claim, Release, Frontier, Resolve, Close, Set status, and Lint work the same on build tickets and on a directly implemented spec. The **map** is the index; its decision tickets are one file each under `decisions/`.

**The script.** The mechanical operations are subcommands of `ticket.sh`, in the `setup` skill's `scripts/` directory. This file is a copy inside the repo, so the script is not beside it: a skill calls it as `bash <this-skill-dir>/../setup/scripts/ticket.sh <subcommand> …`, where `<this-skill-dir>` is the directory of the skill that is running. The operations below write that as `ticket.sh`. Run it inside the repo. `<path>` is one tracker file, and `<slug>` is the effort's directory name under `.scratch/`. It prints one JSON object and exits 0 when done, 1 when it refused (the JSON says why, and nothing was written) or Lint found errors, 2 on a usage error. It does not see a nested `tickets/<suffix>/` directory: read and edit those files by hand, by the same rules.

Map file format:

```markdown
---
title: "<map title>"
status: open
---

<the map body defined by `wayfinder`>
```

A map closes once `/to-spec` (or a spec-less `/to-tickets`) consumes it. Keep comments out of every frontmatter: an empty `claimed-by` means unclaimed, and `blocked-by` lists ticket numbers (`[01, 03]`).

Decision ticket format:

```markdown
---
title: "<ticket title>"
type: research | prototype | grilling | task
status: open | closed
claimed-by:
blocked-by: []
---

## Question

<the decision or investigation this ticket resolves>
```

A new ticket has no `## Resolution` text: Resolve adds it, and refuses a ticket that already has some. A ticket closed out of scope or superseded gets a `## Closed` note with the reason instead, and never appears in Decisions so far.

- **Create map / ticket**: write the file with its stable human-readable `title`; number tickets from `01`, blockers lower than what they block. Set each ticket's `blocked-by` as you create it (wire any remaining cross-edges in a second pass) so no ticket sits on the frontier mis-wired
- **Wire blocking**: `blocked-by:` frontmatter, written by hand; a ticket is unblocked when every listed ticket is closed
- **Lint**: `ticket.sh lint <slug>` checks every tracker file of the effort and changes nothing: the frontmatter block, the quoted title, a legal status, no comments, each blocker an existing ticket with a lower number, file names that start with their number, and one delivery ticket, numbered last and blocked by every other ticket. Prints `{"ok","errors":[{"file","rule","detail"}]}`; fix each error by hand
- **Claim**: `ticket.sh claim <path> --as <id>`, with an id unique to this session (*Working in parallel* above). On a build ticket (under `tickets/` or an older `issues/`) or a directly implemented spec it sets `status: in-progress` and `claimed-by`; on a decision ticket it sets only `claimed-by`. Prints `{"won":true,"path","status","claimed_by"}`. It refuses a closed, claimed, in-progress, or blocked item with `"won":false`, the `reason`, and its `open_blockers`. A second claim with your own id changes nothing and wins, so resume a ticket you already claimed by naming it. A run that builds several tickets and closes them at the end adds `--built <NN,NN>` (to Claim and to Frontier) with the tickets it has built: they stop counting as open blockers
- **Release**: `ticket.sh release <path> [--note "<text>"]` clears `claimed-by`. A build ticket at `in-progress` returns to `ready-for-agent` (or the AFK-ready role string); any other status, such as `ready-for-human`, is kept. `--note` appends the text under `## Comments`. Prints `{"path","status","claimed_by"}`. Release to hand a ticket back to the frontier, when you stop without resolving, or when parking a ticket to wait on outside input (a questionnaire's answers); the note says what it waits on
- **Frontier**: `ticket.sh frontier <slug> [--kind tickets|decisions]` reads every ticket and changes nothing. Prints `tickets` (each with `number`, `path`, `title`, `status`, `derived`, `claimed_by`, `claim_age_seconds`, `open_blockers`, `type`, `deploy_gate`, `delivery`), `frontier` (the ready numbers: open, unblocked, unclaimed; lowest first), `next` (the lowest, or `null`), and `counts`. Without `--kind` it reads `tickets/` when the effort has build tickets, otherwise `decisions/`. An unclaimed ticket at `ready-for-human` is `derived: human`, never on the frontier. A claimed ticket is never on the frontier either, stale or not: the script reports its `claimed_by` and `claim_age_seconds` (seconds since the file last changed), and you judge it
- **Stale claim**: a claim is stale only when its work is visibly committed or clearly abandoned (its session is gone). `claim_age_seconds` is evidence for that judgement, not the verdict: minutes of silence prove nothing (a long test writes no file), while an effort untouched for weeks is abandoned. Take a stale ticket over with Release, then Claim
- **Resolve**: write the answer to a temporary file, then `ticket.sh resolve <path> --body-file <file>`: it appends `## Resolution` with that text (or fills an empty heading), sets `status: closed`, and clears `claimed-by`. Prints `{"path","status","claimed_by"}`. It refuses an item that is already closed or already has `## Resolution` text. The decision now lives in the ticket; the map's **Decisions so far** is *derived* from the closed, resolved tickets, regenerate it from them when you need to read or show it, never hand-append (so parallel resolves can't clobber a shared list)
- **Close (out of scope / superseded)**: write the reason to a temporary file, then `ticket.sh close <path> --reason-file <file>`: it appends a `## Closed` note, sets `status: closed`, and clears `claimed-by`. Prints as Resolve does. Record an out-of-scope close in the map's **Out of scope**; a superseded close names the ticket that replaces it. A Close carries no `## Resolution`, so it stays out of Decisions so far
- **Set status**: `ticket.sh set-status <path> <status>` writes `status` alone and refuses a value that is not legal for the file (*Status values* above). Prints `{"path","status","previous"}`. Claim, Release, Resolve, and Close set their own status: use this for the rest (a map's close, a delivery ticket's `ready-for-human`, a triage role)
- **Hand off**: once every ticket is closed, `/to-spec` writes `spec.md` in the same directory and closes the map: `ticket.sh set-status .scratch/<slug>/map.md closed`. It runs once per map. On a spec-less handoff, `/to-tickets` closes the map instead
- **Assets**: relative links to files in the repo or scratch folder
