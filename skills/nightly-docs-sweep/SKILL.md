---
name: nightly-docs-sweep
description: Run a documentation sweep for a codebase. Use this when the user asks for a nightly docs sweep, overnight docs sweep, documentation drift audit, README/setup/API docs refresh, docs sync after implementation changes, or a reviewable pull request that makes docs match the current code.
---

# Nightly Docs Sweep

## Goal

Make repository documentation match the current implementation, then leave a reviewable change set or pull request.

## Loop Prompt

```text
Whenever a documentation pass is needed, review the codebase in full and make sure all documentation reflects the current implementation. Update stale documentation, verify the changes, then open a pull request.
```

Stop when documentation matches the current implementation and the docs changes are ready for review.

## When To Use

Use this whenever implementation changes may have left READMEs, setup guides, API references, examples, architecture notes, comments, or runbooks behind.

## Workflow

1. Review implementation changes since the last documentation pass.
2. Compare the repository's documentation with the code, configuration, commands, and behavior that currently ship.
3. Update only stale or missing material. Do not rewrite accurate documentation just to create activity.
4. Verify commands, links, examples, configuration names, API shapes, and setup steps against the current repository.
5. Run the relevant checks available in the project, such as documentation tests, link checks, type checks, unit tests, or linting.
6. Summarize the documentation drift found, the files changed, and the verification performed.
7. If the user asked for a PR and the environment supports it, open a pull request with a clear title and body.

## Report

End with:

- Documentation areas checked.
- Stale or missing docs found.
- Files updated.
- Verification commands run and their results.
- Remaining gaps or blockers.
- Pull request link, if one was opened.

## Guardrails

- Keep scope tied to real implementation behavior.
- Preserve accurate documentation and user-authored wording where practical.
- Do not invent behavior that is not backed by code, configuration, tests, or project docs.
- If the repository is too large for a full sweep in one pass, prioritize changed or high-traffic docs first and clearly state the remaining scope.
