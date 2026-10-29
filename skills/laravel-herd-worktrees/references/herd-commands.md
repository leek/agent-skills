# Herd CLI Reference (worktree-relevant subset)

Verified against Herd 2.0.3. `herd help <command>` has every flag.

## Workspaces

| Command | Purpose |
|---|---|
| `herd workspace [name]` | Inside a git worktree: serve it as a workspace of the main checkout's site (`name` is ignored; the branch names it). In the main checkout: make a copy-on-write clone on a new branch. |
| `herd workspace --database=shared\|clone\|empty` | Database mode. `shared` (default) keeps the main database; `clone` copies it; `empty` creates one and runs `migrate` (skip with `--no-migrate`). |
| `herd workspace --secure` / `--no-secure` | Override the HTTPS setting inherited from the main site. |
| `herd workspace --json` | Print the workspace record (`url`, `path`, `branch`, `database_name`, ...). |
| `herd workspaces [--all] [--json]` | List this site's workspaces and the git worktrees not served yet. Also forgets workspaces whose checkout is gone. |
| `herd workspace:delete [name] --force --keep-files` | Stop serving it without a prompt, keep the checkout for `git worktree remove`. Drops a `clone`/`empty` database unless `--keep-database`. Needs the Herd app running. |
| `herd workspace:open [name]` | Open it in the browser. |
| `herd workspace:merge [name]` | Merge its branch into the main checkout's base branch (`--push`, `--delete`). |

A git worktree not served yet is also served (with the `shared` database) the first time its URL, `<branch>.<site>.test`, is visited.

## Site and database

| Command | Purpose |
|---|---|
| `herd site:info` | URL, PHP and Node versions, what `.env` points at, and the site's workspaces. |
| `herd db:connection` | The database this checkout's `.env` reaches, as a connection URL. |
| `herd db:create [name]` | Create a database on the server `.env` points at (for SQLite, the file). |

## PHP version per site

| Command | Purpose |
|---|---|
| `herd isolate php@8.1` | Pin the current site's PHP version. A workspace inherits the main site's pin. |
| `herd unisolate` | Remove the pin. |
| `herd isolated` | List all pins. |
| `herd which-php` | The PHP binary Herd resolves for the current directory. |

## Troubleshooting a `.test` URL

1. `herd workspaces --json`: the worktree is listed with `"served": true` and the URL you are loading.
2. `herd site:info` inside the worktree: the PHP version and database are the ones you expect.
3. `php artisan route:list` works inside the worktree.
4. `dscacheutil -flushcache && sudo killall -HUP mDNSResponder` flushes macOS DNS; `herd restart` after a Herd upgrade.
