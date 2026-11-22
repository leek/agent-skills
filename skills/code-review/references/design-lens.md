# Design lens

The one home for the Design checks: `code-review`'s **Design** axis and `to-spec`'s **blind design**. Both ask the same question: *if a senior engineer built this from scratch today, knowing what we now know, would they choose this design?* Agents rarely ask it on their own: they build something that works, and when a person challenges it, they agree and rewrite it whether or not the first version was wrong. The fix is to design without seeing the answer first, then compare.
## The six areas

| Area | What to look for |
| --- | --- |
| Architecture | Wrong abstractions, misplaced responsibilities, unnecessary layers, poor separation of concerns |
| Data modeling | Wrong relationships, redundant fields, JSON where a relational table belongs, missing constraints |
| Shortcuts | Hardcoded values, workarounds, duplicated logic, a temporary solution that became permanent |
| Complexity | Framework features rebuilt by hand, overengineering, indirection with no second caller |
| Maintainability | Fragile coupling, structures that are hard to change, a pattern used differently from the rest of the repo |
| Missed alternatives | A framework, language, or package feature the code could have used and did not |

Framework knowledge comes from the repo: its conventions, its `AGENTS.md` / `CLAUDE.md`, the stack reference the caller names (for Laravel, `implement/references/laravel.md`), and the code already there. A feature you suggest exists in the installed version: check the lock file or vendor source before naming it.

## The six steps

For each significant design decision (a new table or column shape, a new class or layer, where a responsibility lives, a dependency, a pattern the rest of the code will copy):

1. **Reconstruct the intent.** What problem does this solve? Take it from the spec, the ticket, or the commit messages.
2. **Name the chosen approach.**
3. **Generate alternatives.** At least two plausible approaches, the chosen one included.
4. **Challenge it.** Compare correctness, simplicity, performance, extensibility, and fit with the framework and this repo's conventions.
5. **Decide whether the choice was justified.** A different approach is not better by default. Most choices hold; say so and move on.
6. **Weigh the impact.** `worth changing` (the alternative removes a real cost: a bug class, a query the schema cannot serve, logic duplicated across callers, a constraint the database could enforce) or `preference` (taste, or a trade with no clear winner). Drop every `preference` before reporting.

Never report a decision that an ADR, the spec's Implementation Decisions (including its `Rejected:` lines), or a decision record already settled with a reason, unless you can name a cost that reason did not weigh.

## Design review brief (the `code-review` axis)

The reviewer works in this order, and the order is the point:

1. Read the spec or ticket (or, with none, the commit messages) and the files around the change, **not the diff**. Sketch in a few lines how you would build it: the data shape, where each responsibility lives, what framework features you would use.
2. Read the diff. List the significant design decisions it makes.
3. Where your sketch and the diff differ, run the six steps on that decision. Also run them on any decision in the six areas that your sketch did not cover.

Report each surviving finding in this shape, at most 5, most impact first, under 800 words in total:

```text
Design N: <title> · <file:line>[, <file:line>]
  Current: <what the code does>
  Alternative: <the better approach>
  Why: <the concrete cost the current choice carries>
  Trade-off: <what the alternative costs>
  Impact: high | medium | low · Confidence: high | medium | low · Refactor: small | medium | large
```

End with one line naming the decisions you checked and found justified, so the caller sees the axis ran. No findings is a normal result.

## Blind design brief (`to-spec`)

The designer gets the Problem Statement, the User Stories, the constraints (data handling, launch gating, deploy safety, architecture rules), the ADRs and `GLOSSARY.md` in the area, and pointers to the closest existing implementation. It gets **no** conversation, grill record, or draft Implementation Decisions: those are the anchor it exists to avoid.

It returns, under 600 words: the data model (tables, columns, relationships, constraints), where each responsibility lives (classes, jobs, events, and which existing modules it extends), the framework features it would use, and for each choice one line on the alternative it rejected and why. Each choice names the six-area concern it answers when one applies.

The spec writer then compares that design with the draft, decision by decision.

## Deciding a Design finding

A Design finding is never fixed without the user's answer. Ask each one as a structured question ([harness-tools](../../harness-tools/SKILL.md); otherwise in chat), with the finding's Current, Alternative, Trade-off, and Refactor size in the framing, and these options:

- **Fix now**: it joins the run's fix batch like any other finding.
- **Follow-up ticket**: write it to the tracker as a ticket (or, with no tracker, a `Left open:` line in the PR).
- **Keep as is**: record the reason in the report. When the reason would stop a future review from raising it again, offer an ADR through `domain-modeling`.

Recommend the option the finding's Impact and Refactor size support: a high-impact, small or medium refactor is usually **Fix now**; a large refactor is usually **Follow-up ticket**. The fixer does not rebut or rewrite a Design finding on its own; the user's answer decides it. When nobody can answer (an unattended run), every Design finding goes in the PR as a `Left open:` line.
