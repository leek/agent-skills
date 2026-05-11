# Per-Worktree Isolation: Why & How

Worktrees share the `.git` object store but have independent working trees. Anything **outside the working tree** (caches, OS-level state, server-side data) needs explicit isolation or branches will silently corrupt each other's state.

## `vendor/` and `node_modules/`

**Rule:** never symlink these between worktrees.

Why:
- `composer.lock` and `package-lock.json` differ by branch. Shared `vendor/` means one branch's autoload class map points at code that doesn't exist on disk for the other branch.
- Node native modules (`sharp`, `bcrypt`, `better-sqlite3`) bind to specific Node versions and platforms. Mixed versions across worktrees → `Error: NODE_MODULE_VERSION mismatch`.
- Composer post-install scripts patch files in `vendor/` differently per project state.

Fast install instead:
- Composer cache is global (`~/Library/Caches/composer`). Subsequent installs are mostly hardlinks. A typical Laravel install on a warm cache is < 10 s.
- `pnpm` uses a global content-addressable store — installs are symlinks into that store, ~3 s for a typical Laravel + Inertia app.
- `npm ci` with a warm npm cache is faster than `npm install`. Use it in scripts.

## `.env`

`.env` is gitignored, so a fresh worktree has none. The skill's `worktree-new.sh` copies `.env` from the main checkout, then **rewrites**:

| Key | Per-worktree value | Reason |
|---|---|---|
| `APP_URL` | `http://<app>-<suffix>.test` | Generated links and signed routes embed this. |
| `DB_DATABASE` | per-worktree DB or sqlite file | Shared DB → migrations from one branch break others. |
| `SESSION_COOKIE` | unique name | Cookies on `.test` parent domain leak otherwise. |
| `CACHE_PREFIX` | unique | File/Redis cache key collisions. |
| `REDIS_PREFIX` | unique | Same Redis DB across worktrees → cache pollution. |

You can also bump `REDIS_DB` to a different integer index instead of using a prefix.

## `APP_KEY`

Two worktrees with the same `APP_KEY` will decrypt each other's session cookies on the shared `.test` parent. This sounds harmless until two branches set incompatible session payload shapes — then logging into one logs you out of the other and throws `DecryptException` on the way.

Run `php artisan key:generate` after copying `.env`. The skill's script does this.

## `storage/` and `bootstrap/cache/`

Both contain runtime artifacts: compiled views, route/config caches, logs, session files. Always per-worktree, always regenerated:

```bash
php artisan optimize:clear
```

## `public/storage` symlink

`php artisan storage:link` creates a symlink from `public/storage` → `storage/app/public`. The link is **inside the worktree** and points to a path inside the same worktree, so it's already isolated — but it must be re-created in each new worktree if your app uses public storage. The skill's script does this when `storage/app` exists.

## Database

See [db-strategies.md](./db-strategies.md) for the full decision tree. Summary:

- **SQLite**: simplest. Per-worktree file at `database/database.sqlite`. Migrate from scratch.
- **MySQL/Postgres via Herd Pro**: one server, per-worktree DB name `<app>_<suffix>`. Migrate from scratch, or `mysqldump` the main DB and restore.

## Redis / Horizon / queues

- Use unique `REDIS_PREFIX` so cache keys don't collide.
- Horizon supervisors keyed by `HORIZON_PREFIX` — set unique per worktree if running multiple Horizons.
- Don't run Horizon in two worktrees against the same queue connection — they'll fight over jobs.

## Mail / Telescope

- `MAIL_FROM_ADDRESS` can stay shared; mailpit/log driver doesn't care.
- Telescope writes to the main DB connection — handled by per-worktree DB isolation.
