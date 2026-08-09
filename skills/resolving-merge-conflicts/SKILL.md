---
name: resolving-merge-conflicts
description: Resolve an in-progress git merge or rebase conflict while preserving both sides' intent. Use when a merge/rebase is blocked on conflicts, or the user asks to finish a conflicted merge or rebase.
---

# Resolving Merge Conflicts

1. **See the current state** of the merge/rebase. Check git history and the conflicting files.

2. **Find the primary sources** for each conflict. Understand deeply why each change was made, and what the original intent was. Read the commit messages, check the PRs, check original issues/tickets.

3. **Resolve each hunk.** Preserve both intents where possible. Where incompatible, pick the one matching the merge's stated goal and note the trade-off. Do **not** invent new behaviour. Always resolve; never `--abort` unless the user explicitly asks to abort.

4. Discover the project's **automated checks** and run them — typically static analysis (Larastan / typecheck), then tests (Pest), then format (Pint). Fix anything the merge broke.

5. **Finish the merge/rebase.** Stage everything and commit. If rebasing, continue the rebase process until all commits are rebased.
