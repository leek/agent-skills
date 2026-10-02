# Independent review brief

The reviewer's own pass over the PR. It answers one question: **would this change
break something?** It runs on every PR, whether or not anyone else reviewed it, and
it never reads the other reviews first, so their framing cannot narrow what it sees.

## Inputs to hand the reviewer

- The PR title, body, and commit messages (intent, not evidence).
- The range to review: `<base-sha>...<head-sha>` on the first pass, or
  `<last-reviewed-sha>..<head-sha>` on a re-review (step 5).
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

Skip what formatters, linters, and type checkers enforce, and skip taste. Those are
not findings here.

## Output

One line per finding, then nothing else:

```
Self N: [BLOCKING | MAJOR | MINOR] file:line — <defect> — <concrete failing case>
```

- **BLOCKING**: wrong behaviour, security hole, or data loss on a reachable path.
- **MAJOR**: a real defect on an edge path, or risky logic with no test.
- **MINOR**: worth a note; does not change behaviour.

Every finding names a concrete failing case: the input or state, and what goes wrong.
A finding without one is a suspicion; check it until it has one or drop it. When the
diff is clean, output `Self: no findings` and the areas you checked.
