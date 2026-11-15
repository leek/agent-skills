# Threads and direction

How to read a PR's review comments before judging any of them: who wrote each one,
which threads a human owner has already decided, and which findings are one finding
said twice. Shared by `resolve-review-comments` and `triage-github-pr`; each skill
then judges, fixes, and replies by its own steps. The rows come from `pr-comments.sh`
(fields in its header).

## Claims and directions

A bot's review comment is a claim, not an instruction. Bots (Codex, Copilot, Gemini) are
confidently wrong often enough that **every bot finding earns its verdict from the code,
the spec, the tests, and the permission model, never from the comment's own say-so.**

An **owner's** word is different. An owner is your user (`me`), the PR author
(`pr_author`), or anyone whose `assoc` is `OWNER`, `MEMBER`, or `COLLABORATOR`, writing
as a human (`bot` false). When an owner has answered a thread ("approved", "yes, 'brings'
is correct", "no, leave it", "use X instead"), that answer is **the direction**: it
decides the verdict, and you carry it out. You verify how to carry it out, never whether
to. Anyone else's reply is context for the claim, and gets verified like the claim.

You post from your user's login, so read authorship from the row, not the login: a reply
with `agent` true is an agent's, from this run or an earlier one. Replies from before
that marker existed carry no flag; an unmarked `me` reply that opens with an agent reply
form ("Fixed in", "fixed in", "Reviewed,", "Left as is", "repeat of", "decided by owner")
is an earlier run's too. Every other `me` reply is your user talking to you.

## Build whole threads

Build each thread as its **whole conversation**, not just its root. `pr-comments.sh`
returns replies as separate `inline` rows: group every row whose `reply_to` is the
root's `id` under that root, oldest first. Then read the PR-level surfaces for direction
that covers threads: an owner's review body (`reviews`) or issue comment (`issue`) such
as "fix all of Codex's typo findings" or "ignore the Gemini nits" applies to every thread
it names.

Mark a thread **directed** when an owner's reply, an owner's PR-level comment that covers
it, or an owner's own root comment says what to do; the newest owner direction wins.
Record it verbatim with its author and time. A reply that only asks a question or thinks
aloud ("hm, is this right?") leaves the thread undirected, and your reply answers the
question.

## Re-anchor and cluster

Each bot reviews **one commit**. Compare it to current `HEAD`: a finding on an older
commit may already be fixed, or point at code that has since moved. Re-anchor every
comment to the current code before judging it.

Then **cluster duplicates**: two bots flag the same line for the same reason constantly.
Judge and fix a cluster once; reply to and resolve every thread in it. A direction on
one thread of a cluster directs the whole cluster; two owner directions that disagree
inside one cluster go to your user as a question.

## Carry out a direction

**Directed clusters are already judged.** The human direction is the verdict:

- An agreement ("approved", "yes", "agreed", "do it", a correction like "'brings' is
  correct") means **fix**, the way the direction says. When the reply names the exact
  change, make that change, not your own version of it.
- A refusal ("no", "leave it", "intentional", "won't fix") means **rebut**, using the
  human's reason.
- A different instruction ("rename it instead", "move this to a follow-up") means do
  that.

The direction outranks your own evidence: the spec, a ticket, the PR body, a source
file, a verifier line. When carrying it out contradicts a recorded spec or ticket, follow
it and name the conflict in the reply and in the final report so the spec gets updated. A
test that asserts exactly the value the direction changes changes with it. Ask your user
before acting only when the direction cannot be carried out as written (ambiguous, or
names code that does not exist) or when it turns some other green test red.

Directed clusters never go to the verifier workers: a worker cannot see your user's
authority, and its "not a bug" would silently overrule them. A worker that meets a
direction anyway returns it `UNSURE`, `directed by reply`, unjudged.

## Reply to a directed thread

Say what you did per the direction ("Fixed in <sha> as directed: 'brinks' → 'brings'.",
or "Left as is, per <author>'s reply: <reason>."), plus any spec conflict. Never answer a
human's direction with "Reviewed, not a defect".

Before sending a reply batch, check it: every directed thread's reply must match its
direction (an agreement gets a fix, a refusal gets a rebuttal). A mismatch is a bug in
this run; fix it before anything is posted.
