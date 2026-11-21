#!/bin/bash
# Offline test of prune-pr-assets.sh against folders the pr skill's upload-screenshots.sh
# made under LC_ALL=C: a folder whose PR is open is kept with that PR as the reason, even
# when the branch name is UTF-8, and only a folder with no PR and an old upload is a candidate.
# `gh` is a stub first on PATH; origin is a local bare repository.
# Run: bash test-prune-pr-assets.sh   (PRUNE_SCRIPT=<path> or UPLOAD_SCRIPT=<path> tests another copy)

set -e

here=$(cd "$(dirname "$0")" && pwd)
script=${PRUNE_SCRIPT:-$here/prune-pr-assets.sh}
upload=${UPLOAD_SCRIPT:-$here/../../pr/scripts/upload-screenshots.sh}
t=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$t"' EXIT

fail() { echo "FAIL $1" >&2; exit 1; }
ok() { echo "ok $1"; }

mkdir -p "$t/bin"
cat > "$t/bin/gh" <<'STUB'
#!/bin/bash
# `gh repo view ...`: owner/repo. `gh pr list ...`: the PRs in $STUB_PRS.
case "$1" in
  repo) echo owner/repo ;;
  pr) cat "$STUB_PRS" ;;
esac
STUB
chmod +x "$t/bin/gh"
export PATH="$t/bin:$PATH" STUB_PRS="$t/prs.json"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
# Every upload is years old, so only an open PR keeps a folder.
export GIT_AUTHOR_DATE='2001-01-01T00:00:00Z' GIT_COMMITTER_DATE='2001-01-01T00:00:00Z'

git init -q --bare "$t/origin.git"
git init -q -b main "$t/repo"
cd "$t/repo"
git remote add origin "$t/origin.git"
printf 'png' > "$t/shot.png"
for b in 'feat/café' 'fix/日本' 'gone/old'; do
  LC_ALL=C bash "$upload" "$b" "$t/shot.png" > /dev/null 2>&1 || fail "upload of $b exited non-zero"
done

cat > "$STUB_PRS" <<'JSON'
[{"number": 11, "headRefName": "feat/café", "state": "OPEN", "closedAt": null},
 {"number": 12, "headRefName": "fix/日本", "state": "OPEN", "closedAt": null}]
JSON

out=$(LC_ALL=C bash "$script" 2>/dev/null) || fail "listing exited non-zero"
cand=$(printf '%s' "$out" | jq -c '[.candidates[].folder]')
[ "$cand" = '["gone-old"]' ] || fail "only gone-old should be a candidate, got $cand: $out"
ok "only the folder with no PR is a candidate"
kept=$(printf '%s' "$out" | jq -c '[.kept[] | .reason] | sort')
[ "$kept" = '["open PR #11","open PR #12"]' ] || fail "open PRs should keep their folders, got $kept: $out"
ok "open PRs with UTF-8 branch names keep their folders"
