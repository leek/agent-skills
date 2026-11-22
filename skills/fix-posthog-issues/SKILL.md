---
name: fix-posthog-issues
description: Triage active PostHog error-tracking issues by root cause, fix the legit ones, and resolve or suppress the rest with evidence.
disable-model-invocation: true
argument-hint: "Optional issue ids; defaults to all active issues"
compatibility: "Requires the PostHog MCP server"
---

# Fix PostHog Issues

Active PostHog error-tracking issues are mostly browser exceptions from the JS SDK, plus server-side `$exception` captures. In a Livewire / Alpine SPA most of them are **transient** navigation races, vendor throws, or browser noise, not bugs. Read the session timeline as well as the stack and the occurrence spread.

Follow the shared [production triage](../diagnosing-bugs/references/production-triage.md) frame: its ground rules, then its steps 1–5 in order. This file adds only what is specific to PostHog, under the same step numbers. The project-context file is `.agents/posthog.md`: the project id, the `before_send` filter file, the app's registration patterns, and the precedent fixes.

## 0. Load the working set

Read [`references/posthog-mcp.md`](references/posthog-mcp.md) before your first PostHog call. It covers the single `exec` tool, the error-tracking tools, the status lag, and `resolved` vs `suppressed`. Stay on the project named in the project context: never switch projects. List `active` issues ordered by last seen.

## 1. Group by root cause

PostHog groups issues by exception type and top frame. For example, one `x-data` scope owner that morph-inserts late throws `X is not defined` for every property its descendants read, and each property becomes its own issue.

## 2. Classify each group

Pull event samples first: stack frames, URL, `session_id`, and person. Categories, between STALE and LEGIT:

- **TRANSIENT**: a `wire:navigate` morph race or a bundle-hash change mid-deploy. The signatures are Alpine `X is not defined` / `Can't find variable`, Livewire `Illegal invocation`, `Could not find Livewire component`, `Snapshot missing`, and `Alpine.navigate|morph is not a function`. Resolve these (they auto-reopen on regression). Do not hunt them.
- **VENDOR**: the throw bottoms out in Livewire, Alpine, Filament core, or a third-party plugin. Suppress it. Leave vendor JS unpatched.
- **NOISE**: opaque cross-origin `Script error.`, ResizeObserver loops, link-scanner captures, non-Error captures, and `Failed to fetch` on navigate-away. Suppress these, or drop them in `before_send`.

LEGIT here also means the error fires **outside a navigation window** and recurs on one path.

Examples:

- `Issue a1b2: TRANSIENT — Alpine "segment is not defined" on /leads/pipeline inside a nav window; 3 occ`
- `Issue c3d4: LEGIT — redirect sets skipRender, modal DOM outlives mountedActions=[]; 91 occ, 1 user`
- `Issue e5f6: VENDOR — thrown inside a Filament plugin's entangle; suppress`

**LEGIT vs TRANSIENT.** The best test is whether the error fires within a few seconds of a `livewire:navigate` event. Secondary tests: a handful of occurrences spread across many users and paths is transient, while dozens on one path from one user doing one interaction is legit. A transient race is usually bracketed by `$pageleave` and `$pageview` events for the same URL.

**When the top frame is a lie.** A top frame of `[Alpine] JSON.stringify` inside `livewire.min.js` is Alpine's expression-error rethrow, not the thrower. Pull the session's event timeline around the exception with `execute-sql`, and read what surrounds it.

## 3. Fix each LEGIT group at the right layer

- App Alpine component or page script: use the project's registration pattern.
- Livewire or Filament component behaviour: fix the PHP, with a Pest regression test (a styling-only fix gets `verify` instead).
- A class of noise you control: add a `before_send` matcher. Gate it to the navigation window unless the value is always benign, so a steady-state break still reports.
- Vendor or browser noise: add a suppression rule, never a vendor patch.

JS changes need the asset build. The commit body lists refs as `PostHog: <id>, <id>`.

## 4. Set status

Set `resolved` on fixed, stale, and transient issues, and `suppressed` on vendor and noise issues. Confirm each change with the single-issue read. A shipped JS fix leaves a tail of occurrences from browsers that still run the old bundle, so "pending deploy verification" applies to every JS fix. A blocked LEGIT issue stays `active`. Report the tally as `N active → M`.

## 5. Offer a deploy re-check

The re-check prompt: "With the PostHog MCP, read last-seen for issues <ids>; set back to active, with a note, any seen after <deploy date> beyond the old-bundle tail."
