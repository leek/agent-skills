# Implement in Laravel

What the [SKILL.md](../SKILL.md) steps mean in a Laravel app.

- **Destructive database commands**: `migrate:fresh`, `migrate:rollback`, `migrate:reset`, `db:wipe`. Never run one without explicit approval.
- **Identifiers to verify**: route names (`php artisan route:list`), config keys, enum cases, Blade/Filament icon names.
- **Formatter (step 4)**: `vendor/bin/pint <paths>` when the project uses Pint.
- **Full-suite fallback (step 6)**: `php artisan test`, only when the repo documents no other command.
- **Worktree setup (PR delivery)**: a worktree served by Laravel Herd is made runnable with `laravel-herd-worktrees`' **Bootstrap a bare worktree** section.
