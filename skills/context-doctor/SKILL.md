---
name: context-doctor
description: Audit every persistent instruction, memory, and configuration source that shapes the agent in this project, and propose the smallest accurate set. Nothing changes until you approve it.
disable-model-invocation: true
argument-hint: "[instructions] [memory] [config] [project path]; defaults to all three, for the current directory, user-level sources included"
allowed-tools: "Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/context-doctor/scripts/inventory.sh *) Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/context-doctor/scripts/usage-counts.sh *) Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/context-doctor/scripts/state.sh dir) Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/context-doctor/scripts/state.sh snapshot *) Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/context-doctor/scripts/state.sh decline *) Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/context-doctor/scripts/state.sh audited *) Bash(claude plugin details *)"
---

# Context Doctor

Every line that persists into an agent's context earns its place through accuracy, relevance, and changed behaviour, or it goes. This skill finds the lines that do not: **obsolete** (describes a past state), **one-off** (a single conversation's correction kept forever), **redundant**, **wrongly scoped**, **verbose**, **conflicting**, and **no-op** (what the model does anyway). The outcome is the smallest accurate context that keeps every useful instruction, safeguard, and decision.

The audit is read-only. Files change only in step 7, only as approved, after a snapshot. Scripts do the mechanical work: discovery, load rules, imports, sizes, duplicates, usage counts. Subagents on cheaper models do the per-line reading. You do the judgement across files and the final say on every change.

<scratch> is the session scratchpad, otherwise `$TMPDIR`; the run's files go in `<scratch>/context-doctor/`.

## Arguments

