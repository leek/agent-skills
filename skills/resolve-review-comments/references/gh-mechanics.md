# GitHub mechanics

`PR` is the pull-request number. Every read and write of the PR's review state goes
through the `triage-github-pr` skill's `pr.sh`, installed beside this skill and run from
the repo; `<this-skill-dir>` is this skill's directory. What each subcommand prints, its
reply-file format, and its retry rule are owned by `triage-github-pr`'s
[GitHub mechanics](../../triage-github-pr/references/gh-mechanics.md): read its
**Gather** and **Reply and resolve** sections for the fields and the file. The calls this
skill makes:

```bash
bash <this-skill-dir>/../triage-github-pr/scripts/pr.sh comments PR             # threads (whole), reviews, issue, threads_open
bash <this-skill-dir>/../triage-github-pr/scripts/pr.sh reply PR <scratch>/pr-PR-replies.json   # reply to and resolve every thread
bash <this-skill-dir>/../triage-github-pr/scripts/pr.sh comments PR --count     # {threads_open}: the confirm step
```

Reply bodies for this skill: `"Fixed in <sha>. <behaviour now>. Test: <name>."` for a
fix, `"Reviewed, not a defect. <evidence: spec line / role leaf / existing test>."` for a
rebuttal, each with `"resolve": true`. A reply from a bot's own account is not needed;
your reply + resolve is the record.

## Watch the reviewers

A review is in flight while a requested reviewer has not submitted, a bot shows it is
running, a bot that reviews every push has not reviewed the head, or the PR was
pushed, opened, or marked ready under two minutes ago. One read checks all of it; run it from the repo:

```bash
bash <this-skill-dir>/../run-after/scripts/wait-until.sh --interval 30 --timeout 1200 -- bash <this-skill-dir>/../triage-github-pr/scripts/pr.sh state PR --in-flight --no-required
```

Run it in the background (in Claude Code, Bash with `run_in_background`; the harness
wakes you when it exits; Codex and other harnesses wait on it as `triage-github-pr`'s
**Taking the wait** says). `passed` means nothing is in flight; `timeout` means the
20-minute cap ran out, and `detail.counted` names who is still running; `failed` means
a read failed, so run it once more. The signals and the bots' behaviour are in
`triage-github-pr`'s
[In-flight signals](../../triage-github-pr/references/gh-mechanics.md#in-flight-signals).

## Commit range

The PR's commit range, to compare a reviewed commit against HEAD:

```bash
gh pr view PR --json headRefOid,commits
git log --oneline BASE..HEAD      # what the reviewer had vs what exists now
```

## Failed checks

After the wait, read the failed checks on the PR's head commit in one call:

```bash
bash <this-skill-dir>/../fix-ci-failures/scripts/failed-jobs.sh --pr PR --out <scratch>/pr-PR-ci
```

It prints each failing workflow's failed jobs with `first_errors` and `log` (the full
log's path); `[]` means no completed run on that commit failed.
