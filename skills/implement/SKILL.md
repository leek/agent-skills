---
name: implement
description: Implement one Laravel work item end to end — scope and claim it when trackable, TDD at chosen seams, commit, review, verify, and resolve it.
disable-model-invocation: true
---

# Implement

Implement exactly one work item per session, test-first and verified end to end. A work item is a ticket, a spec that fits one session, or an agreed conversation scope.

Pipeline position: decide (`grill-with-docs`/`wayfinder`) → spec (`to-spec`) → slice (`to-tickets`) → **build (`implement`, review and verify inside)**.

## Laravel guardrails

- **Never** run `migrate:fresh`, `migrate:rollback`, or another destructive database operation without explicit approval. Put schema changes in new migrations; sequence live-table changes expand–contract.
- Verify identifiers before using them — route names, config keys, enum values, icon names, and package APIs. A manifest entry alone does not prove registration or use.

## Process

### 1. Scope and claim the work

Classify the input and make its acceptance criteria explicit:

- **Ticket** — fetch its full body and comments, plus its parent spec or map when linked. A Wayfinder child is eligible only when its type is `task`; stop on other ticket types because they are not implementation work. The ticket is the work item.
- **Spec** — fetch its full body and comments. If it contains more than one independently deliverable slice or cannot fit one session, stop and tell the user to run `to-tickets`; otherwise the spec itself is the work item.
- **Conversation** — restate the scope and behavior criteria in a few lines. It has no tracker claim or resolution.

For a trackable work item, resolve the tracker once through `docs/agents/issue-tracker.md` (written by `/setup`) or an `## Issue tracker` section in `CLAUDE.md`/`AGENTS.md`; default to the referenced local markdown artifact under `.scratch/` when neither exists. Confirm every blocker is closed through the configured tracker operation or the item's `Blocked by` data, and stop before claiming if any remain open. Then claim before building:

- On a shared tracker, use its configured claim operation or assign the work item to the driving dev.
- On a local ticket from `to-tickets`, or a directly implemented local spec, change or add `**Status:** in-progress (claimed <date>, <who>)` near the top.
- On a local Wayfinder child, use the configured Wayfinding **Claim** operation (`claimed-by`).

If the item is already claimed or in progress, stop; treat the claim as stale only when its work is visibly committed or clearly abandoned.

After claiming, or after scoping conversation-only work, record the output of `git rev-parse HEAD` as immutable `base_sha`. Use that exact SHA for review and for proving failures pre-existing.

Finish this step only when the work fits one session, its acceptance criteria are explicit, every trackable item is claimed with blockers closed, and `base_sha` is recorded.

### 2. Choose the seams

Use the ranking and selection rules in the `tdd` skill's **Seams — where tests go** section. Reuse seams already recorded in the spec; otherwise **choose them yourself and state the choice** — one line per seam, no approval round. Seam placement is test structure, which `grilling`'s **What still earns a question** hands to you, and the rules are the single source of truth. Ask only on a genuine fork the rules rank equally where the two placements would make materially different work.

Finish this step when every acceptance criterion has a seam.

### 3. TDD loop

Run the `tdd` skill at the chosen seams. Discover the repository's focused-test and static-analysis commands from its scripts and existing usage; run the focused test each cycle and static analysis regularly when configured.

Finish the loop only when every acceptance criterion is covered at a chosen seam, every focused test passes, and configured static analysis is green.

### 4. Format and commit a reviewable checkpoint

Run the repository's configured formatter; when it uses Pint, run `vendor/bin/pint --dirty`. Check `git status --porcelain`, stage only work-item files by explicit path, and leave foreign changes unstaged. Commit to the current branch so review can inspect the real `base_sha...HEAD` range.

Finish this step with every work-item change committed, every foreign change untouched, and the checkpoint commit SHA recorded.

### 5. Review

Run the `code-review` skill against `base_sha`. Resolve every actionable finding through the `tdd` loop, rerun affected focused checks and static analysis, format, stage explicit paths, and commit the fixes. Re-run `code-review` after each fix commit.

Finish this step only when review reports no unresolved actionable findings and every work-item change is committed.

### 6. Run the final automated checks

Ask the user first (via `AskUserQuestion` where available, otherwise a plain question in chat) whether to run the full test suite as the final automated gate. If they decline, skip the full run — the focused tests from step 3 stand as the automated evidence — and record the skip so step 8 reports it plainly.

When approved, run the repository's full test suite (`php artisan test` when the repo defines no wrapper). Fix failures caused by the work. Prove an unrelated failure pre-existing against `base_sha`, then note it plainly instead of expanding scope.

Any code fix returns to steps 3–5 before this gate runs again. Finish this step when the user declined the full run, or when every caused check passes and every remaining failure has base-SHA evidence.

### 7. Verify end to end

Run the `verify` skill. A product failure returns to steps 3–6 before verification runs again. Successful verification is required to resolve a trackable work item.

If an external dependency prevents verification, keep the committed implementation, report the exact blocker, and leave the work item open. Mark nothing verified on inference alone.

### 8. Close the loop

After successful verification, record what was built, any justified deviation, verification evidence, and the implementation commit SHA or SHAs; check off every satisfied acceptance criterion. Resolve the work item according to its branch:

- **Shared tracker** — post the resolution and close the work item.
- **Local ticket or directly implemented spec** — set `**Status:** closed` and append `## Resolution`.
- **Local Wayfinder child** — use the configured Wayfinding **Resolve** operation.
- **Conversation** — report the result without tracker mutation.

When a ticket has a parent spec or map, leave the parent open. When the spec itself was the one-session work item, close that spec. If a mutated local tracker artifact is tracked, stage only that artifact and commit the resolution separately; if it is ignored or untracked, leave it as tracker state. Resolution text cites the implementation commits, never its own closure commit.

For trackable work, re-read the tracker artifact after mutation and verify its final state.

Finish when the implementation commits and any separate resolution commit are recorded and the tracker's final state is verified, or the conversation-only result is reported. Then stop; any next work item gets a fresh session with a clean context.

## When you're done

End the session by printing the block below — on a clean finish, a stop, or a dead end. On harnesses without slash commands, write the command as plain phrasing (`run implement on <ref>`) instead of `/implement <ref>`.

```text
---
Pipeline: decide → spec → slice → **build**   (4 of 4)
Done: <what now works, the work-item ref if any, commit(s), verification state>
Next:
  • <condition> → /<skill> <ref>
```

For a trackable work item with a parent, check the tracker for the remaining frontier before writing the block — don't guess at what's left. List only the conditions that actually apply, most likely first:

- **More frontier tickets on the parent spec** → `/clear`, then `/implement <next frontier ticket>`; name it and how many remain
- **Every ticket on the parent spec is closed** → nothing to run; say the spec is complete and name anything deferred out of scope
- **Remaining tickets are all blocked** → `/implement <the blocker>` first, or `/grill-me` if the blocker is a decision
- **The build exposed a decision nobody made** → `/grill-me` on it, then re-run `/to-spec` if the spec is now wrong
- **Verification is externally blocked** → keep the work item open and name the exact unblock condition
- **Stopped mid-work** → say what passes, what is committed or uncommitted, the claim state, and the next red test to write
