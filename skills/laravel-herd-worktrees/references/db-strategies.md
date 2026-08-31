# Database Strategies for Laravel + Herd Worktrees

The right strategy depends on (a) DB driver, (b) whether you need production-like data, and (c) how often you create worktrees.

## Decision tree

```
Need realistic data volume?
├─ No  → SQLite per worktree, fresh migrate + seed
└─ Yes → MySQL/Postgres per worktree DB
         Need an exact snapshot of dev DB?
         ├─ No  → migrate + seeders
         └─ Yes → dump from main DB, restore into per-worktree DB
```

## SQLite (recommended default)

Pros: zero server-side state, file lives inside the worktree, removed automatically with `git worktree remove`.

Cons: not production-realistic. Some MySQL-only features (`JSON_TABLE`, fulltext) won't run. Avoid if you're testing migrations that are MySQL-specific.

Setup is what `worktree-new.sh --driver sqlite` already does:

```
DB_CONNECTION=sqlite
DB_DATABASE=/abs/path/to/worktree/database/database.sqlite
```

## MySQL (Herd Pro)

One MySQL server, many DBs. Naming: `<app_name>_<suffix>` with hyphens converted to underscores.

```bash
mysql -uroot -e "CREATE DATABASE \`myapp_feat_billing\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
```

Set in `.env`:

```
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=myapp_feat_billing
DB_USERNAME=root
DB_PASSWORD=
```

Then `php artisan migrate --seed` (or migrate then a custom seeder).

### Snapshot from main DB

When you want the new worktree to start with the current dev data:

```bash
mysqldump -uroot myapp_main > /tmp/snap.sql
mysql -uroot -e "CREATE DATABASE myapp_feat_billing"
mysql -uroot myapp_feat_billing < /tmp/snap.sql
```

Skip `--routines --triggers` unless you actually use them: keeps the dump small.

### Schema-only sync

If you just want the latest schema without data:

```bash
mysqldump -uroot --no-data myapp_main > /tmp/schema.sql
mysql -uroot myapp_feat_billing < /tmp/schema.sql
```

## Postgres (Herd Pro)

Same idea:

```bash
createdb myapp_feat_billing
pg_dump myapp_main | psql myapp_feat_billing      # copy
pg_dump --schema-only myapp_main | psql myapp_feat_billing  # schema only
```

## Cleanup

`worktree-rm.sh --drop-db` handles the drop. Without `--drop-db`, the per-worktree DB lingers: useful if you're going to recreate the same branch later, wasteful otherwise.

## Migrations between branches

If branch A adds migration `2025_01_01_create_invoices_table.php` and branch B doesn't have it:

- Branch A's DB has the `invoices` table and a row in `migrations`.
- Switching to branch B in the **same worktree** would leave the table behind and the migration row pointing at a file that no longer exists. `php artisan migrate:status` shows it as missing.
- This is exactly why each worktree gets its own DB. You won't see this problem if you stay in your worktree's branch.

If you do need to rebase a worktree onto a base branch with new migrations:

```bash
php artisan migrate    # apply the new ones
```

If a migration was renamed/squashed upstream:

```bash
php artisan migrate:fresh --seed   # nuke and rebuild (destructive)
```

## Testing-only DB

Tests typically use an in-memory SQLite via `phpunit.xml`:

```xml
<server name="DB_CONNECTION" value="sqlite"/>
<server name="DB_DATABASE" value=":memory:"/>
```

This is independent of the dev DB, so it works the same in any worktree without changes.
