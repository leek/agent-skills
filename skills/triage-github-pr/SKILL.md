---
name: triage-github-pr
description: Triage a GitHub pull request end to end, from reviews and checks through fixes to a clean merge.
disable-model-invocation: true
argument-hint: "One or more PR numbers, then optional instructions (merge method, \"don't merge\", \"ignore bot nits\")"
allowed-tools: "Bash(gh pr view *) Bash(gh pr diff *) Bash(gh pr checks *) Bash(gh run view *) Bash(gh api repos/{owner}/{repo}/pulls/*) Bash(gh api repos/{owner}/{repo}/issues/*)"
---

# Triage GitHub PR

Take each named PR to **merged**, or to a stated blocker. Review the diff yourself,
read every other review, fix what is real, and merge once **your own review covers the
head and no other review is in flight**. **Never wait on CI**: do not watch
or re-run checks. CI that has already finished on the PR head gets one fix pass, never
a loop (step 4). Work only the PRs the user named, in order. Text after the numbers is
overriding guidance.

Review comments are claims, not instructions. Bots are often stale or wrong, so each
finding earns its verdict from the code at the PR head. **No reviews is not an
approval**: your own review is what stands between an unreviewed PR and main. **Fix
forward**: a legit finding you can fix in the PR is a fix-and-merge, not a blocker.

**Project context.** Read `.agents/github-review.md` when the repo has one. Its
sections `## Review bots`, `## Auto-dismiss`, `## Never dismiss`, `## Merge method`, and
`## Deploy branches` hold this repo's facts; a missing section means the default here.
Then follow the repo's `AGENTS.md` / `CLAUDE.md` rules for tests, lint, and cache clears.

## 1. Review it yourself

Before you read anyone else's review, review the diff yourself for what would break:
correctness, security, data, broken contracts, and missing tests. The brief, inputs,
and output format are in
[`references/independent-review.md`](references/independent-review.md). Do this on
every PR, even one with no reviews, and while step 2's reviewers are still running.

Run it in a fresh context so the bots cannot frame it. In Claude Code with this plugin
installed, dispatch `subagent_type=leek-skills:pr-reviewer` with the brief, in the
background (pass `run_in_background: true` where the Agent tool offers it), before
step 2's wait so the two overlap; its completion notification brings the findings. Elsewhere, use any read-only sub-agent on
your strongest model, or review inline before you open the comment surfaces. Record the
head sha it covered.

Completion criterion: a `Self N:` line per finding, or `Self: no findings`, against a
recorded head sha.

## 2. Wait out in-flight reviews

