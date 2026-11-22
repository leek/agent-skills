---
title: "How to-spec and the implementer challenge their own design"
type: grilling
status: closed
claimed-by:
blocked-by: []
---

## Question

How to add the pasted "adversarial architecture audit" idea ([research/architecture-audit-proposal.md](../research/architecture-audit-proposal.md)) to `to-spec` and to the implementer (`implement`, `implement-spec`), so a design is weighed against other designs before and after it is built.

## Settled

- `to-spec`: one subagent makes a blind design from the Problem Statement, User Stories, constraints, ADRs, GLOSSARY and repo conventions only, without the chat or the grill record. Each real difference from the draft's Implementation Decisions becomes a Needs decision item. Each major Implementation Decision also records the option it rejected and why.
- Build: a fifth `code-review` axis, **Design**. It runs in `implement` step 5 and once over the whole branch in `implement-spec` step 5, never per ticket. Its reviewer reads the spec, sketches its own design, and only then reads the diff (counterfactual first, then comparison).
- Design findings: the user decides each one. Nothing from this axis is fixed without the user's answer.

## Defaults applied

- No standalone `/architecture-audit` skill (context: the user asked to add this to the implementer and spec writer; `improve-codebase-architecture` and `code-smells-audit` already cover whole-repo audits). The repo-wide mode and the persistent debt report drop with it.
- The per-task mode is the one built: it answers the paste's closing question (context).
- In `implement-spec`, a Design finding is asked in parallel and the other fixes go on, per step 5's existing "a finding that needs the user's decision never holds the round" rule (context).
- In `autopilot`, nobody can answer, so Design findings go to the PR as `Left open:` lines and are never fixed automatically (follows from the settled answer).
- Each Design finding the user sees carries the paste's fields: current choice, the alternative, why, trade-off, impact, confidence, refactor size, and a verdict of "worth changing" or "preference". The reviewer drops preferences before asking (established practice: the paste's step 6).
- The question per finding offers: fix now, follow-up ticket, keep as is. "Keep" with a load-bearing reason offers an ADR, as `improve-codebase-architecture` does, so later reviews do not raise it again (default bias: reuse).
- One new read-only agent, `agents/design-reviewer.md`, with two briefs: blind design (for `to-spec`) and Design review (for `code-review`) (context: each `code-review` axis has a typed agent).
- One reference file owns the lens: the paste's six areas and six-step method, for example `skills/code-review/references/design-lens.md`. `to-spec` points at it (AGENTS.md: one owner per shared protocol).
- No dependency on `laravel-best-practices`: it is not in this repo (AGENTS.md: no dead references). Framework knowledge comes from the stack reference files (`implement*/references/laravel.md`) and repo conventions.
- The Design axis skips `inline`-size diffs (3 files or fewer and 150 changed lines or fewer), because the spec-time blind design already covered them (default bias: cost).
- Without a spec, the Design axis rebuilds intent from the commit messages (the paste's step 1).
- `to-spec` runs the blind design on the first write only. An in-place revision runs it again only when Implementation Decisions change (default bias: cost).
- Blind-design differences do not count toward `to-spec`'s "more than three Needs decision items means the grill ended early" rule (that rule is about gaps the grill left, not a second opinion).
- Implementers do not get a separate "state the alternatives" step. Their existing report line "any decision built on an assumed answer" also names the rejected option (default bias: extend what exists).
- A Design axis subagent that fails reports as `not run`, like other axes (context).

## Unresolved risks

- The Design axis adds one subagent per review round. The last release (`913cc56`) made per-ticket review lighter, and this adds cost back at the whole-branch level.
- Asking per finding can add many questions on a large branch. If that becomes noisy, revisit the size-based triage option.
- A blind designer with no chat history can repeat choices the grill already rejected for reasons it cannot see. The Needs decision step is the filter.

## Resolution

Built directly on main in ba9d5c4, with no spec (the user asked to build it in the same session). Every settled line and default above is in that commit: `agents/design-reviewer.md`, `skills/code-review/references/design-lens.md`, the Design axis in `code-review`, the blind design and `Rejected:` lines in `to-spec`, and the wiring in `implement`, `implement-spec`, `implement/references/spec-run.md` and `autopilot/references/worker.md`.

One change from the ledger: a standalone `code-review` only reports Design findings and does not ask about them, because it has no fix batch for a **Fix now** answer to join.
