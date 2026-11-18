# agy mixed valid+invalid tools list, and where the hang warning applies

Question: does a mixed valid-plus-invalid `tools:` list fail the whole subagent, and does the hang occur in interactive or App mode?

## Findings

- Prior note `docs/research/agy-agent-tools-spelling.md`: single bogus name in agy 1.5.10 `-p` fails fast (`unknown component: tool "read_filez" not found in registry`), no hang; mixed list untested.
- Docs scope (`https://antigravity.google/docs/subagents`, summarizing fetch, 2026-11-17): the "Known issue (tool validation)" hang warning sits in the **Antigravity App** tab's Custom subagents section, under the frontmatter table. The CLI tab does not repeat it and points to the Custom subagents page. Interactive/TUI is not mentioned. Mixed lists are not addressed. The warning says "may cause the subagent process to hang"; a fix is "planned".
- Live probe (agy 1.5.10, 2026-11-17, scratch workspace, `.agents/agents/probe-mixed.md` with `tools: [read_file, read_filez]`, `subagent: true`, `mainAgent: false`; run `agy -p "Invoke the subagent named probe-mixed with the task: read note.txt and report its content." --output-format stream-json --dangerously-skip-permissions`): the subagent did not start; the whole agent failed in 31 s (no hang) with `failed to construct executor: failed to resolve components: unknown component: tool "read_filez" not found in registry`. The valid `read_file` did not rescue it: one bad name fails the entire subagent, no partial tool set. Parent run ended `SUCCESS` and relayed the error.
- Caveats: only the CLI `-p` print path was run (one model, one order: valid first, invalid second). Interactive TUI was not run, and the App cannot be driven from here, so the hang the docs describe is not reproduced anywhere. Whether "unmapped" (a real tool the CLI lacks, as opposed to a typo) behaves differently is untested.

## What this unblocks
A mixed list fails the whole subagent at startup in the CLI (loud error, no hang, no partial tools). The documented hang is scoped by the docs to the Antigravity App tab, not the CLI or interactive TUI; it is unreproduced and plausibly an App-only (or older-build) behaviour. Decidable: skills writing agy agent files should list only exact registry names, and need not guard against a CLI hang; App-mode hang remains unverified.