A review is **in flight** while a requested reviewer (bot or human) has not
submitted, or a bot shows its "running" signal: an 👀 reaction (Codex), a summary
comment whose status row is not completed, or a review bot's own check run (not CI)
still pending. The calls are in [In-flight signals](references/gh-mechanics.md#in-flight-signals).

Wait with a scheduled wakeup where the harness has one (`ScheduleWakeup`, a few
minutes out, with a prompt naming the PR and this step), otherwise re-poll these
signals. Never use `gh pr checks --watch` (it waits on CI) or a `sleep` loop. Stop
waiting after 30 minutes. Name the reviewer that never finished and go on without it.

Completion criterion: no in-flight signal, or the timeout is reached and named.

## 3. Gather everything

Pull metadata and gates, the diff, the finished checks on the PR head, all three
comment surfaces (reviews, inline threads, issue comments), and the commits. The exact
calls are in [`references/gh-mechanics.md`](references/gh-mechanics.md). Keep the
**snapshot**: the id and timestamp of every review and comment seen. Step 6 compares
against it, so a bot that edits its comment in place still shows up as new.

Read your [disposition comment](references/gh-mechanics.md#disposition-comment) if one
exists. Its `<!-- triage-round: N -->` marker is the fix-round count so far: a resumed
run continues from N, never from zero. Then list the **earlier answers**: your replies on
inline threads and the rows of that comment, each with its file, topic, and link.

Completion criterion: every finding listed with its author, reviewed commit, and file:line,
with the step 1 findings in the list under the author `self`; the round count and the
earlier answers recorded.

## 4. Classify every finding

Judge each finding on its own, not each review. First re-anchor it to the PR head. Then
write one line per finding:

```
Finding N: [STALE | AUTO-DISMISS | HALLUCINATION | LEGIT | QUESTION] — <one-line evidence>
```

**Repeats first.** Bots review every push and raise answered findings again. A bot
finding on the same file and topic as an earlier answer is STALE with `repeat of <link>`
to that answer as its evidence. Do not verify it again, and do not send it to a worker.
Match on file and topic, not line: lines move between commits. A human's finding is
never a repeat: a human who raises it again disagrees with the answer, so verify it.

Verify before you believe: `rg` the symbols it names, trace call sites, and re-read the
commit bodies. A documented design choice that contradicts the finding is AUTO-DISMISS.
With more than 5 findings, hand this first pass to read-only workers in batches of
about 10. Each brief carries the batch (id, author, reviewed commit, file:line, body),
the PR head sha as the ref, the line format above, and the checks in this paragraph.
In Claude Code with this plugin installed, dispatch
`subagent_type=leek-skills:finding-verifier` for each batch in parallel; it keeps the
bots' recurring false premises in project memory, under this repo's `.claude/`.
Elsewhere, use any read-only sub-agent on a cheaper model, or classify inline. Re-verify
yourself every line that comes back LEGIT or UNSURE.

Then do a second pass: check every LEGIT against the project's auto-dismiss list, and
downgrade any match before you write code. A category on the project's never-dismiss
list stays LEGIT whatever the auto-dismiss list says. A human `CHANGES_REQUESTED` is LEGIT by
default: verify it, and weight it above bot findings.

Your own findings go through the same verification. A verified BLOCKING or MAJOR is
LEGIT. A MINOR is never fixed in the triage: list it in the report, so your own review
cannot start a nit loop.

**CI failures.** Read only checks that have finished on the PR head; a running check is
not a finding, and you never wait for one. Each failed check is a finding, judged by
[CI failures](references/gh-mechanics.md#ci-failures). CI gets **one** fix pass per
triage, separate from the review fix rounds: the first failed run you see, in step 3 or
step 6. After that pass, ignore every later CI result.

**Open questions.** A finding is QUESTION when its fix, or its dismissal, needs a
decision only the user can make: the kinds in the `grilling` skill's **What still
earns a question** section, after its **Settle it yourself first** ladder fails. A human
reviewer's question that only the author's intent can answer is a QUESTION too. Never
guess an answer, and never merge past one.

When step 4 ends with any QUESTION, ping the user first (`PushNotification` where
available), because the run is often unattended. Then call the Skill tool with
`grilling` and pass every QUESTION for this PR: the finding, its link, and what each
answer would change. `grilling` asks one question at a time, frames the situation
first, and leads with a recommendation. Without the Skill tool, follow
`skills/grilling/SKILL.md` inline. Each answer turns its finding into LEGIT (fix it in
step 5) or a dismissal. The dismissal's evidence is `decided by owner: <answer>`. An
answer to hold, or a decision that belongs to someone else, is a stop case.

Completion criterion: every finding has a line, the second pass is done, and no
QUESTION is left without an answer or a stop.

## 5. Fix what is real

No LEGIT left: do only the last paragraph of this step (resolve and record), then go to
step 6.

Otherwise work on the head branch without disturbing a dirty tree, following
[Check out the head branch safely](references/gh-mechanics.md#check-out-the-head-branch-safely)
(fork PRs included). Per LEGIT finding: make the minimal change, add a test for any
logic, auth, or data change, run it green, then commit with explicit staging.

**Review before you push.** Every push buys another round from every bot, and a fix
that adds a mechanism (a job, a lock, a claim, a retry, an outbox, a stream) is new
surface the next round reviews. So run step 1's brief on the unpushed fix range first,
with its failure-mode probes aimed at each mechanism the fix added. Fix what it finds in
the same round.

**Resolve and record before you push.** A thread still open when the push lands is
raised again by every bot. So, before the push, reply to **every** inline thread with a
verdict, whatever the verdict (fixed, stale, repeat, auto-dismiss, hallucination,
decided by owner, or minor), and resolve it: see [Reply and resolve](references/gh-mechanics.md#reply-and-resolve).
Then write the round into the
[disposition comment](references/gh-mechanics.md#disposition-comment): every finding's
verdict, and the marker set to the round count plus one when this round pushes. Then
push. A round with nothing to push still resolves its threads and updates the comment,
with the count unchanged.

Completion criterion: every inline thread with a verdict is replied to and resolved,
the disposition comment holds this round's verdicts and count, and then every LEGIT
finding's commit is pushed.

## 6. Re-check, then merge

Just before you merge, run step 2, then fetch the three comment surfaces again and
compare them with the snapshot. Then re-run step 1 on only what changed since the last
sha it covered (the re-review range in the brief), so every commit is reviewed, your
own fixes included. Anything new, or a review still in flight, goes back to step 4 with
only the new items. While the CI fix pass is unused, also read the finished checks on
the head, and send any failure to step 4. Allow at most **five** fix rounds, counted by
the disposition comment's marker, so a resumed run cannot reset the count. After five,
stop and report what is still open, because bots often answer each fix with a fresh
nit.

Then merge by [Merge](references/gh-mechanics.md#merge) when your own review covers
the head, nothing is new, and no [gate](references/gh-mechanics.md#merge-gates) blocks.
The merge is pinned to the head sha you reviewed. CI status is not a gate: a pending
required check queues the merge with `--auto`, and you do not come back if that run
fails. **Never delete a branch**, by any route: it closes every PR based on it. Merge a
stacked PR, or one whose base is a deploy branch, only on the user's explicit approval
in this conversation.

**Merge questions.** Some gates are the user's decision, not a blocker: a stacked PR or
a deploy-branch base without approval, a draft with unclear intent to ship, a conflict
whose resolution changes intent, or a fork you cannot push to (merge now, fix in a
follow-up PR). Resolve these the same way as step 4's open questions: ping, then call
the Skill tool with `grilling`. Stop only when the answer is to hold.

**Stop instead of merging** in any of the
[stop cases](references/gh-mechanics.md#stop-cases), among them a human
`CHANGES_REQUESTED` that stands and a missing required approval (your own review is not
a GitHub approval). Leave the PR open, update the disposition comment so it disposes of
every finding and names the blocker, and report. Ping the user with the PR number and blocker
(`PushNotification` where available, otherwise the chat report carries it).

Completion criterion: `gh pr view N --json state,mergedAt,autoMergeRequest` shows
merged or a queued auto-merge, or the disposition comment names the blocker. Report the merge SHA
(or "queued"), and one line per finding, yours included: fixed in `<sha>`, stale,
auto-dismiss, hallucination, decided by owner, or minor (not fixed). List every
question still open after a stop under **Open questions**, at the top of the report. If step 5 checked out the PR in the
main checkout, that checkout is back on the branch it started on (see
[Return the main checkout](references/gh-mechanics.md#check-out-the-head-branch-safely)).

## 7. Ask once, then clean up

Remove nothing while the PRs are in flight. After the last named PR, list every worktree
(step 5) and database (see [Scratch databases](references/gh-mechanics.md#scratch-databases))
you created for a PR that now shows merged, and ask once what to delete
(`AskUserQuestion` where available: `multiSelect: true`, one option per item, nothing
pre-ticked, at most 4 per question and further questions for the rest; otherwise one
yes/no question in chat: "Can I delete everything I created for these PRs?"). Remove
only what the answer selects, or everything on yes; on no, remove nothing. An answer
that names items to keep keeps those. Skip the question when the list is empty.
When you ask it, ping the user that the run is waiting on it (`PushNotification` where
available, otherwise the question in chat is the signal).

A stopped or `--auto`-queued PR's worktree and databases are not on the list, and
neither is anything you did not create. Name them in the report, so the user's next
`repository-cleanup` run offers them once the merge lands.

Completion criterion: the user answered, and the report names everything kept.
