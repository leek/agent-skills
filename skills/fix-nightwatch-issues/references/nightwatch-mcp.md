# Nightwatch MCP mechanics

Use the Nightwatch MCP tools. If they are not loaded, discover them first.

## Issue tools

1. `list_applications`: gives the application id.
2. `list_environments`: gives the production environment.
3. `list_issues`: the working set. Filter on status `open`, sorted by last seen.
4. `get_issue`: one issue's stack trace, code context, occurrence stats, and execution
   context. Step 3's `file:line` comes from here.
5. `add_issue_comment`: the comment step 5 writes, with the root cause and the fix sha,
   or with what unblocks an issue that stays open.
6. `update_issue`: sets the status. Step 5 sets `resolved`, after the comment.

## An issue that will not load

A `get_issue` that errors ("Server Error") or is too large to read is a problem with
that one issue's payload, not with the environment. Retry it once at most. Do not walk
the `list_environments` ids through `environment_id`: an issue lives only in the
environments its own `get_issue` lists, and any other id returns "Environment … not
found for this issue". Work from its `list_issues` summary instead.
