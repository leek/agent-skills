# Per-Worktree Isolation

Worktrees share the `.git` object store but nothing outside the working tree. `herd workspace` isolates the URL, PHP version, dependencies and (with `--database=clone|empty`) the database. The rest is the project's to configure.

## What `herd.yml` can add

A committed `herd.yml` (overridden by an uncommitted `herd.local.yml`) sets defaults for every workspace of the project:

```yaml
workspaces:
  database: empty                 # default mode when --database is not passed
  copy: [.env.testing]            # extra gitignored paths to copy from the main checkout
  env:                            # written into the workspace .env
    CACHE_PREFIX: "{{branch}}_cache_"
    REDIS_PREFIX: "{{branch}}_database_"
    SESSION_COOKIE: "{{branch}}_session"
  hooks:
    after_create: composer install   # runs inside the workspace; a failing line only warns
    before_delete: ...
```

Placeholders: `{{domain}}`, `{{scheme}}`, `{{branch}}`, `{{parent}}`, `{{parent_domain}}`, `{{database}}`.

## Shared state that still collides

- **Redis**: worktrees on one Redis database share keys unless `CACHE_PREFIX` / `REDIS_PREFIX` (or `REDIS_DB`) differ. Two Horizons on the same queue connection fight over jobs; run one, or give each its own `HORIZON_PREFIX`.
- **`APP_KEY`**: the copied `.env` keeps the main checkout's key. Run `php artisan key:generate` in the worktree only when it must not read the main checkout's encrypted data; data it shares (a `shared` or `clone` database) needs the same key.
- **`vendor/` and `node_modules/`**: never symlink them between worktrees. The autoloader resolves `app/` relative to `vendor/`, and native Node modules bind to one Node version.

## Database

- **`shared`**: migrations in the worktree change the main checkout's schema. Fine for read-only verification; anything that migrates or seeds needs its own database.
- **`clone`**: a copy of the main database (`mysqldump` / `pg_dump` when Herd has them, a SQL copy otherwise; SQLite copies the file).
- **`empty`**: a fresh database, migrated unless `--no-migrate`.
- **Tests** read `.env.testing` and `phpunit.xml`, which Herd never rewrites: an in-memory SQLite test database needs nothing; a server one needs its own name per worktree.

A worktree whose branch drops or renames a migration leaves its database ahead of the code: `php artisan migrate:status` shows the orphan. `migrate:fresh` rebuilds it and destroys its data.
