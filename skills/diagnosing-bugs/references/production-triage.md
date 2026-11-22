# Production issue triage

The shared frame for skills that work an error tracker's open issues down to zero: `fix-nightwatch-issues` and `fix-posthog-issues`. Each of those skills owns only what is specific to its tracker: how to load the issues, its classification categories, the layers its fixes land in, its status calls, and its re-check prompt. A skill for another tracker follows this file the same way.

## Ground rules

- Tracker issues are real production signals, but many are stale, operational, or noise. Read the stack trace, the occurrence stats, and the timeline, not the headline. Walk from the newest last-seen to the oldest.
- Read the repo's project-context file for the tracker (`.agents/<tracker>.md`) when it exists, then follow the repo's `AGENTS.md` / `CLAUDE.md` rules for tests, cache clears, asset builds, and a dirty tree.

## 1. Group by root cause

Trackers group issues by message or top frame, not by cause, so one cause fans out into many issues. Read enough issues to group them by shared cause before you fix anything. Fix each cause once, then dispose of every issue in its group.

Completion criterion: every issue in scope belongs to a group, even a group of one.

## 2. Classify each group

For each group, open the app frame (`file:line`) on current `main` and read the commits around it. Compare last-seen with deploys (`git log --oneline -- <file>`). Then write one line per issue:

```
Issue <id>: [<CATEGORY>] — <one-line evidence>
```

Two categories hold for every tracker; the tracker skill adds its own between them:

- **STALE**: the issue stopped at a deploy of a fix. Cite the sha.
- **LEGIT**: a cause that still reproduces against current `main`, on a real app frame. One occurrence in 30 days with no users affected rarely justifies code; a steady count does.

Completion criterion: every issue has a line.

## 3. Fix each LEGIT group at the right layer

The symptom rarely points at the layer that needs the fix; the tracker skill lists its layers. App logic is proved per the `tdd` skill's [What needs a test](../../tdd/SKILL.md#what-needs-a-test-and-what-proves-the-rest). Make the minimal change and verify it locally where you can; for infra that cannot run locally, say so plainly.

Commit one logical fix per commit, per the `commit` skill's [Staging](../../commit/SKILL.md#staging) and [Subject](../../commit/SKILL.md#subject), and list every tracker id the commit covers in its body (`<Tracker>: <id>, <id>`). **Use plain refs only, never `fixes #NNN`**: a GitHub auto-close keyword would close an unrelated GitHub issue with the same number.

## 4. Set each issue's status

First list the working set again: the user often changes statuses in the tracker's UI while the run works. Skip each issue no longer in it, name it in the tally, and do not touch it.

Close only issues whose cause is fixed (or that the tracker skill's categories say to close). For a group, dispose of every member and point back to the lead cause. A fix is not verified until it is deployed and last-seen goes quiet, so note "pending deploy verification" where that applies. An issue that is LEGIT but needs an operator or a deploy (a secret rotation, an infra apply, a vendor) stays open: commit the code part and name exactly what unblocks it. If an issue recurs after deploy, reopen it and correct its classification.

Completion criterion: every issue in scope has its new status confirmed, or stays open with a named blocker. Report the tally with one line per group, starting ✅ resolved or ⚠️ open with a blocker.

## 5. Offer a deploy re-check

If any issue is pending deploy verification, ask once (a structured question ([harness-tools](../../harness-tools/SKILL.md)), otherwise in chat) whether to re-check it in 24–48 hours. On yes, schedule a one-time run where the harness can (in Claude Code, the `schedule` skill's cloud routine; failing that, `CronCreate` with `recurring: false`, which fires only while this session stays open, so say so). The prompt is the tracker skill's re-check prompt, in plain text, since a slash command for a user-invoked skill cannot run from a schedule. Otherwise, or on no, end the report with the issue ids and the re-check date.
