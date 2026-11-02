# Delivery shape

Read before step 1 on every `implement` run; `implement-spec` reads its whole-spec questions. The branches and PRs each answer leads to are in [`spec-run.md`](spec-run.md).

Before anything is claimed or branched, settle how and where to build. Ask each question below that applies, in one structured-question call ([harness-tools](../../harness-tools/SKILL.md); single-select, the recommended option first; otherwise one message in chat), and nothing else. Skip a question when the request already answers it ("open a PR", "stack it", "just commit", "in a worktree", `all`), or when the repo's rules or the user's saved preferences settle it, and follow that answer. When every question is settled, ask nothing.

**Scope** comes first, in a call of its own, because its answer picks the delivery options. Ask it when the input is a spec whose `tickets/` are published and the request names neither a ticket nor the whole spec:

- **Next frontier ticket** (recommended when one ticket is ready): build the lowest-numbered open, unblocked ticket as the work item.
- **Every ticket, here**: a spec run, one ticket after another in this session.
- **Every ticket, in parallel**: stop, and tell the user to run `/implement-spec <spec path>`.

Then the rest, together:

- **Delivery**, for one work item:
  - **Current branch** (recommended on a feature branch): commit here, no PR.
  - **New branch and PR** (recommended on the default branch): [PR delivery](spec-run.md#pr-delivery-before-step-1-claims-anything).
  - **Worktree and PR**: PR delivery in `.claude/worktrees/<branch>`.
- **Delivery**, for a whole spec (more than one ticket; with one ticket, ask the one-item question):
  - **One PR** (recommended): every ticket on one branch.
  - **Stacked PRs**: one PR per ticket, each based on the one below, over an integration branch that reaches `<default>` in one merge, so each review holds one ticket. Before offering it, run `gh repo view --json mergeCommitAllowed`: a stack must land with merge commits (`triage-github-pr`'s stacked-PR rules; see [Stacked PRs](spec-run.md#stacked-prs)), so when it reads `false`, say so in the option.
  - **Branch, no PR**: deliver as **One PR**, but push the branch and stop before `gh pr create`.
- **Worktree**, for a whole spec: build the branch in a worktree at `.claude/worktrees/<slug>` (recommended: this checkout stays as it is), or switch this checkout to it. Skip it when the tree is dirty (the worktree is the only option; say so).
- **Local `<default>`**, when the spec's `.scratch/<slug>` will come from local `<default>` and that is all `<default>` holds ahead of `origin/<default>` (`git log --format=%h origin/<default>..<default> -- . ':!.scratch/<slug>'` prints nothing, and `git rev-list --count origin/<default>..<default>` is not `0`): move `<default>` back to `origin/<default>` once the new branch carries the spec (recommended), or leave it. This is the question [PR delivery](spec-run.md#pr-delivery-before-step-1-claims-anything)'s step 3 would otherwise ask mid-run.

Every shape runs the same build, review, and verification. Only the branches and PRs differ.
