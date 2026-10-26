# Spec run and PR delivery

Two additions to the `implement` process. A **spec run** builds every ticket of one spec in this session. **PR delivery** puts the work on its own branch, in a worktree when asked, and ends with a pull request. A spec run always uses PR delivery; a single work item uses it when the delivery question below picks it. `implement-spec` reads the same delivery question and stacked-PR rules.

## Choose the delivery shape

Ask once, before anything is claimed or branched (`AskUserQuestion` where available, one single-select question, the recommended option first; otherwise a plain question in chat). Skip it when the request already names the shape ("open a PR", "stack it", "just commit"), or when the repo's rules or the user's saved preferences settle it, and follow that answer.

- **One work item:**
  - **Current branch** (recommended on a feature branch): commit here, no PR.
  - **New branch and PR** (recommended on the default branch): PR delivery below.
  - **Worktree and PR**: PR delivery in `.claude/worktrees/<branch>`.
- **A whole spec** (more than one ticket; with one ticket, ask the one-item question):
  - **One PR** (recommended): every ticket on one branch.
  - **Stacked PRs**: one PR per ticket, each based on the one below, so each review holds one ticket. Before offering it, run `gh repo view --json mergeCommitAllowed`: a stack must land with merge commits (`triage-github-pr`'s stacked-PR rules), so when it reads `false`, say so in the option.
  - **Branch, no PR**: deliver as **One PR**, but push the branch and stop before `gh pr create`.

Every shape runs the same build, review, and verification. Only the branches and PRs differ.

## PR delivery: before step 1 claims anything

1. Name the branch after the work: the spec's `<slug>`, or the ticket's.
2. Create it from the fresh default branch (`git fetch origin` first):
   - The user asked for a worktree, or the tree is dirty: `git worktree add -b <branch> .claude/worktrees/<branch> origin/<default>`, at that path, never a sibling directory. Make it runnable (install dependencies, copy local env config) the way the project's docs say, or as the stack reference says, then work there: move the session into it with `EnterWorktree({path: ".claude/worktrees/<branch>"})` where available, otherwise run every command with absolute paths into the worktree.
   - Otherwise: `git switch -c <branch> origin/<default>`.
3. When the work comes from `.scratch/<slug>/` and the new branch lacks it or holds an older copy, bring it over from where `to-spec` committed it: the branch `docs/<slug>-spec` when it exists (`git rev-parse --verify -q docs/<slug>-spec`), otherwise local `<default>` (committed, not pushed). Run `git checkout <that ref> -- .scratch/<slug>`, then commit it as `docs(scratch): <slug>`.
4. Record `base_sha` on the new branch. Claims, resolutions, and code all commit to this branch.

## Spec run

Run it on a spec whose `tickets/` already exist and the user asked to build all of ("`all`", "implement all of …", "the whole spec"). A spec with no tickets yet goes to `to-tickets` first.

1. **Order.** Read every ticket's frontmatter once. Take the open tickets in number order (numbers are topological, so blockers come first). A ticket claimed by someone else stays out; name it in the report. The delivery ticket (`delivery: true`) is not built in step 2; it runs in step 4.
2. **Build each ticket inline, one after another.** Per ticket: claim it (step 1), choose its seams (step 2), run the TDD loop with its focused tests (step 3), and commit it (step 4). With **Stacked PRs**, review the ticket, then push and open its PR, per [Stacked PRs](#stacked-prs). Each ticket's commits stand alone, so the PR history reads ticket by ticket. Carry seams a later ticket needs forward in your notes; its `Resolution` is written in step 8.
3. **Stop at a deploy gate.** After a ticket with `deploy-gate: true` is built, run steps 5–8 for the tickets built so far, open the PR, and stop: its dependents start after that PR is deployed.
4. **Run steps 5–7 once, over the whole range.** Review `base_sha..HEAD` scoped to every path the run touched. Ask the full-suite question once. Verify each ticket's acceptance criteria in one `verify` pass. A follow-up fix reruns the focused tests for what it touched, never the full suite again. Then run the delivery ticket's pass 1 ([`DELIVERY-TICKET.md`](../../to-tickets/DELIVERY-TICKET.md)), with no build of its own: the full suite and verify pass above count toward its Before merge list, and a coverage gap is fixed in the run.
5. **Close in step 8.** Write each ticket's `Resolution` and `status: closed`; the delivery ticket closes, or goes to `ready-for-human` with its after-deploy steps in the PR body. The spec is complete when every ticket is closed.

**Ticket board.** Report each ticket's status per [`ticket-board.md`](../../wayfinder/references/ticket-board.md), with `kind: "spec"`: `ready` and `blocked` (note: the blockers) at step 1, `skipped` for tickets left out, `running` at its claim, `built` at its commit (note: the SHA), `released` (note: why), and `closed` in step 8. From the review step on, also send the `stage` at each change and each finding's status.

## PR delivery: after step 8

1. Push the branch and open the PR with `gh pr create`. Write the body with the `pr` skill's template, its Evidence from the verification pass with the screenshots uploaded as its **Screenshots** section says, then one line per ticket closed. For **Stacked PRs**, the ticket PRs are already open: open the closing PR per the stack's step 4 below instead.
2. Read the PR's unresolved review threads once (the GraphQL `reviewThreads` query in `resolve-review-comments`). When any exist, run `resolve-review-comments` on the PR. When review bots are still running, say so in the end block.
3. Keep the worktree: it holds the PR branch. If you entered it, leave with `ExitWorktree({action: "keep"})`, which never removes it. Name its path in the report; `repository-cleanup` removes it after the merge.
4. Without a worktree, return the main checkout to the default branch: `git switch <default> && git pull --ff-only`. Say so in the report, so the next request starts on fresh `<default>`.

## Stacked PRs

The build is unchanged: one branch `<slug>` whose commits read ticket by ticket. Parallel frontier tickets in `implement-spec` still build in parallel; their `--no-ff` merge order on `<slug>` is the stack order, so never ask the user how to linearize parallel tickets for a stack. Each ticket's PR opens as soon as that ticket is **final**, never in a batch at the end, and never before. Final means its code, its review, and its review fixes are all committed. An open PR's branch never gets another commit from the run, so a PR merged early never misses work that lands later:

1. **Review the ticket first.** Run `code-review` on the ticket's own commits, scoped to its paths, and fix the findings the way step 5 does, with the same two-round budget. In a spec run, do this right after step 4. In `implement-spec`, do it on the ticket's branch `<slug>--<NN>` against the integration tip it last merged, before step 4's merge. The ticket's implementer fixes the findings in its worktree. A finding the second round leaves open goes in the ticket's PR body.
2. **Cut and push.** In a spec run, the cut is the ticket's last commit, its review fixes included. In `implement-spec`, it is the ticket's `--no-ff` merge commit on `<slug>`, once the merge passes its focused tests. Run `git branch <slug>-stack-<NN> <cut>`, then `git push -u origin <slug>-stack-<NN>`. The ticket landing `k`th is position `k` (the bottom is 1).
3. **Open its PR.** Base it on `<default>` for position 1, otherwise on the head branch of position `k-1`. Title it `[<slug>#<k>] <ticket title>`, so the whole stack sorts and reads as one group. Write the body with the `pr` skill's template for this ticket. Its Evidence is the ticket's focused test command and result, and its review outcome. Before Merge Danger, add `Stack: <slug>#<k>, based on #<below>. Land bottom-up with merge commits.` Keep each PR number against its ticket: it goes in the progress line and the next PR's `based on`.
4. **Close the stack with one more PR.** The whole-branch review, the verification pass, and the tracker's resolutions come after every ticket's PR is open. Their commits go on `<slug>`, above the top cut, and never onto an open PR's branch. Push `<slug>` and open it as the last PR, `[<slug>#<n+1>] Review fixes and resolutions`, based on the top ticket's branch. Its body lists each fix with the ticket it touches, and the verification evidence per ticket. Then edit each ticket PR's body (`gh pr edit <n> --body-file <file>`, which adds no commit): add a line saying whether verification passed for it, a pointer to any fix in the closing PR, and the whole stack bottom-up (`#101 → #102 → #103`).
5. **Report the stack** bottom-up as `#101 → #102 → #103` with the exact merge order. Name each ticket PR that has a fix waiting in the closing PR. To land it, the next step is `triage-github-pr` on all its PRs, which merges a stack bottom-up and retargets each PR above.

A run that stops early leaves its open PRs as they are; the report names them.

A deploy gate ends the stack at the gate ticket, the same as it ends a single PR.

## Follow-up on a delivered PR

A later request that changes the same work ("also fix…", "tweak…") checks the PR first: `gh pr view <branch> --json state -q .state`.

- `OPEN`: commit to the PR branch, in its worktree when it has one, and push. In a stack, commit to the PR that owns the change, then merge its branch into each branch above it, bottom-up, with plain merges and plain pushes (never a rebase or a force push).
- `MERGED` or `CLOSED`: the branch is finished. Start from fresh `origin/<default>`: a new branch and PR by default, or straight onto `<default>` when the user says main. An open pull request whose base is that finished branch is retargeted first, onto the new branch or onto `<default>` when the new work goes there: `gh pr edit <n> --base <base>`. Merging it on the old base lands the work on that old branch. Landing a stack still follows `triage-github-pr`'s stacked-PR rules.
