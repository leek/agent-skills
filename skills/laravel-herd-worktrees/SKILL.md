---
name: laravel-herd-worktrees
description: Create, serve, or remove git worktrees for Laravel projects served by Laravel Herd on macOS. Use when the user needs a branch worktree, a .test URL for one, or per-worktree database isolation.
compatibility: "macOS with Laravel Herd 2.0+ (the `herd workspace` command)"
---

# Laravel Herd + Git Worktrees

Run several branches of a Laravel project side by side, each a git worktree that Herd serves at its own `*.test` URL. `herd workspace` run inside a worktree does the setup; this skill owns the recipe around it.

## Mental Model

- A **worktree** has its own `HEAD`, and none of the main checkout's untracked state: no `vendor/`, `node_modules/`, `.env`, or built assets.
- **`herd workspace` inside a git worktree** serves that checkout as a workspace of the main checkout's site, at `<branch>.<site>.test` (a detached worktree is named after its commit). It copies `.env`; clones `vendor/`, `node_modules/` and `public/build` from the main checkout (only while the lockfile matches); links the host with the main site's HTTPS and PHP version; rewrites `APP_URL`, `SESSION_DOMAIN` and `SANCTUM_STATEFUL_DOMAINS`; clears the config and route caches. Run in the main checkout instead, it makes a copy-on-write clone outside git's worktree list, which no recipe here uses.
- **Database**: `--database=shared` (the default) keeps the main checkout's database; `clone` and `empty` create `<main db>_<branch>` on the same server (`empty` also migrates), which `herd workspace:delete` drops again.
- What Herd leaves alone: `composer install` when the lockfile differs, `storage:link`, `.env.testing`, `APP_KEY`, cache and Redis prefixes. A project can cover the last three in a committed `herd.yml`: see [references/isolation.md](./references/isolation.md).

## Create a worktree for the user

1. `git worktree add -b <branch> .claude/worktrees/<name> <base>` (or the path the user names).
2. Make it runnable with [Bootstrap a bare worktree](#bootstrap-a-bare-worktree), passing `--database=empty` (a fresh migrated database) or `--database=clone` (a copy of the main one) instead of `shared` when the user wants the worktree's data kept apart.
3. Give the user the `url` and the database Herd reported.

Remove it with [Remove a served worktree](#remove-a-served-worktree).

## Bootstrap a bare worktree

A worktree made with plain `git worktree add` (the PR, issue, and CI recipes in other skills, at `.claude/worktrees/<name>`) starts bare; so does one the harness made (`claude --worktree`, a subagent with `isolation: worktree`). With the leek-skills plugin in Claude Code, a session that opens in such a worktree is told so at start; elsewhere, check for `vendor/` yourself before running anything. Make it runnable from inside the worktree, with `main` set to the main checkout (`git worktree list --porcelain | sed -n '1s/^worktree //p'`):

1. **Serve it.** `herd workspace --database=shared --json`. Keep the `url` it prints: that is the worktree's address for `verify`. `shared` leaves `DB_DATABASE` naming the main checkout's database (for SQLite, its file), so the calling skill's own database (step 3) is the only one created, and the only one its cleanup tracks.
2. **Dependencies and assets.** `composer install`, so `vendor/` matches this branch's lock (Herd cloned the main checkout's only when the lockfiles were equal). Do the same for `node_modules` when the run builds assets. When Composer hooks require generated assets that do not exist yet (such as `@php artisan filament:assets` needing an editor bundle from `npm run build`), run `composer install --no-scripts`, build the assets, then run `composer install`. Run `php artisan storage:link` when the main checkout has `public/storage` (Herd repoints that link only in its own clones). Each tree owns a real `vendor/`: Composer's autoloader resolves `app/` and `tests/` relative to it, so a symlinked `vendor/` makes Pest run the main checkout's code.
3. **Test environment and database.** Copy `.env.testing` from `$main` when it exists there and not here. When the calling skill gives the run its own database, set `DB_DATABASE` to that name in `.env` and `.env.testing` before any migration or test.
4. **Proof.** `git rev-parse HEAD` equals the commit the run means to test, and `test ! -L vendor` passes. Run nothing until both hold.

## Remove a served worktree

1. From inside the worktree: `herd workspace:delete --force --keep-files`. `--force` only skips Herd's confirmation; `--keep-files` leaves the checkout for git, since without it Herd runs `git worktree remove --force`. It unlinks the host, removes its certificate and PHP pin, and drops a database Herd created (`clone` or `empty`).
2. From the main checkout: `git worktree remove <path>`, never with `--force`. When git refuses, the worktree stays for the user; visiting its URL serves it again.

When step 1 fails because the Herd app is not running, do step 2, then `herd workspaces --all >/dev/null`: Herd drops the link, certificate and PHP pin of any workspace whose checkout is gone (but not a database it created).

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
