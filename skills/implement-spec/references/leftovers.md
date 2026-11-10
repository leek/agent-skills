# What is left after cleanup

Read this in [`implement-spec`](../SKILL.md) step 8 when something this run created is left after the merged tickets' cleanup: a refused environment, the environment of an unmerged or released ticket, or the verify setup (the Herd workspace, database or worktree `verify` made for the run, when it made any).

What is left follows step 1's cleanup answer. When it was to remove them, remove each by step 8's ordered cleanup: a worktree that holds uncommitted work beyond agent notes is listed instead, and a branch `git branch -d` refuses stays and is named in the report. Otherwise ask once about them per **What is left** in [Remove a served worktree](../../laravel-herd-worktrees/SKILL.md#remove-a-served-worktree), one option per ticket's retained environment. Keeping a worktree keeps its associated resources.
