#!/bin/bash
# Offline test of upload-screenshots.sh: the pr-assets folder a branch maps to, under
# LC_ALL=C (where `tr` works byte by byte), must be the one repository-cleanup's
# prune-pr-assets.sh computes, one `-` per character, so a UTF-8 branch name keeps its folder.
# `gh` is a stub first on PATH; origin is a local bare repository.
# Run: bash test-upload-screenshots.sh   (UPLOAD_SCRIPT=<path> tests another copy)

set -e

here=$(cd "$(dirname "$0")" && pwd)
script=${UPLOAD_SCRIPT:-$here/upload-screenshots.sh}
t=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$t"' EXIT

fail() { echo "FAIL $1" >&2; exit 1; }
ok() { echo "ok $1"; }

mkdir -p "$t/bin"
printf '#!/bin/bash\necho owner/repo\n' > "$t/bin/gh"
chmod +x "$t/bin/gh"
export PATH="$t/bin:$PATH"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

git init -q --bare "$t/origin.git"
git init -q -b main "$t/repo"
cd "$t/repo"
git remote add origin "$t/origin.git"
printf 'png' > "$t/shot.png"

# branch -> folder, as prune-pr-assets.sh maps headRefName (jq gsub, one `-` per character)
while IFS='|' read -r branch want; do
  out=$(LC_ALL=C bash "$script" "$branch" "$t/shot.png" 2>/dev/null) || fail "upload of $branch exited non-zero"
  case "$out" in
    *"/blob/pr-assets/$want/"*) ;;
    *) fail "$branch: link should name folder $want, got: $out" ;;
  esac
  git -C "$t/origin.git" ls-tree -d --name-only pr-assets | grep -qxF -- "$want" \
    || fail "$branch: pr-assets should hold folder $want, has: $(git -C "$t/origin.git" ls-tree -d --name-only pr-assets | tr '\n' ' ')"
  ok "$branch -> $want"
done <<'CASES'
feat/plain|feat-plain
feat/café|feat-caf-
fix/日本|fix---
CASES
