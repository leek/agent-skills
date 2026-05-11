#!/bin/bash
# Remove a Laravel + Herd worktree.
# - git worktree remove
# - optional DB drop
# - herd unlink if a manual link exists
#
# Usage:
#   bash worktree-rm.sh <suffix> [--drop-db] [--force]

set -euo pipefail

SUFFIX="${1:-}"
DROP_DB=0
FORCE=0

if [[ -z "$SUFFIX" ]]; then
  echo "Usage: $0 <suffix> [--drop-db] [--force]" >&2
  exit 2
fi

shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --drop-db) DROP_DB=1; shift ;;
    --force) FORCE=1; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

REPO_ROOT="$(git rev-parse --show-toplevel)"
APP_NAME="$(basename "$REPO_ROOT")"
PARENT_DIR="$(dirname "$REPO_ROOT")"
WT_NAME="${APP_NAME}-${SUFFIX}"
WT_PATH="${PARENT_DIR}/${WT_NAME}"

if [[ ! -d "$WT_PATH" ]]; then
  echo "Worktree not found: $WT_PATH" >&2
  exit 1
fi

# Capture DB info before removal
ENV_FILE="$WT_PATH/.env"
DB_CONN=""
DB_DATABASE=""
if [[ -f "$ENV_FILE" ]]; then
  DB_CONN="$(grep ^DB_CONNECTION= "$ENV_FILE" | cut -d= -f2- || true)"
  DB_DATABASE="$(grep ^DB_DATABASE= "$ENV_FILE" | cut -d= -f2- || true)"
fi

# Try to unlink in Herd in case of manual `herd link`
if command -v herd >/dev/null; then
  (cd "$WT_PATH" && herd unlink >/dev/null 2>&1) || true
fi

REMOVE_FLAGS=()
[[ "$FORCE" -eq 1 ]] && REMOVE_FLAGS+=("--force")

echo ">> git worktree remove $WT_PATH" >&2
git -C "$REPO_ROOT" worktree remove "${REMOVE_FLAGS[@]}" "$WT_PATH"

if [[ "$DROP_DB" -eq 1 ]]; then
  case "$DB_CONN" in
    sqlite)
      # sqlite file already removed with the worktree dir
      ;;
    mysql)
      echo ">> Dropping MySQL DB $DB_DATABASE" >&2
      mysql -uroot -e "DROP DATABASE IF EXISTS \`${DB_DATABASE}\`;" \
        || echo "WARN: failed to drop DB" >&2
      ;;
    pgsql)
      echo ">> Dropping Postgres DB $DB_DATABASE" >&2
      dropdb "$DB_DATABASE" 2>/dev/null || echo "WARN: failed to drop DB" >&2
      ;;
  esac
fi

echo ">> Done." >&2
