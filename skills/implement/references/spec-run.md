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
3. When the work comes from `.scratch/<slug>/` and the new branch lacks it or holds an older copy (committed on local `<default>`, not pushed), bring it over: `git checkout <default> -- .scratch/<slug>`, then commit it as `docs(scratch): <slug>`.
4. Record `base_sha` on the new branch. Claims, resolutions, and code all commit to this branch.

## Spec run

Run it on a spec whose `tickets/` already exist and the user asked to build all of ("`all`", "implement all of …", "the whole spec"). A spec with no tickets yet goes to `to-tickets` first.

1. **Order.** Read every ticket's frontmatter once. Take the open tickets in number order (numbers are topological, so blockers come first). A ticket claimed by someone else stays out; name it in the report.
2. **Build each ticket inline, one after another.** Per ticket: claim it (step 1), choose its seams (step 2), run the TDD loop with its focused tests (step 3), and commit it (step 4). Each ticket's commits stand alone, so the PR history reads ticket by ticket. Carry seams a later ticket needs forward in your notes; its `Resolution` is written in step 8.
3. **Stop at a deploy gate.** After a ticket with `deploy-gate: true` is built, run steps 5–8 for the tickets built so far, open the PR, and stop: its dependents start after that PR is deployed.
4. **Run steps 5–7 once, over the whole range.** Review `base_sha..HEAD` scoped to every path the run touched. Ask the full-suite question once. Verify each ticket's acceptance criteria in one `verify` pass. A follow-up fix reruns the focused tests for what it touched, never the full suite again.
5. **Close in step 8.** Write each ticket's `Resolution` and `status: closed`. The spec is complete when every ticket is closed.

## PR delivery: after step 8

1. Push the branch and open the PR with `gh pr create`. Write the body with the `pr` skill's template, its Evidence from the verification pass with the screenshots uploaded as its **Screenshots** section says, then one line per ticket closed. For **Stacked PRs**, open the stack below instead.
2. Read the PR's unresolved review threads once (the GraphQL `reviewThreads` query in `resolve-review-comments`). When any exist, run `resolve-review-comments` on the PR. When review bots are still running, say so in the end block.
3. Keep the worktree: it holds the PR branch. If you entered it, leave with `ExitWorktree({action: "keep"})`, which never removes it. Name its path in the report; `repository-cleanup` removes it after the merge.
4. Without a worktree, return the main checkout to the default branch: `git switch <default> && git pull --ff-only`. Say so in the report, so the next request starts on fresh `<default>`.

## Stacked PRs

The build is unchanged: one branch `<slug>` whose commits read ticket by ticket. Cut the stack from it after step 8:

1. **One cut per ticket.** In a spec run, the cut is the ticket's last commit. In `implement-spec`, it is the ticket's `--no-ff` merge commit on `<slug>` (`git log --first-parent --merges <base_sha>..<slug>`), in merge order. Create `git branch <slug>-stack-<NN> <cut>` for every ticket but the last. The last ticket's PR uses `<slug>` itself, so the review fixes and the tracker commit ride in the top PR.
2. **Push and open bottom-up.** Push all the branches in one `git push origin <branches…>`. Open the bottom PR against `<default>`, and each next PR against the head branch of the PR below it. Each body uses the `pr` skill's template for its own ticket: Evidence from that ticket's acceptance checks in the one verification pass, then its closed-ticket line. Before Merge Danger, add `Stack: <k> of <n>, based on #<below>. Land bottom-up with merge commits.` The top PR's body also names the review-fix commits it carries.
3. **Report the stack** bottom-up as `#101 → #102 → #103`. To land it, the next step is `triage-github-pr` on all its PRs, which merges a stack bottom-up and retargets each PR above.

A deploy gate ends the stack at the gate ticket, the same as it ends a single PR.

## Follow-up on a delivered PR

A later request that changes the same work ("also fix…", "tweak…") checks the PR first: `gh pr view <branch> --json state -q .state`.

- `OPEN`: commit to the PR branch, in its worktree when it has one, and push. In a stack, commit to the PR that owns the change, then merge its branch into each branch above it, bottom-up, with plain merges and plain pushes (never a rebase or a force push).
- `MERGED` or `CLOSED`: the branch is finished. Start from fresh `origin/<default>`: a new branch and PR by default, or straight onto `<default>` when the user says main.
