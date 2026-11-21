#!/bin/bash
# Offline end-to-end test of pr-assets.sh: upload, plan, and the destructive prune rewrite,
# against a local bare repository as origin and a stub `gh` first on PATH. Covers a UTF-8
# branch name mapping to one folder in upload (any locale) and in plan/prune, a stale plan,
# and a lease that refuses the rewrite when the remote moves between fetch and push.
# Run: bash test-pr-assets.sh   (PR_ASSETS_SCRIPT=<path> tests another copy)

set -e

here=$(cd "$(dirname "$0")" && pwd)
script=${PR_ASSETS_SCRIPT:-$here/pr-assets.sh}
t=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$t"' EXIT

fail() { echo "FAIL $1" >&2; exit 1; }
ok() { echo "ok $1"; }

mkdir -p "$t/bin"
cat > "$t/bin/gh" <<'STUB'
#!/bin/bash
# `gh repo view ...`: owner/repo. `gh pr list ...`: the PRs in $STUB_PRS.
# With STUB_RACE=<bare repo>, the first `pr list` also commits a racing upload on top of
# that repo's pr-assets and records it in $STUB_RACED.
case "$1" in
  repo) echo owner/repo ;;
  pr)
    if [ -n "$STUB_RACE" ] && [ ! -s "$STUB_RACED" ]; then
      cur=$(git --git-dir="$STUB_RACE" rev-parse refs/heads/pr-assets)
      c=$(git --git-dir="$STUB_RACE" commit-tree "$cur^{tree}" -p "$cur" -m 'racing upload')
      git --git-dir="$STUB_RACE" update-ref refs/heads/pr-assets "$c"
      echo "$c" > "$STUB_RACED"
    fi
    cat "$STUB_PRS" ;;
  *) echo "gh stub: unexpected $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$t/bin/gh"
export PATH="$t/bin:$PATH" STUB_PRS="$t/prs.json"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
# Every upload is years old, so only an open or recently closed PR keeps a folder.
export GIT_AUTHOR_DATE='2001-01-01T00:00:00Z' GIT_COMMITTER_DATE='2001-01-01T00:00:00Z'
echo '[]' > "$STUB_PRS"

origin="$t/origin.git"
git init -q --bare "$origin"
git init -q -b main "$t/repo"
cd "$t/repo"
git remote add origin "$origin"
printf 'png-a' > "$t/shot.png"
printf 'png-b' > "$t/my shot.png"

remote_tip() { git --git-dir="$origin" rev-parse -q --verify refs/heads/pr-assets || true; }
remote_folders() { git --git-dir="$origin" ls-tree -d --name-only pr-assets | sort | tr '\n' ' '; }

# --- usage ---
code=0; bash "$script" > /dev/null 2>&1 || code=$?
[ "$code" = 2 ] || fail "no subcommand should exit 2, got $code"
code=0; bash "$script" prune --drop x > /dev/null 2>&1 || code=$?
[ "$code" = 2 ] || fail "prune without --tip should exit 2, got $code"
out=$(bash "$script" plan 2>/dev/null) || fail "plan with no pr-assets branch exited non-zero"
[ "$(printf '%s' "$out" | jq -c '[.tip, .candidates]')" = '[null,[]]' ] || fail "plan with no branch: $out"
ok "usage errors exit 2; plan with no branch is empty"

# --- upload: the first push creates the branch (lease: must not exist) ---
out=$(LC_ALL=C bash "$script" upload 'feat/café' "$t/shot.png" "$t/my shot.png" 2>/dev/null) \
  || fail "first upload exited non-zero"
case "$out" in
  *"https://github.com/owner/repo/blob/pr-assets/feat-caf-/"*"-shot.png?raw=true)"*) ;;
  *) fail "upload link should name folder feat-caf-: $out" ;;
esac
case "$out" in
  *"-my%20shot.png?raw=true)"*) ;;
  *) fail "a space in a file name should be percent-encoded: $out" ;;
