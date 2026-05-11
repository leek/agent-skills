#!/bin/bash
# Create a new git worktree for a Laravel project served by Laravel Herd.
# - Creates worktree as sibling of current repo
# - Copies .env, rewrites APP_URL/DB/cache/session/redis prefixes
# - Installs composer + node deps (auto-detects pnpm/yarn/npm)
# - Generates APP_KEY, creates DB, runs migrations
#
# Usage:
#   bash worktree-new.sh <suffix> <base-branch> [--driver sqlite|mysql|pgsql] [--no-migrate]
#
# Example:
#   bash worktree-new.sh feat-billing main --driver sqlite

set -euo pipefail

SUFFIX="${1:-}"
BASE="${2:-}"
DRIVER="sqlite"
RUN_MIGRATE=1

if [[ -z "$SUFFIX" || -z "$BASE" ]]; then
  echo "Usage: $0 <suffix> <base-branch> [--driver sqlite|mysql|pgsql] [--no-migrate]" >&2
  exit 2
fi

shift 2
while [[ $# -gt 0 ]]; do
  case "$1" in
    --driver) DRIVER="$2"; shift 2 ;;
    --no-migrate) RUN_MIGRATE=0; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

# --- Resolve paths ---------------------------------------------------------
REPO_ROOT="$(git rev-parse --show-toplevel)"
APP_NAME="$(basename "$REPO_ROOT")"
PARENT_DIR="$(dirname "$REPO_ROOT")"
WT_NAME="${APP_NAME}-${SUFFIX}"
WT_PATH="${PARENT_DIR}/${WT_NAME}"
NEW_BRANCH="${SUFFIX}"
NEW_URL="http://${WT_NAME}.test"

if [[ -e "$WT_PATH" ]]; then
  echo "Path already exists: $WT_PATH" >&2
  exit 1
fi

echo ">> Creating worktree $WT_PATH from $BASE as branch $NEW_BRANCH" >&2
git -C "$REPO_ROOT" worktree add -b "$NEW_BRANCH" "$WT_PATH" "$BASE"

# --- .env ------------------------------------------------------------------
if [[ ! -f "$REPO_ROOT/.env" ]]; then
  echo "No .env in main checkout; copy .env.example instead" >&2
  cp "$REPO_ROOT/.env.example" "$WT_PATH/.env"
else
  cp "$REPO_ROOT/.env" "$WT_PATH/.env"
fi

ENV_FILE="$WT_PATH/.env"
SAFE_SUFFIX="$(echo "$SUFFIX" | tr -c 'a-zA-Z0-9' '_')"
DB_NAME="${APP_NAME//-/_}_${SAFE_SUFFIX}"

# Helper: set or append a key=value in .env (BSD sed compatible)
set_env() {
  local key="$1" val="$2"
  if grep -q "^${key}=" "$ENV_FILE"; then
    # use | as delimiter to avoid clashing with URL slashes
    sed -i '' "s|^${key}=.*|${key}=${val}|" "$ENV_FILE"
  else
    echo "${key}=${val}" >> "$ENV_FILE"
  fi
}

set_env APP_URL "$NEW_URL"
set_env SESSION_COOKIE "${WT_NAME//-/_}_session"
set_env CACHE_PREFIX "${WT_NAME//-/_}_cache"
set_env REDIS_PREFIX "${WT_NAME//-/_}_db_"

case "$DRIVER" in
  sqlite)
    set_env DB_CONNECTION sqlite
    set_env DB_DATABASE "${WT_PATH}/database/database.sqlite"
    mkdir -p "$WT_PATH/database"
    : > "$WT_PATH/database/database.sqlite"
    ;;
  mysql)
    set_env DB_CONNECTION mysql
    set_env DB_DATABASE "$DB_NAME"
    echo ">> Creating MySQL database $DB_NAME (Herd's mysql on default socket)" >&2
    mysql -uroot -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" \
      || echo "WARN: could not auto-create DB; create it manually" >&2
    ;;
  pgsql)
    set_env DB_CONNECTION pgsql
    set_env DB_DATABASE "$DB_NAME"
    echo ">> Creating Postgres database $DB_NAME" >&2
    createdb "$DB_NAME" 2>/dev/null || echo "WARN: could not auto-create DB; create it manually" >&2
    ;;
  *)
    echo "Unknown driver: $DRIVER" >&2; exit 2 ;;
esac

# --- Install deps ----------------------------------------------------------
cd "$WT_PATH"

echo ">> composer install" >&2
composer install --no-interaction --prefer-dist

if [[ -f package.json ]]; then
  if [[ -f pnpm-lock.yaml ]] && command -v pnpm >/dev/null; then
    echo ">> pnpm install" >&2
    pnpm install
  elif [[ -f yarn.lock ]] && command -v yarn >/dev/null; then
    echo ">> yarn install" >&2
    yarn install
  else
    echo ">> npm ci" >&2
    npm ci
  fi
fi

# --- Laravel bootstrap -----------------------------------------------------
echo ">> php artisan key:generate" >&2
php artisan key:generate --force

if [[ -d storage/app && ! -L public/storage ]]; then
  php artisan storage:link || true
fi

if [[ "$RUN_MIGRATE" -eq 1 ]]; then
  echo ">> php artisan migrate --force" >&2
  php artisan migrate --force
fi

php artisan optimize:clear >/dev/null || true

# --- Done ------------------------------------------------------------------
cat <<EOF
{
  "worktree": "$WT_PATH",
  "branch": "$NEW_BRANCH",
  "url": "$NEW_URL",
  "db_driver": "$DRIVER",
  "db_database": "$(grep ^DB_DATABASE= "$ENV_FILE" | cut -d= -f2-)"
}
EOF

echo ">> Done. Open $NEW_URL" >&2
