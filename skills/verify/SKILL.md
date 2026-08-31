---
name: verify
description: Exercise a change end to end in the running application (hit the route, run the command, click through the page) and report what actually happened. Use after tests pass, when a change needs proving in the real app, or when another skill's build step ends.
---

# Verify

Tests passing is not the finish line. Exercise the actual flow once, in the running application, and report **what you observed: never what should happen**.

## Process

1. **Pick the flow the change owns.** The route a user would hit, the command an operator would run, the job the system would dispatch, the Filament/Livewire page a back-office user would open. One realistic pass; this is not a test suite.
2. **Run it for real.**
   - HTTP / UI: the app is served (Herd serves Laravel apps at `https://<dir>.test`: never start a server that's already running). Use the project's browser tooling (`agent-browser`, Boost's `browser-logs`) to load the page, perform the action, and screenshot the result.
   - Console: run the artisan command with realistic arguments.
   - Jobs / listeners: dispatch through the real path (`dispatchSync` or trigger the event), then check the side effect where it lands, database rows, storage, logs.
3. **Check the seams the tests can't see.** Browser console errors, the Laravel log (`storage/logs/` or Boost's `read-log-entries`/`last-error`), a queue that needed a running worker, an unbuilt frontend (a Vite manifest error means run `npm run build`, not that the change is broken).
4. **Report faithfully.** What you did, what you saw (status codes, redirects, rendered state, rows written), and anything that surprised you: with the evidence. If a step couldn't be exercised (needs credentials, a webhook, a human), say so plainly instead of marking it verified.

## Guardrails

- Verify against local/dev: never run mutating flows against a real environment's data without explicit approval.
- Leave no residue: throwaway records created during verification get cleaned up, or created under an obviously-fake identity the seeds already use.
