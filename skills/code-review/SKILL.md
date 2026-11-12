---
name: code-review
description: "Three-axis review of the diff since a fixed point: Correctness (bugs, failure modes, security), Standards (repo conventions) and Spec (ticket/PRD fidelity). Use when the user wants to review a branch, PR, WIP changes, or asks to \"review since X\"."
argument-hint: "since <ref>, or a PR or branch (omit for WIP changes)"
allowed-tools: "Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/code-review/scripts/review-scope.sh *) Bash(git diff *) Bash(git log *) Bash(git merge-base *) Bash(git status *)"
---

# Code Review

Three-axis review of the diff between `HEAD` and a fixed point the user supplies:

- **Correctness**: would this change break something? Bugs, failure modes (what a side effect does when it fails, repeats, or races), security, data, broken contracts, missing tests (for behaviour only, per the `tdd` skill's [What needs a test](../tdd/SKILL.md#what-needs-a-test-and-what-proves-the-rest) section).
- **Standards**: does the code conform to how this repo writes code?
- **Spec**: does the code faithfully implement the originating ticket / PRD / spec?

The axes run **separately** so they don't pollute each other's context, then this skill aggregates their findings. Prefer **parallel sub-agents** when the harness supports them; otherwise run the reviews **inline in sequence** in this session. Either path must finish every axis before aggregating: never leave a review handle running past session end.

## Process

### 1. Pin the fixed point

Whatever the user said is the fixed point: a commit SHA, branch name, tag, `main`, `HEAD~5`, etc. If they named none and asked for WIP or uncommitted changes, it is `HEAD`. Otherwise ask for it (a structured question ([harness-tools](../harness-tools/SKILL.md)), otherwise in chat; when invoked from `implement`, it's the ticket's base commit).

**WIP is in scope** when the user asked for WIP or uncommitted changes, or asked to review "my changes" (or similar words for their own work) while `git status --porcelain` prints anything. A range a caller names (`implement`'s base commit, a re-review's head) is committed work only, so WIP stays out of it.

Pin it once, from inside the repo: `bash <this-skill-dir>/scripts/review-scope.sh <fixed-point>`, with `--wip` after the fixed point when WIP is in scope. When the caller passes a **path scope** (as `implement` does, so parallel sessions sharing one branch don't pollute the range), append ` -- <paths>`: the script adds it to both commands. It prints one JSON object: `diff_cmd` (`git diff <fixed-point>...HEAD`: three-dot, so the comparison is against the merge-base) and `commits` (from `log_cmd`) are the diff command and commit list every brief carries, `files` the changed paths, and `size` what step 4 reads.

With `--wip`, `diff_cmd` is `git diff <merge-base>`: the working tree against the merge-base, so it also prints staged and unstaged changes. It prints no untracked file. `untracked` lists those, and every brief carries that list beside the diff command, each file to be read whole as new code.

Exit 1 is a fixed point that does not resolve, or an empty diff (`"empty": true`): stop here, not inside three parallel reviews.

### 2. Identify the spec source

Look for the originating spec, in this order:

1. Ticket references in the commit messages or branch name: read the matching markdown file under `.scratch/` (or wherever `.agents/issue-tracker.md`, written by `/setup`, says this repo keeps them).
2. A path the user passed as an argument.
3. A PRD/spec file under `docs/`, `specs/`, or `.scratch/` matching the branch name or feature.
4. If nothing is found, ask the user where the spec is (a structured question, as in step 1, with **There is no spec** as one option). If they say there isn't one, the **Spec** axis skips and reports "no spec available".

### 3. Identify the standards sources

Anything in the repo that documents how code should be written, in priority order:

1. **`AGENTS.md`** at the repo root (and any standards docs under `docs/` it points at).
2. **`CONTRIBUTING.md`**, **`CODING_STANDARDS.md`**, or other project standards under `docs/`.
3. **Harness-specific or colocated rule files**: root and directory-scoped `CLAUDE.md`, `.cursor/rules`, or equivalents in directories the diff touches. Colocated rules are binding for their tree and override generic guidance for that path.
4. When both `AGENTS.md` and a harness-specific root file exist, prefer `AGENTS.md` for cross-harness conventions; apply harness-specific files as additional constraints for that environment.

**Skip anything tooling already enforces.** Formatters, type checkers, and mechanical upgrade tools own their domains; a finding those tools would catch or fix is noise, not a review finding. In a Laravel repo that typically means Pint, Larastan, and Rector.

On top of whatever the repo documents, the Standards axis always carries the **smell baseline** in [`references/smell-baseline.md`](references/smell-baseline.md): twelve Fowler code smells that apply even when a repo documents nothing. A documented repo standard overrides it, and each smell is a judgement call, never a hard violation.

### 4. Run the axes: sub-agents or inline

**If the harness can spawn parallel sub-agents** (dispatch and wait per [harness-tools](../harness-tools/SKILL.md)): launch three foreground sub-agents in parallel, wait for all results before writing anything. Do not background them, a background handle can die with the session. Where the harness loads this plugin's agents, use the typed agents `leek-skills:pr-reviewer`, `leek-skills:standards-reviewer` and `leek-skills:spec-reviewer` (read-only tools enforced, the Standards one remembers this repo's recurring violations, in files under this repo's `.claude/agent-memory/` that the next commit includes); elsewhere, any general sub-agent with the briefs below, the Correctness one on your strongest model.

**If sub-agents are unavailable:** run the reviews inline in this session, Correctness first, then Standards, then Spec (or skip Spec when no source was found). Same briefs, same output shape, only the execution host changes.

**Small diffs run inline too.** When step 1's `size` is `inline` (at most 3 files and 150 changed lines), three fresh contexts each re-reading it cost more than they find: take the inline path above.

**Large diffs split Correctness.** When `size` is `split` (more than 25 files), one Correctness reviewer runs out of turns before it reports. Dispatch two, each given half of `files` (a file and its tests stay together) and the full commit list, and present both reports under the one `## Correctness` heading.

**A caller may name the axes.** Run only those, and report the rest as `not run`.

**A re-review narrows.** When the caller passes the previous round's findings and its head, review only `<previous head>..HEAD` (the fix commits) and run only the axes that had actionable findings, plus Correctness when a fix added a mechanism (job, lock, claim, retry). Report the axes that did not run as `not re-run`.

**Correctness brief**: hand over the brief in [`triage-github-pr/references/independent-review.md`](../triage-github-pr/references/independent-review.md) in full, failure-mode probes included, with the diff command and commit list as its range, the commit messages as intent, and the repo's `AGENTS.md` / `CLAUDE.md`. Do not pass any PR review comments: this axis is the view they did not shape. Its output is the brief's `Self N: [BLOCKING | MAJOR | MINOR]` lines, each with a concrete failing case.

**Standards brief**: include:

- The full diff command and commit list.
- The list of standards-source files you found in step 3, **plus the absolute path of [`references/smell-baseline.md`](references/smell-baseline.md)** (this skill's directory), to read before reviewing: a sub-agent has no other access to it. Inline, read it yourself.
- The brief: "Report (per file/hunk where relevant) (a) every place the diff violates a documented standard: cite the standard (file + the rule); and (b) any baseline smell you spot: name it and quote the hunk. Distinguish hard violations from judgement calls, documented-standard breaches can be hard, but baseline smells are always judgement calls, and a documented repo standard overrides the baseline. Skip anything formatters, type checkers, or mechanical upgrade tools enforce. Under 1000 words."

**Spec brief**: include:

- The diff command and commit list.
- The path or fetched contents of the spec.
- The brief: "Report: (a) requirements the spec asked for that are missing or partial; (b) behaviour in the diff that wasn't asked for (scope creep); (c) requirements that look implemented but where the implementation looks wrong. Quote the spec line for each finding. Under 1000 words."

If the spec is missing, skip the Spec axis and note this in the final report.

### 5. Aggregate

Present the reports under `## Correctness`, `## Standards` and `## Spec` headings, verbatim or lightly cleaned. Do **not** merge or rerank findings; the axes are deliberately separate (see _Why three axes_).

Invoked standalone, report the findings through the host's findings list where it offers one (in Claude Code, one `ReportFindings` call holding all three axes, `category` set to the axis, axes in the order above and most severe first _within_ each axis; a judgement-call smell is `PLAUSIBLE`), and then print only the summary line below; otherwise print the three headed sections. Invoked by another skill, always print the sections.

End with a one-line summary: total findings per axis, and the worst issue _within each axis_ (if any). Don't pick a single winner across axes, that's the reranking the separation exists to prevent. Mark each axis in that line: ✅ no findings, ⚠️ findings. No marks in the findings themselves.

## Why three axes

A change can pass any axis and fail another:

- Code that follows every standard but implements the wrong thing → **Standards pass, Spec fail.**
- Code that does exactly what the issue asked but breaks the project's conventions → **Spec pass, Standards fail.**
- Code that is conventional and faithful to the spec but loses work when a queue push fails, or races a concurrent request → **Standards and Spec pass, Correctness fail.** This is the axis PR review bots spend most of their rounds on; asking it here, before the PR, is what keeps those rounds short.

Reporting them separately stops one axis from masking another.

## When you're done

Invoked from `implement`, hand the findings back to its loop; it decides what's real and fixes before committing; print no block. Invoked standalone, print the end-of-session block using the frame in [`wayfinder/references/pipeline-end-block.md`](../wayfinder/references/pipeline-end-block.md):

```text
---
Pipeline: decide → spec → tickets → **build**   (review runs inside build)
Done: <n Correctness, m Standards, k Spec findings; the worst per axis>
Next:
  • <condition> → /<skill> <ref>
```

Stage-specific **Next** conditions (only those that apply):

- **Real findings to fix** → fix them, or `/implement <ticket>` if they belong to an open ticket
- **Spec axis skipped (no spec)** → `/to-spec` if this work deserved one
- **Clean on every axis** → nothing to run; say so
