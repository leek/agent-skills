# Submit and clean up

## Submit

1. **Review the diff** against `origin/<default>`. Check correctness, security, accidental behavior changes, duplication, needless complexity, generated artifacts, unrelated files, and scope creep. Exactly one issue must remain.
2. **Recheck the known work.** Run `known-work.sh` again, because another session may have opened an overlapping PR during the cycle. If a new PR now covers the issue, do not push. Keep the worktree for the end-of-run list, and return to step 2 of the skill for a new candidate in the same cycle. If the default branch moved, rebase and repeat any verification the rebase invalidates.
3. **Commit and push.** In the worktree, stage explicit paths only (`git add -- <path> …`), inspect the staged diff, commit, and `git push -u origin sweep/<topic>`. Never push to the default or a deploy branch, and never force-push shared work.
4. **Open the PR.** Write the body in the `pr` skill's format, for a reviewer who has not seen this conversation: the problem and impact, the evidence, the root cause, the change, why this fix, the verification, and any remaining risk. Leave out secrets, patient or customer data, and raw telemetry; redact them or link to them. Write the body to a file and run `gh pr create --base <default> --head sweep/<topic> --body-file <file>`.
5. **After an unclear failure** of a push or `gh pr create`, check the remote branch and `gh pr list --head sweep/<topic>` before you retry. Reuse a PR this cycle already opened. Never open a second one.
6. **Label it** after it exists, so a bad label cannot block creation. Match names from `gh label list --limit 200` exactly (case-insensitive), apply each with its own `gh pr edit <n> --add-label <name>`, and never create a label:

   | Change | Label |
   | --- | --- |
   | defect fix | `bug` |
   | refactor | `refactor`, plus `dry`, `architecture`, or `tech-debt` when one fits |
   | performance | `performance` |
   | security | `security` |
   | UI, UX, accessibility | `ux` |
   | tests or coverage only | `test` |
   | CI | `ci` |

   Never apply status or bot labels (`duplicate`, `invalid`, `wontfix`, `wip`, `dependencies`, review-bot triggers). Report the wanted labels that did not exist. A labeling failure does not fail the cycle.
7. **Confirm** that the remote branch holds the commit and that the PR has the right head, base, diff, and labels.
8. **Wait for checks.** In Claude Code, run `gh pr checks <n> --watch` with `run_in_background` and end the turn; its exit wakes you. Elsewhere, run it in the foreground. If it times out, report the checks as pending. Fix failures this change caused in the same worktree and PR. Report failures that already existed, or that come from outside, as such. Never present pending checks as passed. If the repo's PR checks skip the test suite, say that green means static analysis only.

## Clean up

Remove nothing until the run ends. Remove only what this run created and recorded. Never remove something another session might own, even when it looks stale.

1. **Prove each worktree is saved.** Both commands must print nothing. Compare against `origin/<default>` for a branch that was never pushed:
   ```bash
   git -C <worktree> status --porcelain
   git -C <worktree> log --oneline origin/sweep/<topic>..HEAD
   ```
   A worktree that fails this check is kept, and the report says why.
2. **Ask once.** List the worktrees and scratch databases that passed, and ask which to remove: one `AskUserQuestion` multi-select in Claude Code (`request_user_input` in Codex when it is offered), otherwise one yes/no in chat. With no answer, remove nothing.
3. **Remove what the user chose.** Use `git worktree remove <path>` and drop each chosen database (`DROP DATABASE IF EXISTS <name>`; for SQLite, delete the file). Then delete its line from `<git-common-dir>/scratch-databases`. Never drop the app's main or shared test database.
4. **Branches.** Keep every pushed branch. Delete only a local branch with no commits that was never pushed (`git branch -d sweep/<topic>`).
5. **Scratch files.** Delete PR-body files, logs, and screenshots the run wrote outside the scratchpad. Keep `.scratch/sweep/findings/`.

For anything left over (a kept worktree, a branch after its PR merges), recommend `/repository-cleanup` to the user.
