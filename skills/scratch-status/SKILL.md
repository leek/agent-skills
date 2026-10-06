---
name: scratch-status
description: "Report what is still open across .scratch/: every effort's open tickets and decisions, what blocks it, how stale it is, and the next skill to run. Read-only — never files research, removes anything, or touches disk. Companion to scratch-cleanup, which does those."
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

In Claude Code with the leek-skills plugin, `/scratch [slug]` shows steps 1–2 live in a pane without a turn; point the user at it for a quick look. You cannot read that board, so always run the steps below: they add the commit-ancestry checks and the table the board lacks.

## 1. Inventory

Read the tracker layout from `.agents/issue-tracker.md` (fallback `docs/agents/issue-tracker.md`,
then `setup/issue-tracker.md` in this collection) and the status vocabulary from the matching
`triage-labels.md`. Then walk `.scratch/` (or just `.scratch/<slug>/` when scoped) and find every
**effort**: a directory holding a map, spec, decisions, tickets, or triage request files. Older
efforts may use an `issues/` folder instead of `tickets/`; treat it as tickets. Skip `research/`
and any unclassified file: this skill reports on efforts, not the whole inbox.

For each effort, note its last change date: `git log -1 --format=%cs -- <path>` for tracked
files, the file mtime otherwise.

Done when every effort under scope is found, with a date.

## 2. Read each effort

For every file in an effort (map, every decision ticket, the spec, every build ticket), read its
status in either dialect: the YAML frontmatter `status:` field, or a legacy `**Status:**` /
`Status:` line near the top of the body. Also read:

- **Blockers**: any `Blocked by` line or explicit dependency reference to another ticket's id.
- **Claimed-by**: whether the ticket is claimed, and by whom.
- **Commit references**: a 7–40 character hex SHA in the status line, `## Resolution`, or
  `## Comments`; check `git merge-base --is-ancestor <sha> <default-branch>` (default branch:
  `git symbolic-ref --short refs/remotes/origin/HEAD` without the remote prefix, else `main`).

Classify the effort exactly as `scratch-cleanup` does:

- **done**: every file's status is closed or the wontfix role string, every cited commit is on
  the default branch, and nothing contradicts (a spec still `ready-for-agent` while every ticket
  is closed is a contradiction, so is a closed ticket whose commit is missing).
- **mismatched**: fails the contradiction check, or has a file with no readable status.
- **open**: has any open file. Note the single most-blocked chain if one ticket blocks several
  others.

An open effort is **stale** when its newest file is older than 30 days, the same default
`scratch-cleanup` uses.

These rules are the source of truth; the `/scratch` board's `hooks/mods/scratch-scan.ts` must
change with them, so a drift shows as the board and this report disagreeing.

Done when every effort in scope is labelled done, mismatched, or open (with stale marked), and
every open ticket has its blockers and claim state noted.

## 3. Report

Print only this table, one row per effort in scope, most urgent first (unblocked open work,
then blocked open work, then stale, then mismatched, then done):

| Effort | Open work | Blocked by | Claimed by | Last change | Stale | Next |
|---|---|---|---|---|---|---|
| `.scratch/<slug>/` | open ticket/decision ids, by number | open blockers, or empty | claimant, or empty | date | yes/no | the skill that moves it forward |

`Next` names one concrete command: `/implement <ticket>` for an unclaimed unblocked build
ticket, `/grill-me <decision>` for an open decision, `/wayfinder <map>` for a map with no
tickets yet, `/to-spec` for a resolved map with no spec, `/to-tickets <spec>` for a spec with
no tickets. A **done** effort's `Next` is `/scratch-cleanup` (nothing else to do here). A
**mismatched** effort's `Next` is the one-line contradiction itself, so the user knows what to
settle before either skill can act on it.

Below the table, one line for any effort with no readable status file at all, naming the file.
End with a one-line total: `<n> open, <n> stale, <n> mismatched, <n> done`. Stop there: no
plan, no questions, no approval prompt, no restating the `Next` column in prose.
