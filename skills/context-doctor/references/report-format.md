# Report format

The report is a Markdown file at `<scratch>/context-doctor/report.md` (`<scratch>` is the session scratchpad, otherwise `$TMPDIR`). Chat gets the executive summary, the top five changes, and the path. Write it for a reader deciding what to approve: lead each section with the number, then the specifics. Quote at most one line of any memory or instruction, redacted.

## 1. Executive summary

Overall health in one sentence, then one line each: sources found (active, lazy, on-demand, never, uncertain); stored and always-loaded tokens (estimates); counts of obsolete, redundant, conflicting, and missing-context findings; the three changes worth the most.

## 2. Inventory

One row per source with findings, plus one summary row per group with none (`37 plugin skills, no findings`):

| Source | Scope | Loads | ~Tokens | Findings |
|---|---|---|---|---|

Add the inventory's issues (broken imports, links that do not import, memory index problems), and any mismatch between the inventory and what your own context shows loaded.

## 3. Recommended changes

Grouped, in this order: obsolete or inaccurate · low-value or one-off · redundant · wrongly scoped · verbose · conflicting · missing high-value context · configuration (plugins, skills, MCP, hooks). Number every finding across the whole report (`F1`, `F2`, …) so the user can approve by number. Each finding:

```
F7 · UPDATE · High confidence · low risk · saves ~40 tokens/session
<file:line>  "<excerpt, one line>"
Change: <exact replacement text, "delete", or the destination and moved text>
Why: <one sentence>
Evidence: <file:line, command output, or usage count that proves it>
```

User-scope findings carry `⟂ global: affects every project` after the class. A finding on a generated file names its source line and the regenerate command; one on an upstream copy carries `↑ upstream: <checkout>` and goes last in its group, as an edit to make there. A GENERALIZE finding lists the notes it replaces and gives the one rule that stays. Conflicts name the winning rule and why (the more specific scope wins in Claude Code; a newer verified convention beats an older one).

## 4. Proposed optimized context

For a file with many approved-in-principle changes, its full proposed text. Otherwise, only the targeted edits from section 3. Preserve structure and order.

## 5. Before and after

| Metric | Before | After (proposed) |
|---|---|---|
| Instruction files | | |
| Memory files | | |
| Stored context, editable sources (~tokens) | | |
| Always-loaded (~tokens) | | |
| Per-turn listing (~tokens) | | |
| Lazy and on-demand (~tokens) | | |
| Duplicate units | | |
| Obsolete statements | | |
| Conflicts | | |
| Unverified statements | | |

Say that token figures are bytes/4 estimates. Point at `/context all` for measured numbers.

## 6. Action plan

The approved-in-principle changes ranked by correctness and safety impact, then risk of misleading future agents, then recurring token savings, then maintenance burden, then confidence.

## 7. Final evaluation

Answer in one or two lines each: what to delete now; what misleads by describing an obsolete state; what exists only because of a one-off; what is duplicated or verbose; what loads more often than it is needed; which decisions and constraints must be preserved; what missing context would materially help; the expected efficiency gain.