esac
[ "$(printf '%s\n' "$out" | grep -c '^!\[')" = 2 ] || fail "one Markdown line per image: $out"
ok "upload creates pr-assets and prints one encoded link per image"

# Same UTF-8 branch in a UTF-8 locale lands in the same folder; later uploads keep earlier ones.
LC_ALL=en_US.UTF-8 bash "$script" upload 'feat/café' "$t/shot.png" > /dev/null 2>&1 || fail "UTF-8 locale upload"
for b in 'fix/日本' 'gone/old' 'closed/recent'; do
  LC_ALL=C bash "$script" upload "$b" "$t/shot.png" > /dev/null 2>&1 || fail "upload of $b exited non-zero"
done
[ "$(remote_folders)" = 'closed-recent feat-caf- fix--- gone-old ' ] \
  || fail "pr-assets should hold four folders, has: $(remote_folders)"
[ "$(git --git-dir="$origin" ls-tree --name-only pr-assets feat-caf-/ | wc -l | tr -d ' ')" = 2 ] \
  || fail "re-uploading the same image should not add a second file"
ok "UTF-8 branch maps to one folder in any locale; uploads accumulate"

# An upload that loses a race (origin moves during its first push) retries on the new tip.
cat > .git/hooks/pre-push <<HOOK
#!/bin/bash
[ -s "$t/upload-raced" ] && exit 0
cur=\$(git --git-dir="$origin" rev-parse refs/heads/pr-assets)
c=\$(git --git-dir="$origin" commit-tree "\$cur^{tree}" -p "\$cur" -m 'racing upload')
git --git-dir="$origin" update-ref refs/heads/pr-assets "\$c"
echo "\$c" > "$t/upload-raced"
HOOK
chmod +x .git/hooks/pre-push
bash "$script" upload 'gone/old' "$t/shot.png" > /dev/null 2>&1 || fail "an upload that lost a race should retry and succeed"
rm -f .git/hooks/pre-push
[ -s "$t/upload-raced" ] || fail "the racing upload did not run"
[ "$(git --git-dir="$origin" rev-parse pr-assets~1)" = "$(cat "$t/upload-raced")" ] \
  || fail "the retried upload should build on the racing commit"
ok "upload retries on top of a racing commit"

# --- plan ---
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > "$STUB_PRS" <<JSON
[{"number": 11, "headRefName": "feat/café", "state": "MERGED", "closedAt": "2001-02-01T00:00:00Z"},
 {"number": 12, "headRefName": "fix/日本", "state": "OPEN", "closedAt": null},
 {"number": 13, "headRefName": "closed/recent", "state": "CLOSED", "closedAt": "$now"}]
JSON
plan=$(LC_ALL=C bash "$script" plan 2>/dev/null) || fail "plan exited non-zero"
tip=$(printf '%s' "$plan" | jq -r .tip)
[ "$tip" = "$(remote_tip)" ] || fail "plan tip should be the remote tip: $plan"
[ "$(printf '%s' "$plan" | jq -c '[.candidates[].folder] | sort')" = '["feat-caf-","gone-old"]' ] \
  || fail "candidates should be feat-caf- and gone-old: $plan"
[ "$(printf '%s' "$plan" | jq -r '.candidates[] | select(.folder == "feat-caf-") | .reason')" = 'PR #11 merged 2001-02-01' ] \
  || fail "the UTF-8 branch's PR should map to its folder: $plan"
[ "$(printf '%s' "$plan" | jq -c '[.kept[] | "\(.folder): \(.reason)"] | sort')" \
  = "[\"closed-recent: PR #13 closed ${now:0:10}\",\"fix---: open PR #12\"]" ] \
  || fail "open and recently closed PRs should keep their folders: $plan"
[ "$(printf '%s' "$plan" | jq '.bytes > 0')" = true ] || fail "plan should total bytes: $plan"
[ "$(remote_tip)" = "$tip" ] || fail "plan must not change the remote"
ok "plan maps PRs (UTF-8 included) to folders and lists candidates and kept"

