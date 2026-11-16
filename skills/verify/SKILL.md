---
name: verify
description: Exercise a change end to end in the running application (hit the route, run the command, click through the page) and report what actually happened. Use after tests pass, when a change needs proving in the real app, or when another skill's build step ends.
---

# Verify

Tests passing is not the finish line. Exercise the actual flow once, in the running application, and report **what you observed: never what should happen**.

Two layers decide how to run a flow:

- The **verify profile** holds this repo's own answers: how the app is served, who to sign in as, what to watch, which data is safe, what must never fire. It lives in the target repo at `.agents/verify.md`, and the user owns it. Format: [VERIFY-PROFILE-FORMAT.md](VERIFY-PROFILE-FORMAT.md).
- The **defaults** below fill whatever the profile leaves out.

The profile wins over the defaults. The [Guardrails](#guardrails) win over both.

## Load the verify profile

Read `.agents/verify.md` in the current checkout; in a worktree that has none, read the main checkout's copy (the first entry of `git worktree list`).

When neither exists, this repo has not set the skill up:

- **A user is here to answer** (an interactive main session): ask before any other work (a structured question ([harness-tools](../harness-tools/SKILL.md)), otherwise in chat):
  - **Set it up now** (recommended): bootstrap the profile per [VERIFY-PROFILE-FORMAT.md](VERIFY-PROFILE-FORMAT.md#bootstrap), then continue.
  - **Skip this time**: continue on the defaults, and say in the report that the repo has no verify profile.
- **Nobody answers** (a sub-agent, an Autopilot worker, an unattended loop such as `sweep`, `prune-tests`, `/loop` or a scheduled run, any headless run): ask nothing and write nothing. Continue on the defaults, and add one line to the report: `No .agents/verify.md in this repo; ran on the defaults.`

Done when the profile is loaded, or you know the run is on the defaults and why.

## Process

1. **Pick the flow the change owns.** The route a user would hit, the command an operator would run, the job the system would dispatch, the Filament/Livewire page a back-office user would open. Select a small scenario that can expose the changed behavior: grouped or aggregated UI needs multiple related records with distinct values; interactive state needs the action and its reversal (for example expand, collapse, expand), checking controls and content agree each time. Use records the profile's **Data** marks safe, or isolated fixtures under the guardrails below. Keep the pass focused on the change, not a broad test suite.
2. **Run it for real.**
   - HTTP / UI: load the URL from the profile's **Serve** (for a worktree, the URL from the worktree command it names, else the URL the worktree's bootstrap printed), signed in as the profile's account for the role the flow needs. Use the project's browser tooling (`agent-browser`, Boost's `browser-logs`) to load the page, perform the action, and screenshot the result of every step that shows a page. A browser test, including one pointed at `127.0.0.1`, is a test run, not this step.
   - Console: run the command with realistic arguments.
   - Jobs / listeners: dispatch through the real path (`dispatchSync` or trigger the event), then check the side effect where it lands, database rows, storage, logs.
3. **Check the seams the tests can't see.** Before driving the flow, start what the profile's **Watch** names under `Monitor` where available, so each error arrives tied to the action that caused it; otherwise read the log tail after each action. Look for browser console errors, the app log, a queue that needed a running worker, an unbuilt frontend (a Vite manifest error means run `npm run build`, not that the change is broken). Expect the profile's **Traps**.
   - **Calculated reports:** for one nontrivial record, reconcile detail rows, totals, badges/status, units, and the selected period against an independent worked example or source records. When adjacent values intentionally use different periods or populations, confirm the UI makes that difference explicit. Record the scenario and observed values; an unexplained mismatch fails verification.
4. **Report faithfully.** What you did, what you saw (status codes, redirects, rendered state, rows written), and anything that surprised you: with the evidence. If a step couldn't be exercised (needs credentials, a webhook, a human), say so plainly instead of marking it verified. List each screenshot's path, so a PR opened later can embed it. In chat, start each step's line with ✅ worked as expected, ❌ broke, or ⚠️ surprised you or could not be exercised. When you run as a sub-agent and your report goes to another agent, write the same plain words with no mark.

## Defaults

Where the profile is silent or absent:

- **Laravel on Herd:** the main checkout serves at `https://<dir>.test`; a worktree at the `url` its bootstrap's `herd workspace` printed (`herd workspaces --json` lists it again). Watch `tail -f storage/logs/laravel.log | grep --line-buffered -E 'ERROR|CRITICAL|Exception'`, plus `php artisan queue:work` when a queued job is involved; Boost's `read-log-entries`/`last-error` read the same log. Console flows are artisan commands.
- If `agent-browser` fails with `ERR_CERT_COMMON_NAME_INVALID` after `herd secure`, close and reopen the browser session so Chromium reloads the trust store.
- If a dev toolbar (such as Laravel Debugbar) covers a click target, collapse or disable it rather than forcing the click.
- Other stacks: the URL and log the repo's `README.md` or `AGENTS.md` names.

## Record a correction

When the user corrects how this repo is verified (a wrong URL, the account to use, a service never to trigger, a quirk to expect):

1. **Nobody answers** (the same runs as in [Load the verify profile](#load-the-verify-profile)): write nothing; put the correction in the report as a suggested profile line.
2. Otherwise, look in the profile you loaded (the current checkout's copy when it has one, else the main checkout's) for the section that covers it, and sharpen that line rather than adding a near-duplicate. With no profile yet, create it in the main checkout with the `# Verify` heading and that one section, and tell the user it is a new, uncommitted file there.
3. Show the user the added or changed text in your reply.

## Guardrails

The profile cannot loosen these:

- Verify against local/dev: never run mutating flows against a real environment's data without explicit approval.
- Trigger nothing the profile's **Off limits** names, even locally: report that step as not exercised.
- Leave no residue: throwaway records created during verification get cleaned up, or created under an obviously-fake identity the seeds already use.
