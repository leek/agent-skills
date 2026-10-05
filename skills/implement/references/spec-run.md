# Spec run and PR delivery

Two additions to the `implement` process. A **spec run** builds every ticket of one spec in this session. **PR delivery** puts the work on its own branch, in a worktree when asked, and ends with a pull request. A spec run always uses PR delivery; a single work item uses it when the user asks for a branch, a worktree, or a PR.

## PR delivery: before step 1 claims anything

1. Name the branch after the work: the spec's `<slug>`, or the ticket's.
2. Create it from the fresh default branch (`git fetch origin` first):
   - The user asked for a worktree, or the tree is dirty: `git worktree add -b <branch> .claude/worktrees/<branch> origin/<default>`, at that path, never a sibling directory. Make it runnable with `laravel-herd-worktrees`' **Bootstrap a bare worktree** section, then work there.
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

1. Push the branch and open the PR with `gh pr create`. Write the body with the `pr` skill's template, its Evidence from the verification pass, then one line per ticket closed.
2. Read the PR's unresolved review threads once (the GraphQL `reviewThreads` query in `resolve-review-comments`). When any exist, run `resolve-review-comments` on the PR. When review bots are still running, say so in the end block.
3. Keep the worktree: it holds the PR branch. Name its path in the report; `repository-cleanup` removes it after the merge.
4. Without a worktree, return the main checkout to the default branch: `git switch <default> && git pull --ff-only`. Say so in the report, so the next request starts on fresh `<default>`.

## Follow-up on a delivered PR

A later request that changes the same work ("also fix…", "tweak…") checks the PR first: `gh pr view <branch> --json state -q .state`.

- `OPEN`: commit to the PR branch, in its worktree when it has one, and push.
- `MERGED` or `CLOSED`: the branch is finished. Start from fresh `origin/<default>`: a new branch and PR by default, or straight onto `<default>` when the user says main.
