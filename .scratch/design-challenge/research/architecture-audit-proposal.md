# Pasted source: adversarial architecture audit proposal

Saved verbatim from the grill-me session of 2026-11-22. It was pasted, not linked, so this file is its only copy.

---

What you're describing is one of the biggest weaknesses of AI coding agents: **they often produce code that works, but never seriously question whether they should have built it that way.**

And when you challenge a decision, they readily agree and rewrite it. That doesn't necessarily mean the original was wrong, but it suggests the agent didn't adequately evaluate alternatives.

I think the best solution is an **adversarial architecture audit**, not a traditional code review.

## **What I'd build**

A reusable Claude Code skill that audits an existing codebase with the explicit goal of finding *missed opportunities for better engineering*.

It should examine six areas:

| Area                    | What the auditor investigates                                                                       |
| ----------------------- | --------------------------------------------------------------------------------------------------- |
| **Architecture**        | Wrong abstractions, misplaced responsibilities, unnecessary layers, poor separation of concerns     |
| **Data modeling**       | Incorrect relationships, redundant fields, JSON where relational tables belong, missing constraints |
| **Shortcuts**           | Hardcoded values, workarounds, duplicated logic, temporary solutions that became permanent          |
| **Complexity**          | Reinvented framework functionality, overengineering, unnecessary indirection                        |
| **Maintainability**     | Fragile coupling, difficult-to-change structures, inconsistent patterns                             |
| **Missed alternatives** | Better Laravel/PHP/native approaches the original agent never considered                            |

## **The important part: force it to compare alternatives**

A normal code review asks:

> Is there anything wrong with this implementation?

Your audit should ask:

> If a senior engineer were implementing this feature from scratch today, knowing everything we now know, would they choose this architecture?

For every significant design decision, require the auditor to:

1. **Reconstruct the intent.** What problem is this code solving?
2. **Identify the chosen approach.** What architectural decisions were made?
3. **Generate alternatives.** Find at least two plausible approaches, including the existing one.
4. **Challenge the decision.** Compare correctness, simplicity, performance, extensibility, and Laravel conventions.
5. **Determine whether the choice was justified.** Don't assume a different approach is better.
6. **Quantify the impact.** Is it worth changing, or is it merely a preference?

This last distinction is critical. Otherwise, you'll create an agent that enthusiastically recommends rewriting everything.

## **I'd actually use three independent passes**

**Pass 1: Architectural discovery**

Map the application's modules, data structures, dependencies, conventions, and major design decisions. Identify suspicious choices without proposing changes yet.

**Pass 2: Adversarial review**

A separate agent challenges those decisions, searches for superior alternatives, and looks for shortcuts that aren't immediately obvious from reading individual files.

**Pass 3: Independent adjudication**

A third agent evaluates the criticisms, verifies evidence, and rejects speculative improvements or changes that merely trade one problem for another.

## **Example of the output I'd want**

**Finding #014: Misused JSON column**

High impact

app/Models/Workflow.php · database/migrations/...

**Current implementation**

Workflow steps and their relationships are stored in one JSON column.

**Why this may be problematic**

The application frequently needs to query, update, and reference individual steps. This creates unnecessary application-level logic and makes relational integrity harder to enforce.

**Better alternative**

Normalize workflow steps into a dedicated table with foreign keys and explicit ordering.

**Tradeoff**

More tables and joins, but simpler individual-step updates and stronger database constraints.

Confidence: High

Estimated refactor: Medium

*Illustrative finding, not an assessment of your actual code.*

## **One addition that would make this substantially better**

**Run a counterfactual implementation review.**

Instead of showing the auditor the existing implementation first, give an independent agent only the feature requirements, relevant constraints, and existing project conventions.

Ask it to design the solution independently.

Then compare its proposed architecture against what the coding agent actually built.

This reduces anchoring on the existing implementation and can uncover missed design opportunities that conventional reviews overlook.

It isn't a guarantee of better architecture, but it's a useful additional signal.

## **My recommendation**

Build this as a Claude Code skill called `/architecture-audit`, with:

- Read-only operation by default.
- Independent agents where supported.
- Repository-wide and feature-scoped modes.
- Laravel-specific architectural knowledge.
- Evidence-based findings with exact file references.
- Ranked recommendations based on impact, confidence, and refactoring cost.
- A persistent findings report so you can measure whether architectural debt improves over time.

**One important question:** Do you want this primarily to audit an *entire existing codebase*, or to run *after every AI coding task* and challenge what the agent just built?

I'd design it differently depending on that answer, although the strongest solution would ultimately support both.
