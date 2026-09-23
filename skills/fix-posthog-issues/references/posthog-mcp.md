# PostHog MCP mechanics

The PostHog MCP exposes one `exec` tool, which takes CLI-style command strings:

```text
search <regex>                     # find tools
info <tool_name>                   # read a tool's schema once, then reuse it
schema <tool_name> <field_path>    # drill into any field that carries a `hint`
call <tool_name> <json_input>      # invoke
```

## Error-tracking tools

1. `query-error-tracking-issues-list`: the working set. Filter on `status: active`, and
   order by last seen. **Can lag** (see below).
2. `query-error-tracking-issue`: one issue's detail and impact. This read is fresh.
3. `query-error-tracking-issue-events`: event samples, with stack traces, code
   variables, `session_id`, URL, browser, and person.
4. `error-tracking-issues-partial-update`: takes
   `{"id": "<uuid>", "status": "active" | "resolved" | "suppressed"}`, and also
   `severity`, `name`, and `description`. Use
   `error-tracking-issues-assign-partial-update` for assignees, and
   `error-tracking-issues-merge-create` to fold duplicates into one issue.
5. `error-tracking-suppression-rules-create` / `-list` / `-update`: permanent
   server-side drops.
6. `execute-sql`: session timelines for frame archaeology. Confirm the columns before
   you query. Filter on the `session_id` and a tight timestamp window around the
   exception.

## Status write lag

After `error-tracking-issues-partial-update`, the list can show the old status for a
while (aggregation lag). Confirm with `query-error-tracking-issue` for that id. Do not
write the status again just because the list looks stale.

## `resolved` vs `suppressed`

`resolved` reopens automatically if the error recurs. Use it for fixes pending deploy,
stale issues, and transients. `suppressed` never comes back. Keep it for vendor code you
will never patch and for scanner or browser noise.
