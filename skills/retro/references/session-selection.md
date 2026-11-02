# Session selection

`scripts/select-sessions.sh` does discovery, grouping, ranking, and batching. This file
holds what it cannot decide: who wrote a session.

## What the script already does

- Pre-filters each harness to its newest files by mtime, so old archives are never
  streamed, then ranks roots by the conversation's own timestamp, not the file's.
- **Claude:** `<uuid>.jsonl` owns `<uuid>/subagents/agent-*.jsonl`; harness agent
  worktrees are skipped.
- **Codex:** identity from the first `session_meta` (`id`, else `session_id`), a plain
  and compressed copy deduplicated; a child (`thread_source: subagent` or a
  `source.subagent` object) is followed up its `parent_thread_id` chain to its root. A
  child whose root is not available is excluded as an orphan.
- **Grok:** `summary.json` gives the kind (`subagent*` children attach to the root whose
  history names their id) and the last-active time; `<user_query>` holds the human text.
- **agy:** `history.jsonl` joins `conversationId` to the `.db` basename.
- Hints that exclude a root unless `--keep-automated`: a headless entrypoint (`sdk-cli`,
  `sdk-py`, `codex exec`, Grok `headless`), a panelist brief, an agy conversation absent
  from history with no step 14 prompt in its `.db` (relayed or headless). A `/private/tmp`
  cwd, or an agy prompt found only as step 14, sets `clue`.
- Roots rank by their latest activity, linked children included.

## Decide authorship

Read each selected root's `first_prompt`, and, when that is ambiguous, its first few
`user` events from `extract-signal.sh`.

- A `/private/tmp` cwd or a panelist-shaped brief is a clue, not proof; classify from the
  actual task. Keep an automated panelist's log as linked evidence when its human parent
  is identifiable.
- An agy prompt that is not in history is step 14 or a relayed step 101 in the `.db`. A
  relayed prompt is not another human correction.
- Prompt history can miss queued corrections; the transcript's `queued` events hold them.
- Mark unresolved authorship as unknown and exclude it from claims about human
  correction frequency.
- A root that is not a human session: rerun with `--exclude <id>`, so the count stays N.

## Report

Selected roots by harness, linked children, exclusions by reason (automated, orphan,
unknown, caller), unreadable files, and missing harnesses. The batch files and these
totals must agree before synthesis.
