---
name: setup
description: Configure this repo for the engineering skills — issue tracker, triage label vocabulary, and domain doc layout. Run once before first use of the other skills.
disable-model-invocation: true
---

# Setup

Scaffold the per-repo configuration that the engineering skills assume:

- **Issue tracker** — where issues live (**local markdown by default**; GitHub and Linear also supported)
- **Triage labels** — the strings used for the five canonical triage roles
- **Domain docs** — where `CONTEXT.md` and ADRs live, and the consumer rules for reading them

This is a prompt-driven skill, not a deterministic script. Explore, present what you found, confirm with the user, then write.

## Process

### 1. Explore

Read whatever exists; don't assume:

- `git remote -v` — is there a GitHub remote?
- Are Linear MCP tools available, and does the user track this project in Linear?
- `AGENTS.md` / `CLAUDE.md` at the repo root — does an `## Agent skills` section already exist?
- `CONTEXT.md` at the repo root, `docs/adr/`
- `docs/agents/` — does this skill's prior output already exist?
- `.scratch/` — sign that the local-markdown convention is already in use
- Is the `triage` skill installed? This decides whether Section B runs at all.

### 2. Present findings and ask

Summarise what's present and missing, then take the sections in order — one section, one answer. Lead each with the recommended answer so the user can accept it in a word. Use `AskUserQuestion` where available; otherwise ask in chat and wait.

**Section A — Issue tracker.** Recommend **local markdown** (`.scratch/`) as the default — it works in every repo, needs no auth, and keeps specs and tickets greppable next to the code. Offer GitHub (only when a GitHub remote exists) and Linear (only when its MCP tools are available) as alternatives; for anything else, have the user describe the workflow in a paragraph and record it as freeform prose.

Record the choice in `docs/agents/issue-tracker.md`, seeded from the matching template in this skill's folder.

**Section B — Triage label vocabulary.** Skip entirely if the `triage` skill isn't installed. If it is, ask exactly one question: keep the default labels? (recommended: **yes**). Defaults: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. Collect overrides only on "no".

**Section C — Domain docs.** Default to **single-context** — one `CONTEXT.md` + `docs/adr/` at the repo root. Write it without asking. Offer multi-context (a root `CONTEXT-MAP.md` pointing at per-module `CONTEXT.md` files) only when exploration found real module boundaries (`app-modules/`, `modules/`, a monorepo layout).

### 3. Confirm and write

Show a draft of the `## Agent skills` block and each `docs/agents/*.md` file; let the user edit before writing.

Edit `CLAUDE.md` if it exists, else `AGENTS.md`; if neither exists, ask which to create. If an `## Agent skills` block already exists, update it in place — never append a duplicate.

```markdown
## Agent skills

### Issue tracker

[one-line summary]. See `docs/agents/issue-tracker.md`.

### Triage labels

[one-line summary]. See `docs/agents/triage-labels.md`.

### Domain docs

[one-line summary — "single-context" or "multi-context"]. See `docs/agents/domain.md`.
```

Omit the `### Triage labels` sub-block (and its file) when Section B didn't run.

Seed templates in this folder:

- [issue-tracker-local.md](./issue-tracker-local.md) — local markdown (the default)
- [issue-tracker-github.md](./issue-tracker-github.md) — GitHub via `gh`
- [issue-tracker-linear.md](./issue-tracker-linear.md) — Linear via MCP tools
- [triage-labels.md](./triage-labels.md) — label mapping (only if `triage` is installed)
- [domain.md](./domain.md) — domain doc consumer rules + layout

### 4. Done

Tell the user setup is complete and which skills now read these files (`wayfinder`, `to-spec`, `to-tickets`, `implement`, `code-review`, `triage`). They can edit `docs/agents/*.md` directly later — re-running this skill is only needed to switch trackers or restart.
