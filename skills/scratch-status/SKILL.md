---
name: scratch-status
description: "Report what is still open across .scratch/ and the next skill to run for each effort. Read-only."
disable-model-invocation: true
argument-hint: "An effort slug to check just one (omit for every effort)"
model: sonnet
effort: low
---

# Scratch Status

A quick answer to "what's left to do in `.scratch/`", with nothing written or removed. For
the full sweep (filing research, removing done efforts, judging contradictions), that is
`scratch-cleanup`; this skill only ever reports.

`$ARGUMENTS` is an effort slug to scope to `.scratch/<slug>/` alone; empty means every effort.

In Claude Code with the leek-skills plugin, `/scratch [slug]` shows the effort board live in a pane without a turn; point the user at it for a quick look. You cannot read that board, so always run the steps below: they add the commit-ancestry checks and the per-artifact report the board lacks.

## 1. Scan `.scratch/`

From inside the repository, run [`scripts/scratch-state.sh`](scripts/scratch-state.sh) `$ARGUMENTS` once.

The script walks `.scratch/` (or `.scratch/<slug>/` when scoped), reads `.agents/triage-labels.md`
(fallback `docs/agents/triage-labels.md`) when present, parses frontmatter and legacy `Status:`
lines across maps, specs, `decisions/`, `tickets/` (or legacy `issues/`), and triage request
files, checks every cited commit SHA against `default_branch` (`git merge-base --is-ancestor`,
merged PRs via `gh api`, `git cherry`, and commit subject match), and emits one JSON object
ranking efforts most urgent first:

- **done**: every file's status is closed or the wontfix role string, every cited commit is on
  `default_branch`, and nothing contradicts (`mismatch` is `null`). A spec with tickets is
  closed by derivation: it is complete (`spec.complete`) once every ticket is closed, whatever
  its own status, because nothing writes `closed` onto it. A spec with no tickets was
  implemented directly and needs its own closed status.
- **mismatched**: fails the contradiction check (`map` still open while `spec.md` exists, a
  closed ticket whose cited commit is missing from `default_branch`, or a file with no readable
  status).
- **open**: has any open file, with `stale: true` when its newest file is older than 30 days
  (a tracked file's last commit, an untracked file's modification time).

These rules are the source of truth; the `/scratch` board's `hooks/mods/scratch-scan.ts` must
change with them, so a drift shows as the board and this report disagreeing. Two things stay
skill-only: the cited-commit check, and the `also` alternatives.

Done when `scripts/scratch-state.sh` has returned the JSON state for every effort in scope.

## 2. Report

One block per effort in `efforts`, in the order the script returned them (unblocked open work,
then blocked open work, then stale, then mismatched, then done). A **done** effort collapses to
one line:
`` `.scratch/<slug>/` — done, last change <last_change>. Next: `/scratch-cleanup` ``. Every other
effort gets the full block:

```markdown
### `.scratch/<slug>/`: <open | mismatched> · last change <date><, stale>

<⚠️ mismatched: <mismatch> | ⚠️ stale: no change in <stale_days> days>

**Map**: <title>, <status>. Destination: <one line>.
**Spec**: <title>, <status | complete>. <problem, one line>. <n> open questions.

**Decisions**: <n> open of <n>
| # | Decision | Status | Resolution or blocker |
|---|---|---|---|
| 01 | <title> | closed | <resolution, one line> |
| 02 | <title> | blocked | by 01 |

**Tickets**: <n> open of <n>
| # | Ticket | Status | Detail |
|---|---|---|---|
| 01 | <title> | ready | |
| 02 | <title> | blocked | by 01 |
| 03 | <title> | in progress | claimed by <claimant> |
| 04 | <title> | closed | <short SHA>, on <default-branch> |

**Next**: `<command>`: <why, one line>.
<Also: up to two alternatives, one line each, only when they exist.>
```

Section rules:

- An absent artifact gets one line, so its absence is visible: `**Map**: none.`,
  `**Spec**: none.`, `**Decisions**: none.`, `**Tickets**: none.` Older efforts' `issues/`
  folder reports as Tickets; a loose triage request file in `requests` gets its own line,
  `**Request** <file>: <title>, <status>.`
- List every decision and ticket, closed ones too, in number order.
- **Status** uses `derived_status` (`closed`, `in progress`, `blocked`, `ready`, or
  `unreadable`, which you print as `⚠️ unreadable`; when `wontfix` is true, say `wontfix` in
  Detail).
- **Detail** for a ticket: `open_blockers` (`by 01, 03`), `claimed_by`, or for a closed
  ticket its cited `commits` (`<sha>, on <default_branch>` or `⚠️ <sha> missing`). Empty when
  there is nothing to say. A decision's last column is its `resolution` once closed, its
  `open_blockers` or `claimed_by` while open.
- The heading carries the plain words `mismatched` and `stale`, never a mark. The ⚠️ status
  line under it appears only for a mismatched or stale effort; an effort that is neither has
  no such line.
- **Spec** prints `complete` in place of the status when `spec.complete` is true and the
  spec's own status is not closed.
- Mark nothing else with ⚠️: only stale, mismatched, unreadable, and missing commits.
- **Next** uses `next` and `next_why`; when mismatched, `next` is the contradiction already on
  the ⚠️ status line, so **Next** prints `next_why` alone.
  **Also** prints the entries in `also` when non-empty.

After the last block, one line naming any path in `unreadable_efforts`, then a one-line total
from `counts`: `<open> open, <stale> stale, <mismatched> mismatched, <done> done`. Stop there:
no plan, no questions, no approval prompt.
