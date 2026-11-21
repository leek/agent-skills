# Several PRs

Read this when the run has more than one PR, or one stacked on or merging after another.
Step numbers are the main skill's.

With more than one PR, run the read-only steps for all of them at once, write the fixes
of independent PRs in parallel, and push and merge one PR at a time. You stay the
orchestrator. Never hand a whole PR to a sub-agent:
a sub-agent cannot start its own reviewers, ask the user, or schedule a wakeup, and the
steps need all three.

1. **Snapshot.** "All open PRs", a label, or a range means the PRs that match when the
   run starts. List them once; that list is the run. A PR opened during the run goes in
   the report as `opened mid-run, not triaged`, unless the user asked for new PRs to be
   taken too.
2. **Order.** Build the **merge plan** per
   [`merge-order.md`](merge-order.md): edges from stack bases
   and merge-after lines in PR bodies, then the user's stated order as the fallback
   (a PR's order always wins over the user's), sorted bottom-up and printed before
   any write. A PR whose base is another open PR's
   head is **stacked**: [`stacked-prs.md`](stacked-prs.md)
   builds its stack and owns its merge method, retargets, and fixes that must flow
   upward. A PR merges only after every PR before it on an edge shows `MERGED`; a
   stopped or queued one holds its dependents. Independent PRs keep the user's order.
3. **Step 1 for all PRs at once.** Dispatch one `pr-reviewer` per PR in the
   background, in one message (other harnesses: dispatch in the background per
   [harness-tools](../../harness-tools/SKILL.md) with a fresh context and the full brief). A stack's integration
   PR waits for its own turn after the landings, and steps 2–4 skip it until then.
4. **Steps 2 and 3 for all PRs.** Gather reviews and review state for every PR.
   Watch every PR's reviewers with one wait for the queue (several numbers in one
   `--in-flight` read), as the shipping budget says.
5. **Step 4 in one pool.** Send the findings of all PRs to the verifier workers
   together, each batch from one PR, so its head sha is the ref. Then collect the
   QUESTIONs of every PR into one `grilling` call, each one named with its PR number,
   so the user is asked once.
6. **Steps 5 and 6 one PR at a time, in merge-plan order, sharing the batch-1 wait.**
   Use a worktree for every PR
   (`.claude/worktrees/pr-N`), never the main checkout, so no two PRs share a tree.
   **Fixers per PR:** every PR whose merge does not wait on another open PR (no stack
   base, no merge-after edge) and has current-batch findings gets its fixes written by
   fixer sub-agents per [Parallel fix batch](parallel-fixes.md), one per PR (or one per
   file group when that PR's batch splits), all started in one message (other harnesses:
   dispatch in the background per [harness-tools](../../harness-tools/SKILL.md) with a
   fresh context and the full brief). While they run, keep
   verifying and replying on the other PRs; as each returns, merge its work, then take
   that PR through its tests, pre-push review and push. A stack is never split this
   way: it fixes once, on its integration or top PR, below.
   Waits run once for the queue: push batch 1 for each PR in turn whose merge does not
   wait on another open PR (no stack base, no merge-after edge), then watch all of them with
   one `--in-flight` read of several numbers, then take each through step 6 in order.
   A PR on an edge still waits its turn, since its base changes when its predecessor
   merges.
   A stack lands first and fixes once, on its integration PR or its top branch, per
   [Fixes inside a stack](stacked-prs.md#fixes-inside-a-stack).
   After a base PR merges, retarget each PR stacked on it; its step 6 re-checks
   against the stack's landing branch (the trunk, or the integration PR's branch),
   since its base and diff changed. Only a stack on per-PR fixes also gives each PR its
   own step 5, bottom-up; elsewhere a finding step 6 raises on a stack PR joins the
   integration or top PR's batch instead of a push to that PR.
7. **Step 7 once,** after the last PR.

Completion criterion: every named PR is merged after all its predecessors, queued, or
stopped with a blocker, and one report covers all of them, starting with the merge
plan as it ran.
