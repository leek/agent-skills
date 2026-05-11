# Herd CLI Reference (worktree-relevant subset)

Full docs: https://herd.laravel.com/docs

## Site routing

| Command | Purpose |
|---|---|
| `herd park` | Park the current directory. Every immediate subdir resolves as `<name>.test`. |
| `herd parked` | List parked directories. |
| `herd forget` | Unpark current directory. |
| `herd link [name]` | Serve current directory as `<name>.test` (or dir name if omitted). Use when you don't want to park the parent. |
| `herd unlink [name]` | Remove a manual link. |
| `herd links` | List manual links. |
| `herd open` | Open current site's `.test` URL. |

For worktrees: **prefer `herd park` on the parent** — zero per-worktree work. Use `herd link` only if siblings include non-Laravel projects you don't want exposed.

## PHP version per site

| Command | Purpose |
|---|---|
| `herd use php@8.3` | Set global default PHP. |
| `herd isolate php@8.1` | Override PHP version for the current site only. Persists across `herd restart`. |
| `herd unisolate` | Remove the per-site override. |
| `herd isolated` | List all per-site overrides. |
| `herd which-php` | Show which PHP binary Herd resolves for the current dir. |

Use case: a legacy worktree on PHP 8.1 alongside a `main` worktree on 8.3.

## Services (Pro)

`herd services` lists managed MySQL/Postgres/Redis/Meilisearch instances. They listen on standard ports, so all worktrees share one server — isolation comes from per-worktree DB names and Redis prefixes, not separate servers.

## Secure (HTTPS)

| Command | Purpose |
|---|---|
| `herd secure` | Generate a trusted cert for current site → `https://<name>.test`. |
| `herd unsecure` | Revert to HTTP. |

If you secure one worktree, secure them all (or none) — mixed HTTP/HTTPS confuses cookies on the shared `.test` parent domain.

## Other useful commands

| Command | Purpose |
|---|---|
| `herd restart` | Restart Herd's PHP/Nginx/dnsmasq. Run after editing `~/.config/herd/...` config. |
| `herd log` | Tail Nginx/PHP-FPM logs. |
| `herd debug` | Toggle Xdebug for current site's PHP. |
| `herd tinker` | Open Tinker bound to current site's PHP version. |

## Troubleshooting `*.test` not resolving

1. `herd parked` — confirm parent is in the list.
2. `dscacheutil -flushcache && sudo killall -HUP mDNSResponder` — flush macOS DNS.
3. Directory name must be lowercase, no spaces, no dots beyond what becomes the subdomain.
4. `herd restart` if you just upgraded Herd.
