---
name: fix-github-issues
description: Verify, triage, fix, and close review-bot GitHub issues one finding at a time.
disable-model-invocation: true
argument-hint: "Optional issue numbers or a label (defaults to the project's review-bot label, else ai-review)"
allowed-tools: "Bash(gh issue view *) Bash(gh issue list *) Bash(gh api *)"
---

# Fix GitHub Issues

Work the open issues that a review bot filed. Each issue is a **container of findings**:
some are legit, some stale, some wrong. Every finding earns its own verdict from the
code on `origin/main`, never from the issue's headline. An issue closes only when no
legit finding is left in it.

**Project context.** Read `.agents/github-review.md` when the repo has one. It holds
the bot label, the auto-dismiss and never-dismiss lists, and the stack facts the bots get wrong. Then
follow the repo's `AGENTS.md` / `CLAUDE.md` rules for tests, lint, cache clears, and a
dirty tree.

## 1. Build the working set

Run `git fetch origin`, and verify everything against `origin/main`, not local `main`.
List the open issues with the bot label (or the ones the user named), newest first.

Walk order is newest to oldest, but let evidence reorder it. A newer diff that
introduced a defect an older issue already flagged makes the older finding LEGIT, and
you fix both in one commit chain. A newer commit that fixed an older finding makes that
finding STALE: cite the sha.

## 2. Classify every finding

For each issue, read its body and every comment (note any "fixed in <sha>" or "false
positive" from earlier runs). Read the commits it reviewed. Then write one line per
finding:

```
Finding N: [STALE | AUTO-DISMISS | HALLUCINATION | LEGIT] — <one-line evidence>
```

- `Finding 1: STALE — fixed in bf707fde3, see app/Foo.php:42`
- `Finding 3: HALLUCINATION — rg 'BarPolicy::class' returns 0; symbol does not exist`
- `Finding 4: LEGIT — app/Auth.php:88 still uses < instead of <=, exploitable on token boundary`

Verification rules:

- For a "class, method, or permission missing" claim, `rg` the symbol across the source
  and the tests. If it exists, the finding is HALLUCINATION.
- For an "X may break Y" claim, trace the real call sites. If nothing calls it, the
  finding is STALE or HALLUCINATION.
- A finding on a file the commit did not touch is HALLUCINATION.
- A documented design choice in the commit body that contradicts the finding is
  AUTO-DISMISS.
- A finding whose body retracts itself ("this technically works", "disregard") is
  AUTO-DISMISS.

**Delegate the legwork on a large set.** With more than 5 findings, hand the first pass
to read-only workers in batches of about 10. Each brief carries the batch (id, reviewed
commit, file:line, body), the ref `origin/main`, the line format above, and the
verification rules. In Claude Code with this plugin installed, dispatch
`subagent_type=leek-skills:finding-verifier` for each batch in parallel. Elsewhere, use any
read-only sub-agent on a cheaper model, or classify inline when the harness has none.
Then re-verify yourself every line that came back LEGIT or UNSURE. You read that code
for the fix anyway.

**Second pass.** Re-read every LEGIT against the project's auto-dismiss list and
downgrade any match. A category on the project's never-dismiss list stays LEGIT. Do this
before writing any code.

Completion criterion: every finding in the working set has a line, and the second pass is done.

## 3. Fix the legit ones

Per LEGIT finding: make the minimal change, with no drive-by refactors. Add a test for
logic, auth, or data changes and run it green. Commit it on its own (Conventional
Commits, explicit staging). Put `fixes #NNN` **only** on the commit that resolves the
issue's last legit finding, so the issue closes at the right moment.

A LEGIT finding you cannot fix (a secret rotation, infra, a human decision) keeps the
issue OPEN. Comment to dispose of the other findings, and name what is blocking.

## 4. Close with a disposition

When the issue closes, or you close it by hand because nothing was legit, post one
comment with one bullet per finding:

```
- Finding 1 (X): fixed in <sha>
- Finding 2 (Y): stale — superseded by <sha>
- Finding 3 (Z): auto-dismiss — <category>
- Finding 4 (W): hallucination — symbol does not exist at claimed location
```

If you later find a misclassified finding, reopen the issue with a correction note.

Completion criterion: every issue in the working set is closed with a disposition, or
stays open with a comment that names its blocker. Report the tally: fixed, stale,
auto-dismiss, hallucination, and blocked.
