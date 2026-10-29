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
3. With `clone` or `empty`, read `database_mode` and `database_name` from the `--json` output: Herd falls back to `shared` with only a note when it cannot create the database, so say so when it did. Register a created server database the way every worktree skill does, so `repository-cleanup` sees it: `printf '%s\t%s\t%s\t%s\n' "$(date +%s)" <pgsql|mysql> <database_name> "<worktree path>" >> "$(git rev-parse --path-format=absolute --git-common-dir)/scratch-databases"`. With `empty`, run `php artisan migrate` once the bootstrap's step 2 has installed `vendor/`: Herd's own migration runs before that and only warns when `vendor/` was missing.
4. Give the user the `url` and the database.

Remove it with [Remove a served worktree](#remove-a-served-worktree).

## Bootstrap a bare worktree

A worktree made with plain `git worktree add` (the PR, issue, and CI recipes in other skills, at `.claude/worktrees/<name>`) starts bare; so does one the harness made (`claude --worktree`, a subagent with `isolation: worktree`). With the leek-skills plugin in Claude Code, a session that opens in such a worktree is told so at start; elsewhere, check for `vendor/` yourself before running anything. Make it runnable from inside the worktree, with `main` set to the main checkout (`git worktree list --porcelain | sed -n '1s/^worktree //p'`):

1. **Serve it.** `herd workspace --database=shared --json`. Keep the `url` it prints: that is the worktree's address for `verify`. `shared` leaves `DB_DATABASE` naming the main checkout's database (for SQLite, Herd points it at the main checkout's file), so the calling skill's own database (step 3) is the only one created, and the only one its cleanup tracks; run no migration or seeder before step 3. When `herd` is missing or the command fails, copy `.env` from `$main` yourself and go on: the worktree has no URL, but artisan and tests run.
2. **Dependencies and assets.** `composer install`, so `vendor/` matches this branch's lock (Herd cloned the main checkout's only when the lockfiles were equal). Do the same for `node_modules` when the run builds assets. When Composer hooks require generated assets that do not exist yet (such as `@php artisan filament:assets` needing an editor bundle from `npm run build`), run `composer install --no-scripts`, build the assets, then run `composer install`. Run `php artisan storage:link` when the main checkout has `public/storage` (Herd repoints that link only in its own clones). Each tree owns a real `vendor/`: Composer's autoloader resolves `app/` and `tests/` relative to it, so a symlinked `vendor/` makes Pest run the main checkout's code.
3. **Test environment and database.** Copy `.env.testing` from `$main` when it exists there and not here. When the calling skill gives the run its own database, set `DB_DATABASE` to that name in `.env` and `.env.testing` before any migration or test. When `.env` puts the cache, queue, or sessions on Redis and the project's `herd.yml` sets no prefixes, set `CACHE_PREFIX` and `REDIS_PREFIX` to values unique to this worktree, so parallel worktrees keep their keys apart.
4. **Proof.** `git rev-parse HEAD` equals the commit the run means to test, and `test ! -L vendor` passes. Run nothing until both hold.

## Remove a served worktree

Run every step from the main checkout, in order, so nothing is dropped while git might still keep the worktree:

1. **Clean check.** `git -C <path> status --porcelain` prints nothing. When it prints anything, `git worktree remove` would refuse: stop, and the worktree and its database stay (the calling skill's rule for a refused removal applies).
2. **Unserve.** When `<path>/.herd-workspace.json` exists, `herd workspace:delete <site> --force --keep-files`, with `<site>` the file's `site` field (`jq -r .site <path>/.herd-workspace.json`), its host, which unlike the branch name is unique across Herd sites. Herd's `--force` only skips its confirmation prompt; it is not git's `--force`. `--keep-files` leaves the checkout for step 3, since without it Herd runs `git worktree remove --force`. Herd unlinks the host, removes its certificate and PHP pin, and drops a database it created (`clone` or `empty`).
3. **Remove.** `git worktree remove <path>`, never with `--force`. When git still refuses, the worktree stays for the user; visiting its URL serves it again.
4. **Registry.** Delete the `scratch-databases` line of a database Herd dropped in step 2.

When step 2 fails because the Herd app is not running: when the file's `database_mode` is `clone` or `empty` on a server driver, drop its `database_name` with the repo's client (`DROP DATABASE IF EXISTS`; a SQLite file goes with the checkout), then do steps 3 and 4, then `herd workspaces --all >/dev/null`, which drops the link, certificate and PHP pin of any workspace whose checkout is gone.

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
