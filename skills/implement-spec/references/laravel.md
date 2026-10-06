# Implement Spec in Laravel

What the [SKILL.md](../SKILL.md) steps mean in a Laravel app. Pass this file's path into every implementer brief.

- **Destructive database commands**: `migrate:fresh`, `migrate:rollback`, `migrate:reset`, `db:wipe`. Never run one on a database this run did not create without explicit approval.
- **Worktree setup (step 2)**: a worktree served by Laravel Herd is made runnable with `laravel-herd-worktrees`' **Bootstrap a bare worktree** section.
- **Database names to avoid (step 2)**: any name the main checkout's `.env`, `.env.testing`, or `phpunit.xml` uses.
- **Formatter (implementer brief)**: `vendor/bin/pint <paths>` when the project uses Pint.
