# Session selection

Select human parent sessions before applying the requested count. Open every source
read-only. Store inventories and batch files in the session scratchpad, never beside logs.

## Discover candidates

These commands list candidates, not the final sample. A missing directory means that
harness has no available logs; report it. Do not rank compressed archives by compressed
size or treat filesystem modification time as the conversation date.

```sh
find ~/.claude/projects -type f -name '*.jsonl' ! -path '*/subagents/*'
find ~/.codex/sessions -type f \( -name 'rollout-*.jsonl' -o -name 'rollout-*.jsonl.zst' \)
find ~/.grok/sessions -type f -name chat_history.jsonl
find ~/.gemini/antigravity-cli/conversations -type f -name '*.db'
```

Pass paths as quoted arguments; preserve spaces. Read plain JSONL directly. For an
archive, stream `zstd -dc -- "$file"` into the same JSONL parser. Never decompress in
place. If the reader is missing or a file is corrupt, record that exclusion explicitly.

## Group and identify authorship

- **Claude:** a top-level `<uuid>.jsonl` owns `<uuid>/subagents/agent-*.jsonl`.
  Also inspect its initial prompt: top-level files can be automated review/panel runs.
- **Codex:** inspect the first `session_meta` payload in each file; later metadata
  can be inherited parent context, not another session. Use `id` (or `session_id`) as the
  identity; deduplicate a plain and compressed copy with the same identity. A
  `thread_source` of `subagent`, or a `source.subagent` object, identifies a child.
  Follow `source.subagent.thread_spawn.parent_thread_id` recursively to its root.
  Keep children as evidence for that root, including children in other date directories.
  A child with an unavailable parent is an orphan exclusion, not a human session.
- **Grok:** use the session directory ID and inspect the prompt history plus initial
  conversation turns. `/private/tmp` and panelist briefs are automation clues, not
  proof by themselves; classify from the actual task. Keep automated panelist logs
  as linked evidence when their human parent can be identified.
- **agy:** join history `conversationId` to the database basename. Inspect step 14
  and relayed step 101 messages when history is absent or authorship is ambiguous.
  A relayed prompt is not another human correction. Open SQLite with `-readonly`.

For Codex, this query extracts grouping fields from either plain or streamed JSONL:

```sh
jq -nc 'reduce inputs as $event (null;
  if . == null and $event.type == "session_meta" then $event.payload else . end) |
  {id:(.id // .session_id), timestamp, thread_source, source}'
```

Use prompt-history matches and neighboring turns to distinguish human input from
agent briefs, preambles, summaries, and quoted earlier conversations. History can
miss queued corrections, so inspect the transcript too. Mark unresolved authorship
as unknown and exclude it from claims about human correction frequency.

## Select and batch

Exclude the current retro and its workers to avoid mining the audit itself. Rank
eligible roots by their latest conversation-event timestamp (including linked child
activity), using mtime only as a labeled fallback. Select N roots. If the user asks
for coverage across harnesses, allocate the sample across available harnesses and
state the allocation rather than letting the busiest harness consume every slot.

Write `parents.jsonl`: one JSON object per root with `harness`, `id`, `path`,
`timestamp`, and `children` (paths). Dispatch each entire object to one batch so
children stay with their parent. Report counts of selected roots by harness, linked
children inspected, automated/orphan/unknown exclusions, and unreadable files.
The batch manifest and coverage totals must agree before synthesis.
