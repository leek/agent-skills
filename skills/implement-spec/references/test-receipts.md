# Test receipts

Use for a repeated focused test command after updating an implementer branch to the
integration tip and when checking its prospective integration merge. Run ordinary
TDD iterations normally. Receipts reuse successful execution evidence, never a
review, application verification, or a required CI check.

## Establish reproducibility

The orchestrator prepares a context JSON outside the worktrees, with these fields:

```json
{
  "reproducible": true,
  "runtime": "fingerprint of interpreter, runner, OS and architecture",
  "dependencies": "fingerprint of actual installed dependencies and lockfiles",
  "configuration": "fingerprint of effective test config and relevant environment",
  "environment": "identity of the equivalent isolated services and execution setup",
  "fixtures": "fingerprint of the repeatable fixture/reset recipe and initial state"
}
```

Replace every description with verified fingerprints, regenerating them before
each invocation. Hash sensitive inputs; store no credentials. Lockfiles alone do
not prove installed dependencies match. Worktree paths, URLs, databases, time,
randomness, network responses, ignored/generated files and inherited environment
can affect a test: include their identity or prove the runner normalizes them. Each
ticket normally has a different environment fingerprint; share one only after
proving equivalent setup. Reproducible means every run establishes the same initial
state without changing inputs used by another concurrent worker.

If any input is unknown, use `reproducible: false` or run the command normally. Never
invent a matching fingerprint to obtain a hit. The helper cannot discover external
state or validate the caller's claim of equivalence.

Tracker claims stay uncommitted during a build. If the command, its discovery, and
its setup never consume `.scratch/`, explicitly add `"planning_metadata_unused": true`
to the context. This projects only `.scratch/` out of the compared Git tree and
dirty/untracked checks. All other paths remain covered. Omit it when uncertain;
there are no arbitrary path exclusions. Record the evidence for that choice in the
run notes. This option also participates in the context fingerprint.

## Run and reuse

In the worktree being tested, run:

```sh
bash <this-skill-dir>/scripts/run-with-receipt.sh "$notes/receipts/<NN>.json" "$notes/test-context-<NN>.json" -- <focused test command and arguments>
```

Here `<this-skill-dir>` is the `implement-spec` skill directory. Use one receipt per
ticket and command; the implementer reports its path, command, and tested tree with
its result. The helper runs on a miss, forwards command output to stderr, and emits
JSON on stdout. A successful run records the index tree (projected only when the
metadata option above is verified) when tracked files in scope match it, no
nonignored untracked files in scope exist, and inputs remain unchanged across
the run. Thus it also works during `git merge --no-commit`, when the index holds the
prospective merge. Dirty or uncertain state executes tests without caching them.

At integration, regenerate context and invoke the same command through the helper.
An identical tree, command, repository and context reuses the result. A changed
integration tip, conflict resolution, or environment causes a run. Separate receipt
files have one writer each; wait for the implementer's report before using its file.
Missing, malformed, or failed receipts cause a run. A failing run exits nonzero and
invalidates the old receipt, so the existing merge-abort/fix path still applies.

Report `reused` distinctly from `passed`; reference the original receipt as evidence.
Final checks, delivery coverage, browser verification, and independent PR review
keep their existing requirements. A repo-mandated fresh execution always runs fresh.
