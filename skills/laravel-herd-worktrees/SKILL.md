---
name: laravel-herd-worktrees
description: Create, serve, or remove git worktrees for Laravel projects served by Laravel Herd on macOS. Use when the user needs a branch worktree, a .test URL for one, or per-worktree database isolation.
compatibility: "macOS with Laravel Herd 2.0+ (the `herd workspace` command)"
---

# Laravel Herd + Git Worktrees

Run several branches of a Laravel project side by side, each a git worktree that Herd serves at its own `*.test` URL. `herd workspace` run inside a worktree does the setup; this skill owns the recipe around it.

## Mental Model

- A **worktree** has its own `HEAD`, and none of the main checkout's untracked state: no `vendor/`, `node_modules/`, `.env`, or built assets.
- **`herd workspace` inside a git worktree** serves that checkout as a workspace of the main checkout's site, at `<branch>.<site>.test` (a detached worktree is named after its commit). It copies `.env`; clones `vendor/` and `node_modules/` from the main checkout (each only while its lockfile matches) and `public/build`; links the host with the main site's HTTPS and PHP version; rewrites `APP_URL`, `SESSION_DOMAIN` and `SANCTUM_STATEFUL_DOMAINS`; clears the config and route caches. Run in the main checkout instead, it makes a copy-on-write clone outside git's worktree list, which no recipe here uses.
- **Database**: `--database=shared` (the default) keeps the main checkout's database; `clone` and `empty` create `<main db>_<branch>` on the same server (`empty` also migrates), which `herd workspace:delete` drops again.
- What Herd leaves alone: `composer install` when the lockfile differs, `storage:link`, `.env.testing`, `APP_KEY`, cache and Redis prefixes. A project can cover the last three in a committed `herd.yml`: see [references/isolation.md](./references/isolation.md).

## Create a worktree for the user

