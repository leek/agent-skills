# Harness mechanics

Two branches of [`diagnosing-bugs`](../SKILL.md), each reached from the step that names it.

## Running the HITL script

Phase 1, way 10: the loop is `scripts/hitl-loop.template.sh`.

Its `read -p` prompts need a terminal, so where the harness has structured questions ([harness-tools](../../harness-tools/SKILL.md)), run the script's steps as questions instead: each `step` as `Done` / `Couldn't`, each closed `capture` as its answers as options, an open `capture` through the free-text Other. Otherwise hand the user the edited script to run in their own terminal and paste back its `--- Captured ---` block.

## Watch the probes live

Phase 4: the loop needs a running server or reads a log.

Start the dev server, or `tail -f` the app log, in the background under `Monitor` where available, filtered with `grep --line-buffered -E '\[DEBUG-a4f2\]|ERROR|Exception|Fatal'` (add the stack's own error signatures), so each probe hit arrives as an event while the loop runs. Otherwise send that output to a file and grep it for the tag and the error signatures after each run.