# --- prune refusals: nothing changes ---
code=0; bash "$script" prune --tip "$tip" --drop 'fix---' > /dev/null 2>&1 || code=$?
[ "$code" = 1 ] && [ "$(remote_tip)" = "$tip" ] || fail "dropping a non-candidate should refuse (exit 1), got $code"
ok "prune refuses a folder that is not a candidate"

printf 'png-c' > "$t/late.png"
bash "$script" upload 'closed/recent' "$t/late.png" > /dev/null 2>&1 || fail "late upload"
moved=$(remote_tip)
code=0; bash "$script" prune --tip "$tip" --drop gone-old > /dev/null 2>&1 || code=$?
[ "$code" = 1 ] && [ "$(remote_tip)" = "$moved" ] || fail "a stale plan tip should refuse (exit 1), got $code"
ok "prune refuses a tip that moved since the plan"

# Lease: the remote moves after prune fetched and checked the tip, before its push. The gh
# stub's `pr list` runs in that window, so with STUB_RACE set it lands a racing upload on
# origin. A plain force push would clobber it; the lease must refuse.
tip=$(bash "$script" plan 2>/dev/null | jq -r .tip)
code=0; err=$(STUB_RACE="$origin" STUB_RACED="$t/raced" bash "$script" prune --tip "$tip" --drop gone-old 2>&1 >/dev/null) || code=$?
[ -s "$t/raced" ] || fail "the racing upload did not run"
[ "$code" = 1 ] || fail "prune should fail when the remote moves before the push, got $code: $err"
[ "$(remote_tip)" = "$(cat "$t/raced")" ] || fail "the racing commit should survive: remote is $(remote_tip)"
case "$err" in *"moved since the plan"*) ;; *) fail "lease refusal should say the branch moved: $err" ;; esac
[ "$(remote_folders)" = 'closed-recent feat-caf- fix--- gone-old ' ] || fail "nothing should be dropped: $(remote_folders)"
ok "prune's push is leased: a remote that moved keeps its commit"

# --- prune: the rewrite ---
plan=$(LC_ALL=C bash "$script" plan 2>/dev/null)
tip=$(printf '%s' "$plan" | jq -r .tip)
freed_want=$(printf '%s' "$plan" | jq '[.candidates[] | .bytes] | add')
out=$(LC_ALL=C bash "$script" prune --tip "$tip" --drop feat-caf- --drop gone-old 2>/dev/null) || fail "prune exited non-zero"
new=$(printf '%s' "$out" | jq -r .tip)
[ "$new" = "$(remote_tip)" ] || fail "prune should push its new tip: $out, remote $(remote_tip)"
[ "$(printf '%s' "$out" | jq -c .dropped)" = '["feat-caf-","gone-old"]' ] || fail "dropped list: $out"
[ "$(printf '%s' "$out" | jq .freed_bytes)" = "$freed_want" ] || fail "freed_bytes should be $freed_want: $out"
[ "$(remote_folders)" = 'closed-recent fix--- ' ] || fail "only kept folders should remain: $(remote_folders)"
[ -z "$(git --git-dir="$origin" rev-list --parents -n1 "$new" | cut -s -d' ' -f2)" ] || fail "the rewrite should be an orphan commit"
[ "$(git --git-dir="$origin" rev-parse "$new:fix---")" = "$(git --git-dir="$origin" rev-parse "$tip:fix---")" ] \
  || fail "a kept folder's tree should be unchanged"
ok "prune rewrites pr-assets as an orphan holding only kept folders"

# Upload after a prune builds on the rewritten tip.
bash "$script" upload 'fix/日本' "$t/late.png" > /dev/null 2>&1 || fail "upload after prune"
[ "$(git --git-dir="$origin" rev-parse pr-assets~1)" = "$new" ] || fail "upload after prune should build on the new tip"
ok "upload after prune builds on the rewritten tip"