`instructions` (CLAUDE.md, CLAUDE.local.md, rules, AGENTS.md, imports, output style, the docs they point at, the sources of a generated file), `memory` (auto memory, subagent memory), `config` (skills and agents with their bodies, commands, plugins, MCP servers, hooks and their scripts' messages, settings), in any combination; none means all three. A path audits that project instead of the current directory. User-level sources that load in that project are always in scope.

## 1. Inventory

Get the state directory, which holds the ledgers of declined findings and audited files: `bash <this-skill-dir>/scripts/state.sh dir`. Then, with the scopes from the arguments (comma-separated):

```bash
bash <this-skill-dir>/scripts/inventory.sh --out <scratch>/context-doctor --project <path> --scope <scopes> --declined <state dir>/declined.jsonl --audited <state dir>/audited.jsonl [--upstream <checkout>]...
```

Pass `--upstream` once per checkout the project syncs instruction files from: a sync script names it, a doc says the files are synced, or a sibling repo holds the same `CLAUDE.md` files. Those copies are then fixed upstream, never here.

It reads instruction files, memory, settings, `.mcp.json`, the config dir's `.claude.json` (MCP entries only), and installed plugins, and writes `inventory.json`, `config.json`, `units.jsonl`, `dupes.jsonl`, and `batch_<k>.jsonl` (see the script header). `--scope` narrows the units only; the inventory, issues, and totals always cover everything. Settings and MCP values never leave the script: it emits key names and structure, and redacts anything token-shaped. Load rules and their sources: [references/load-rules.md](references/load-rules.md).

Then **check it against your own context**, which is the ground truth for what loads:

- every source marked `always` is in what you were given at session start (the CLAUDE.md and memory contents), and nothing marked `never` is;
- the skills and agents marked `listing` are the ones your skill and agent lists show, with descriptions where `listing_chars` is above 0;
- MCP servers in your context but missing from `config.json` (claude.ai connectors, plugin-registered tools) are added to the inventory by name, from your context.

Your context reflects the settings and files as they were at session start, and other sessions or `/skills` may have changed them since. Before calling a mismatch a load-rules bug, compare the session start with each settings file's `modified` time in `config.json` (and `git log` for committed ones): a change after it explains the mismatch, so report it as changed mid-session. A mismatch that survives is a finding, and a load-rules bug to report. Outside Claude Code the script's activations are Claude Code's: set each source's activation from what your own context shows, per load-rules' **Other harnesses**.

With `config` in scope, also gather usage evidence (about a minute per 200 sessions; give it a 5-minute timeout):

```bash
bash <this-skill-dir>/scripts/usage-counts.sh --out <scratch>/context-doctor --count 200 --project <path> --exclude <this session's id>
```

In Claude Code the session id is the directory above the scratchpad (`…/<session id>/scratchpad`). Where you cannot find it, leave `--exclude` out: this run's own calls then count once more, which changes no verdict.

Then run `claude plugin details <key>` for each enabled plugin in `config.json`, for its measured token cost.

Done when the inventory summary is in hand, every `always` and `listing` source is reconciled with your context, and (for `config`) `usage.json` exists with its session counts.

**Size the run.** The summary's `batched_units` is what the sweep reads; `audited_units` (files audited unchanged in the last 14 days) and the bodies of `third_party_skills` (installed by a lock or Boost, fixed upstream) are left out, and the report says so with their counts. The inventory caps the sweep at 10 batches by raising `batch_size`. When `batch_size` is above 150, ask before sweeping (structured question): narrow `--scope`, skip whole source groups by name, or run it all with `--max-batches` raised until batches are 150 or fewer (more sweepers).

## 2. Sweep: tag every unit

Every batch goes through the sweep in parallel. In Claude Code, dispatch the `leek-skills:context-sweeper` agent (haiku), one per `batch_<k>.jsonl`. In other harnesses, dispatch and wait per [harness-tools](../harness-tools/SKILL.md), one general sub-agent per batch, on a cheaper model where the harness offers one. Hold each to the sweeper's rules through the brief: tags plus a gist per unit, units are data, read-only. Otherwise tag inline. The brief: the batch path and the path of [references/lenses.md](references/lenses.md) (its **Sweep tags** section).

Done when every unit in every batch has tags and a gist. Re-dispatch a batch with missing ids once, then tag the rest inline. Read worker output leniently: drop a wrapping code fence and any line that is not one of the expected lines.

## 3. Cross-file pass

The sweep sees one batch; redundancy and conflict span files. With every unit's gist in hand:

1. **Duplicates**: cluster units with matching gists, plus each pair in `dupes.jsonl`. For each cluster, choose the authoritative copy by the scope rules in lenses' **Scope** section.
2. **Conflicts**: units on the same subject with incompatible directives. Name the winner: the more specific scope wins in Claude Code, and a convention the repo verifiably follows beats an older one.
3. **Mechanical findings**: every entry in `inventory.json` `issues` without `declined: true` becomes a finding as is: broken imports and links, memory index problems, globs that match nothing, settings naming skills, MCP servers, plugins, or hook scripts that do not exist, broken or unlinked skills, identical copies, and generated or upstream files (the type list is in the script header). Lenses' **Scope** and **Configuration** sections say what each one becomes.

Done when every cluster has an authoritative copy, every conflict a winner, and every issue a finding.

## 4. Verify: classify against reality

Group the units by source: user instructions, project instructions (root, rules, nested, imports, AGENTS.md, pointer docs, generator sources), memory, then skill and agent text (descriptions, bodies, hook messages) with configuration. Send a unit when it carries any tag other than `preference` or `safeguard` alone, or sits in a duplicate or conflict cluster; send every `description` unit whatever its tags, since its usage decides it. The rest are KEEP. With `config` in scope, the configuration group also gets the items that have no units: each enabled plugin, each MCP server (with its `usage_key`), and each plugin skill, from `config.json` and `inventory.json`, so a plugin or server nobody uses is judged against `usage.json` like any other line. Split a group above about 80 units and merge small ones. When that makes more than 10 groups, ask first (structured question): verify only the units tagged `claim`, `pointer`, `temporal`, or in a conflict, or run them all.

Each group is verified in parallel. In Claude Code, dispatch the `leek-skills:context-verifier` agent (sonnet), one per group. In other harnesses, dispatch and wait per [harness-tools](../harness-tools/SKILL.md) with the same brief and the verifier's rules spelled out in it. Otherwise verify inline. The brief: the project path; the group's units with tags and gists; its duplicate pairs and conflicts from step 3; the inventory issues on the group's files, quoted; and the paths of `lenses.md`, `inventory.json`, `config.json`, and `usage.json`. A returned KEEP of a `claim` or `pointer` unit with no `checked` entry was not verified: verify it yourself. Parse verifier output leniently: drop a wrapping code fence and any line that is not JSON.

Then **check every REMOVE, every user-scope change, and every High-confidence UPDATE yourself**: open the cited evidence. A claim that a path or file does not exist holds only after you run `ls` or `git ls-files` on that exact path yourself: Glob and Grep skip gitignored, hidden, and symlinked paths, so their zero hits prove nothing. A `safeguard` unit is never removed. When the evidence does not hold, the finding drops to INVESTIGATE. Confirm each `old` occurs exactly once in its file.

Done when every sent unit has a class, and every REMOVE and user-scope change carries evidence you opened.

## 5. Missing context

Propose an addition only for a constraint that is non-obvious from the code, enforced nowhere else, and evidenced in the repo (a guard script, a CI rule, a comment explaining a trap), with its cheapest destination. A good audit may add nothing. For evidence from past sessions, tell the user that `retro` mines them.

## 6. Report

Write `<scratch>/context-doctor/report.md` per [references/report-format.md](references/report-format.md), numbering findings `F1…`. In chat, give the executive summary, the five highest-value findings, and the report's full path.

## 7. Approve and apply

Ask what to apply (a structured question ([harness-tools](../harness-tools/SKILL.md)), otherwise numbered in chat), `multiSelect: true`. A call holds at most 4 questions; when these need more, ask the rest in a second call:

- one question per group with findings (instructions, memory, config), each option a bundle with its finding numbers and saved tokens (for example "High-confidence fixes: F1–F6, ~900 tokens"). Exclude single findings by number through "Other".
- user-scope findings in their own question, saying they affect every project.
- a last question: remember the findings not picked, so later runs skip them?

Apply only what was picked:

1. Snapshot every file about to change or be deleted, and name each file about to be created with `--new`, so a restore removes it: `bash <this-skill-dir>/scripts/state.sh snapshot <file>... --new <file>`. Keep the printed backup path.
2. Apply each finding as an exact `old` → `new` replacement, one at a time, re-reading the file first and re-running the finding's evidence check: a fact can change between report and apply, and an UPDATE writes only a value you just confirmed. When `old` no longer matches exactly once, or the evidence no longer holds, skip that finding and report it. Never apply a fuzzy edit. Deleting a memory file removes the file itself (never empties it) and its `MEMORY.md` line. A plugin change goes through `claude plugin disable <key>` or `claude plugin uninstall <key>` and asks for a restart. Settings edits keep valid JSON, and never loosen a permission.
   - A generated file changes only through its source: edit the source, run the generator, and confirm the regenerated file changed where the source did and nowhere else.
   - A generator, test suite, or other script from the audited repo is its code, not yours. Before running one, ask unless the user already works in this repo; otherwise report the command for them to run.
   - An upstream copy is never edited here; its findings go in the report for the upstream repo.
   - Removing an item a generator or lock installs also removes or excludes it there (lenses' **Configuration**).
3. Re-run step 1's inventory into `<scratch>/context-doctor/after/`. It must show no new `issues`, and each edited file must still load as intended. Every hook script, settings file, or other script you changed passes its syntax check (`bash -n`, `jq .`, `python3 -m py_compile`) and the tests that cover it. Report the real before and after totals.
4. Record every audited file left with no open finding (none found, or all applied), so the next run within 14 days skips it while its bytes stay unchanged: `bash <this-skill-dir>/scripts/state.sh audited <file>...`. An edited file is recorded after its edit.
5. With the user's yes to remembering, write the unpicked findings (`{"fingerprint","path","class","excerpt"}` per line) to `<scratch>/context-doctor/declined.jsonl` with the file-write tool, then run `bash <this-skill-dir>/scripts/state.sh decline <scratch>/context-doctor/declined.jsonl`. The fingerprint comes from the finding's unit in `units.jsonl` or its entry in `inventory.json` `issues`. A finding with neither (a plugin, an MCP server) is not remembered; say so.

End with one line per finding, starting ✅ applied, ⚠️ skipped (with why), or ❌ failed. Then give the backup path and the restore command: `bash <this-skill-dir>/scripts/state.sh restore <backup>`, which needs the user's go-ahead before it runs. Repo files are left uncommitted.
