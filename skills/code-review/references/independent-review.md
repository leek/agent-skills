# Independent review brief

The reviewer's own pass over the PR. It answers one question: **would this change
break something?** It runs on every PR, whether or not anyone else reviewed it, and
it never reads the other reviews first, so their framing cannot narrow what it sees.

## Inputs to hand the reviewer

- The PR title, body, and commit messages (intent, not evidence).
- The range to review. First pass: `<base-sha>...<head-sha>`. Re-review (step 6),
  after `git fetch origin`: when `git merge-base --is-ancestor <last-reviewed-sha> <head-sha>`
  holds, only the PR's own new commits,
  `git log -p --no-merges <last-reviewed-sha>..<head-sha> ^origin/<base>`, which leaves
  out what `gh pr update-branch` merged in from the base. When it does not hold (a
  rebase or force-push), the whole `<base-sha>...<head-sha>` again.
- The repo's `AGENTS.md` / `CLAUDE.md` and `.agents/github-review.md` when present.
- This brief. Do **not** pass the PR's review comments.

## What to look for

Read each changed hunk, then the code it touches outside the diff: callers, callees,
the schema, the tests. A bug often sits in what the diff did not change.

- **Correctness**: wrong condition or boundary, inverted logic, null or empty input,
  off-by-one, a changed return shape that a caller still reads the old way.
- **Security**: missing authorization on a new path, user input reaching SQL, shell,
  HTML, a file path, or a redirect without escaping; secrets in code or logs.
- **Data**: a migration that loses or locks data, a write without a transaction it
  needs, a non-idempotent job or webhook, a race on read-modify-write.
- **Contracts**: a renamed or removed public route, event, config key, column, or API
  field that something outside the diff still uses (`rg` for it).
- **Failure paths**: a swallowed exception, a retry that duplicates side effects, a
  timeout or external call with no handling.
- **Tests**: changed logic, auth, or data behaviour with no test that would fail if
  the change were reverted.

### Workflow coverage

For each changed invariant (ownership, requiredness, eligibility, completion or
another shared rule), find every live path that creates, updates or consumes that
state. Trace callers and registrations; file existence alone is not a live path.
Build a compact map before judging the hunks:

```text
invariant -> path -> producer/consumer -> gate or transition -> test/evidence
```

Check sibling paths together: public versus authenticated submissions, ordinary
versus imported/uploaded creation, queued versus synchronous completion, and full
versus partial previews when they exist. Follow persisted defaults and migrated
state through the same paths. Do not limit the pass to the first class named in a
finding or to files edited by the fix; report only defects caused by the reviewed
change, with a reachable failing case.

For a fix range, re-check the affected invariant across its live siblings before
declaring the fix complete. State which paths were covered and which could not be
reviewed; keep this scoped to the changed invariants.

### Failure-mode probes

The categories above are where review bots find the most, one round at a time. Ask
each probe of every side effect, entry path and input in the range, before anyone else
does:

- **What a side effect returns on failure.** A storage write or delete, a queue push, an
  HTTP call, a mail send: does it throw, or return `false` / `null` that the code then
  ignores? Check the driver's config (a Laravel disk with `throw => false` fails silently).
- **Success recorded before the effect is durable.** A "sent", "processed" or "claimed"
  row, a cooldown or a dedupe key written before the work it stands for has succeeded
  (an after-commit dispatch has not been queued yet when the commit lands). One failure
  must leave the work retryable.
- **Transient versus terminal.** A catch that turns a network blip into "refused" or
  "invalid" (a 401, a permanent unread state) loses the retry the caller would have made.
  Catch only the exception that means refusal.
- **Isolation.** One item's failure inside a loop, chunk or batch must not abort the
  items after it.
- **Budgets.** Serial work inside one job against that job's timeout, and output sized by
  input (decompression, text extraction, a generated filename) against a hard cap.
- **Twice and at once.** A repeated or concurrent request on the same key: is the check
  and the write under the same lock or unique constraint? A validation that runs before
  the transaction is not a guard.
- **Every live path preserves the invariant.** Use the workflow map to compare
  authorization, input bounds, identity resolution, requiredness and completion
  gates. Two writers of the same fact must also agree on keys, hashes and validation.
- **The sibling you imitated.** Diff the new module against the existing one it copies
  (an IAM attachment, an adapter, a terraform module). What the sibling does and the copy
  does not is a finding until shown otherwise.

Skip what formatters, linters, and type checkers enforce, and skip taste. Those are
not findings here.

## Output

One line per finding:

```
Self N: [BLOCKING | MAJOR | MINOR] file:line — <defect> — <concrete failing case>
```

- **BLOCKING**: wrong behaviour, security hole, or data loss on a reachable path.
- **MAJOR**: a real defect on an edge path, or risky logic with no test.
- **MINOR**: worth a note; does not change behaviour.

Every finding names a concrete failing case: the input or state, and what goes wrong.
A finding without one is a suspicion; check it until it has one or drop it. When the
diff is clean, output `Self: no findings`. Follow either result with one compact
`Coverage: <invariant> — <live paths checked>` line per changed invariant. List an
unreached path as `NOT REVIEWED: <path>`; incomplete coverage is not a clean review.
