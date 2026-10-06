#!/bin/bash
# SessionStart: in a linked git worktree of a Laravel app that has no vendor/ yet
# (`claude --worktree`, or a session opened in a recipe's .claude/worktrees/<name>),
# point the agent at laravel-herd-worktrees' "Bootstrap a bare worktree" before it runs anything.
# Runs at the start of every session in every repo, so every other path exits 0 at once.
# WorktreeCreate cannot do this: it replaces git's worktree creation and plugins cannot register it.
set -e

dir="${CLAUDE_PROJECT_DIR:-$PWD}"
[[ -f "$dir/.git" ]] || exit 0  # a linked worktree has a .git file; the main checkout has a directory
[[ -f "$dir/artisan" && -f "$dir/composer.json" && ! -e "$dir/vendor" ]] || exit 0

echo "This session is in a bare git worktree of a Laravel app: no vendor/ yet, and likely no .env. Before running tests, artisan, or the app, make it runnable with the laravel-herd-worktrees skill's \"Bootstrap a bare worktree\" section."
