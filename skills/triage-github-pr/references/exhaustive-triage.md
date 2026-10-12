# Exhaustive triage

Read this only when the user explicitly asks to keep iterating until reviews are
clean. A bare PR number, an entire queue, or a resumed bounded run does not enable it.
The main skill still owns classification, thread dispositions, local validation,
exact-head review, merge gates and cleanup.

## Wait for optional reviews

Use the [in-flight signals](gh-mechanics.md#in-flight-signals). Schedule a wakeup a
few minutes out where the harness supports it (`ScheduleWakeup`), otherwise re-poll
with the host's wait/yield mechanism. Keep progress event-driven as the main skill
allows. Never watch CI or use a shell sleep loop.

Optional waits share the main skill's 20-minute total budget per PR, at most 10
minutes per checkpoint; record time used across rounds and resumes. Once exhausted,
name any reviewers that did not finish and proceed with the reviews available.
A later user instruction to merge now and move new findings to another PR
immediately returns to bounded delivery. Hard merge
gates still apply.

## Round budget

A round is a push after the PR opened. Count it from
[GitHub activity](gh-mechanics.md#count-rounds), including pushes before this run;
resuming or restarting cannot reset the count.

| Latest round | Fix in this PR | Merge when |
|---|---|---|
| 0–3 | Every LEGIT finding, MINOR included | No LEGIT finding remains |
| 4 | BLOCKING and MAJOR with the smallest fix that adds no new mechanism; carry MINOR | No open BLOCKING or MAJOR |
| 5 (maximum) | No further fix push | No open BLOCKING or MAJOR; carry MINOR |

At round 5 or beyond, stop with open BLOCKING and MAJOR findings named as blockers;
never make a sixth fix push. If a round-4 defect cannot be fixed without a new
mechanism, name it as a blocker rather than carrying it or expanding the final batch.
If no BLOCKING or MAJOR findings remain, carry the rest and merge. A carried finding
preserves its severity and is
replied to, resolved and listed for the follow-up owned by the main skill.

Before each push, update dispositions and independently review the unpushed fixes.
After it, wait within the limit above, gather changed comment surfaces and classify
only new claims. Repeat only when this table requires another fix. When clean, return
to step 6's exact-head merge checkpoint.