1. `git worktree add -b <branch> .claude/worktrees/<name> <base>` (or the path the user names).
2. Make it runnable with [Bootstrap a bare worktree](#bootstrap-a-bare-worktree), passing `--database=empty` (a fresh migrated database) or `--database=clone` (a copy of the main one) instead of `shared` when the user wants the worktree's data kept apart.
3. With `clone` or `empty`, read `database_mode` and `database_name` from the `--json` output: Herd falls back to `shared` with only a note when it cannot create the database, so say so when it did. Register a created server database per [Scratch database registry](#scratch-database-registry), so `repository-cleanup` sees it. With `empty`, run `php artisan migrate` once the bootstrap's step 2 has installed `vendor/`: Herd's own migration runs before that and only warns when `vendor/` was missing.
4. Give the user the `url` and the database.

Remove it with [Remove a served worktree](#remove-a-served-worktree).

## Bootstrap a bare worktree

A worktree made with plain `git worktree add` (the PR, issue, and CI recipes in other skills, at `.claude/worktrees/<name>`) starts bare; so does one the harness made (`claude --worktree`, a subagent with `isolation: worktree`). With the leek-skills plugin in Claude Code, a session that opens in such a worktree is told so at start; elsewhere, check for `vendor/` yourself before running anything. Make it runnable from inside the worktree, with `main` set to the main checkout (`git worktree list --porcelain | sed -n '1s/^worktree //p'`):

1. **Serve it.** `herd workspace --database=shared --json`. Keep the `url` it prints: that is the worktree's address for `verify`. `shared` leaves `DB_DATABASE` naming the main checkout's database (for SQLite, Herd points it at the main checkout's file), so the calling skill's own database (step 3) is the only one created, and the only one its cleanup tracks; run no migration or seeder before step 3. When `herd` is missing or the command fails, copy `.env` from `$main` yourself and go on: the worktree has no URL, but artisan and tests run.
2. **Dependencies and assets.** When the project's `herd.yml` declares `workspaces.hooks` or `workspaces.copy`, read the hook script first: it may already install dependencies on lockfile drift, copy built assets, and set up the test database, so do only what it leaves out, and use the project's own test-database tool when its docs name one. Otherwise `composer install`, so `vendor/` matches this branch's lock (Herd cloned the main checkout's only when the lockfiles were equal). Do the same for `node_modules` when the run builds assets. When Composer hooks require generated assets that do not exist yet (such as `@php artisan filament:assets` needing an editor bundle from `npm run build`), run `composer install --no-scripts`, build the assets, then run `composer install`. Run `php artisan storage:link` when the main checkout has `public/storage` (Herd repoints that link only in its own clones). Each tree owns a real `vendor/`: Composer's autoloader resolves `app/` and `tests/` relative to it, so a symlinked `vendor/` makes Pest run the main checkout's code.
3. **Test environment and database.** Copy `.env.testing` from `$main` when it exists there and not here. When the calling skill gives the run its own database, set `DB_DATABASE` to that name in `.env` and `.env.testing` before any migration or test. When `.env` puts the cache, queue, or sessions on Redis and the project's `herd.yml` sets no prefixes, set `CACHE_PREFIX` and `REDIS_PREFIX` to values unique to this worktree, so parallel worktrees keep their keys apart.
4. **Proof.** `git rev-parse HEAD` equals the commit the run means to test, and `test ! -L vendor` passes. Run nothing until both hold.

## Remove a served worktree

From the main checkout (or, for `implement-spec`, the integration checkout `git branch -d` checks against), run [`scripts/remove-worktree.sh`](scripts/remove-worktree.sh) `<path>`, adding `--branch <name>` when the run's branch goes too. It works in the safe order and prints one JSON line:

1. **Clean check.** A worktree with any `git status --porcelain` output stays, with its branch and databases: `removed: false` and the reason. The calling skill's rule for a refused removal applies.
2. **Unserve.** When Herd's own `herd workspaces --all --json` serves this exact path, `herd workspace:delete --force --keep-files -- <site>` with that site (never a site read from the checkout, which a branch could plant) (Herd's `--force` only skips a prompt; `--keep-files` leaves the checkout for git). Herd drops a database it created (`clone` or `empty`), and the script unregisters it.
3. **Remove.** `git worktree remove <path>`, never with `--force`. When git refuses, everything stays; visiting its URL serves it again.
4. **Branch.** `git branch -d <name>` only after a removal; a refusal keeps the branch, named in `branch_reason`. Git's `-D` hint is not a go-ahead.

`databases` lists what is still registered for that path once it is removed (`[]` when kept, since a kept worktree keeps its databases): the calling skill's own databases. Wait for the script's JSON before dropping anything (if your harness backgrounds a slow command, read its output first): a drop issued earlier runs before git decides, and an unregister issued earlier empties the list. Drop each, and its parallel-testing copies (`<database>_test_<N>`), with the repo's client (`DROP DATABASE IF EXISTS`; a SQLite file goes with the checkout), then unregister each one only after its drop succeeded. A failed drop keeps its registry line and is reported.

When `herd_unserve_failed` is set (the Herd app is not running) and its `database_mode` is `clone` or `empty` on a server driver, drop its `database_name` yourself and unregister it.

**What is left.** A calling skill removes without asking what it created whose work has landed, and lists each removal. It asks once only about the rest it created (a worktree git refused, unmerged or queued work): a structured question ([harness-tools](../harness-tools/SKILL.md)) with `multiSelect: true`, one option per item naming its worktree, branch, and databases, nothing pre-ticked, at most 4 per question and further questions for the rest; otherwise one yes/no question in chat: "Can I delete these too?". It removes only what the answer selects, by the steps above; on no, nothing. It skips the question when nothing is left, and names everything kept in its report for `repository-cleanup`.

## Scratch database registry

Every skill that creates a worktree or a throwaway database registers each database in `<git-common-dir>/scratch-databases`, so `repository-cleanup` finds what a stopped run left behind. One script owns the file:

```bash
bash <this-skill-dir>/scripts/scratch-db.sh register <pgsql|mysql|sqlite> <database> <worktree path, or ->   # the moment it is created
bash <this-skill-dir>/scripts/scratch-db.sh unregister <database>                                           # only after a successful drop
bash <this-skill-dir>/scripts/scratch-db.sh list [<worktree path>]                                          # JSON
```

Name a scratch database so no checkout config uses it: never a name in the main checkout's `.env`, `.env.testing`, or `phpunit.xml`.

## Diagnostics

```bash
herd workspaces --json   # this site's workspaces and unserved worktrees, with URLs
herd site:info           # URL, PHP version, and what .env points at
herd db:connection       # the database this checkout's .env reaches
git worktree list
```

Command reference: [references/herd-commands.md](./references/herd-commands.md).

## Out of Scope

- **Valet**, **Linux**, **Docker / Sail**: this skill assumes Herd on macOS.
