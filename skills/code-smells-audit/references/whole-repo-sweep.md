# Whole-repo sweep: fan-out

Read in [SKILL.md](../SKILL.md) step 1 when the target is the whole repo.

For a whole-repo sweep, fan out sub-agents by codebase size:

- **Small** (≲100 source files): run the lens passes yourself, sequentially.
- **Medium** (≲1,000): one sub-agent per occurrence lens, each sweeping the
  whole target in parallel.
- **Large**: partition by top-level module or directory, one sub-agent per
  partition running all lens passes; merge candidate lists before verifying.

Each sub-agent gets the target list, the workflow's sweep instructions (SKILL.md step 2), and
the index section(s) for the lens or lenses it will sweep, nothing more: pass the
absolute path of [index.md](index.md) and the lens heading(s)
to read, so you never load the whole index yourself to dispatch. In Claude
Code with this plugin installed, dispatch `subagent_type=leek-skills:smell-sweeper`
(read-only, no project CLAUDE.md, a cheaper model); in other harnesses, dispatch and wait per
[harness-tools](../../harness-tools/SKILL.md), read-only where offered, on the cheapest model the harness lets you pick: the sweep is recall
only, and verification runs here on the main model.
