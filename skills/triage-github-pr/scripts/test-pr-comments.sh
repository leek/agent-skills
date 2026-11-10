#!/bin/bash
# Offline test for pr-comments.sh (and review-threads.sh, which it calls): a stub `gh` first
# on PATH returns canned JSON per subcommand and fails the calls GH_FAIL (a regex) matches.
# Prints one `ok <case>` line per case and exits non-zero on the first failed assertion.
set -e

here=$(cd "$(dirname "$0")" && pwd)
script="$here/pr-comments.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/fix"
export GH_FIX="$work/fix" GH_LOG="$work/gh.log"

cat > "$work/bin/gh" <<'STUB'
#!/bin/bash
args="$*"
printf '%s\n' "$args" | tr '\n' ' ' >> "$GH_LOG"; echo >> "$GH_LOG"
if [ -n "${GH_FAIL:-}" ] && [[ "$args" =~ $GH_FAIL ]]; then
  echo "HTTP 403: Resource not accessible by integration (stub)" >&2; exit 1
fi
jqf=""; prev=""
for a in "$@"; do
  case "$prev" in --jq|-q) jqf=$a ;; esac
  prev=$a
done
emit() { if [ -n "$jqf" ]; then jq -rc "$jqf" "$1"; else cat "$1"; fi; }
case "$args" in
  "repo view"*) emit "$GH_FIX/repo-view.json" ;;
  "pr view"*) emit "$GH_FIX/pr-view.json" ;;
  "api graphql"*reviewThreads*) emit "$GH_FIX/threads.json" ;;
  "api user"*) emit "$GH_FIX/user.json" ;;
  "api repos/o/r/pulls/7/reviews"*) emit "$GH_FIX/reviews.json" ;;
  "api repos/o/r/pulls/7/comments"*) emit "$GH_FIX/inline.json" ;;
  "api repos/o/r/issues/7/comments"*) emit "$GH_FIX/issue.json" ;;
  *) echo "stub gh: unexpected call: $args" >&2; exit 97 ;;
esac
STUB
chmod +x "$work/bin/gh"
PATH="$work/bin:$PATH"

fail() { echo "FAIL $1" >&2; exit 1; }
ok() { echo "ok $1"; }
eq() { [ "$2" = "$3" ] || fail "$1: expected '$3', got '$2'"; }
run() { rc=0; out=$(env GH_FAIL="${GH_FAIL:-}" bash "$script" "$@" 2> "$work/stderr") || rc=$?; }

echo '{"nameWithOwner":"o/r"}' > "$GH_FIX/repo-view.json"
echo '{"headRefOid":"abc1234def"}' > "$GH_FIX/pr-view.json"
echo '{"login":"me"}' > "$GH_FIX/user.json"
# Two pages, as `gh api graphql --paginate` prints them: one object per page.
cat > "$GH_FIX/threads.json" <<'JSON'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":true,"endCursor":"x"},"nodes":[
  {"id":"PRRT_a","isResolved":true,"comments":{"nodes":[{"databaseId":111},{"databaseId":112}]}}]}}}}}
{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
  {"id":"PRRT_b","isResolved":false,"comments":{"nodes":[{"databaseId":222}]}}]}}}}}
JSON
echo '[{"id":1,"user":{"login":"copilot[bot]"},"state":"COMMENTED","commit_id":"abc1234def0000","submitted_at":"2026-01-01T00:00:00Z","body":"review"}]' > "$GH_FIX/reviews.json"
cat > "$GH_FIX/inline.json" <<'JSON'
[{"id":111,"user":{"login":"codex[bot]"},"path":"a.php","line":3,"original_line":3,"commit_id":"abc1234def0000","updated_at":"2026-01-01T00:00:00Z","in_reply_to_id":null,"html_url":"https://x/111","body":"finding a"},
 {"id":112,"user":{"login":"me"},"path":"a.php","line":3,"original_line":3,"commit_id":"abc1234def0000","updated_at":"2026-01-02T00:00:00Z","in_reply_to_id":111,"html_url":"https://x/112","body":"fixed"},
 {"id":222,"user":{"login":"codex[bot]"},"path":"b.php","line":null,"original_line":9,"commit_id":"abc1234def0000","updated_at":"2026-01-01T00:00:00Z","in_reply_to_id":null,"html_url":"https://x/222","body":"finding b"}]
JSON
# Own comments 31 (an older run's marker) and 33 (the newest); 32 is someone else's with the marker.
cat > "$GH_FIX/issue.json" <<'JSON'
[{"id":30,"user":{"login":"codex[bot]"},"updated_at":"2026-01-01T00:00:00Z","html_url":"https://x/30","body":"summary"},
 {"id":31,"user":{"login":"me"},"updated_at":"2026-01-01T00:00:00Z","html_url":"https://x/31","body":"<!-- triage-round: 2 -->\nold"},
 {"id":32,"user":{"login":"mallory"},"updated_at":"2026-01-01T00:00:00Z","html_url":"https://x/32","body":"<!-- triage-disposition -->\nnot yours"},
 {"id":33,"user":{"login":"me"},"updated_at":"2026-01-03T00:00:00Z","html_url":"https://x/33","body":"<!-- triage-disposition -->\n**Triage, round 1**"},
 {"id":34,"user":{"login":"me"},"updated_at":"2026-01-04T00:00:00Z","html_url":"https://x/34","body":"a plain comment of mine"}]
JSON

# --- full run ---
run 7 --repo o/r
eq "full exit" "$rc" 0
eq "full keys" "$(echo "$out" | jq -c 'keys')" '["disposition","head","inline","issue","me","pr","reviews","threads_open"]'
eq "full threads_open" "$(echo "$out" | jq -c '.threads_open')" 1
eq "full thread map" "$(echo "$out" | jq -c '[.inline[] | [.id, .thread, .resolved]]')" '[[111,"PRRT_a",true],[112,"PRRT_a",true],[222,"PRRT_b",false]]'
eq "full line fallback" "$(echo "$out" | jq -c '.inline[2].line')" 9
eq "full me" "$(echo "$out" | jq -r '.me')" me
eq "full counts" "$(echo "$out" | jq -c '[(.reviews | length), (.issue | length)]')" '[1,5]'
ok "full run maps threads across pages"

eq "disposition is the newest own marker comment" "$(echo "$out" | jq -c '.disposition | [.id, .url]')" '[33,"https://x/33"]'
eq "disposition keys" "$(echo "$out" | jq -c '.disposition | keys')" '["body","id","url"]'
echo "$out" | jq -e '.disposition.body | test("Triage, round 1")' >/dev/null || fail "disposition body"
ok "disposition found"

# --- an older run's marker counts when it is the only one; none gives null ---
cp "$GH_FIX/issue.json" "$work/issue.all"
jq 'map(select(.id != 33))' "$work/issue.all" > "$GH_FIX/issue.json"
run 7 --repo o/r
eq "old marker" "$(echo "$out" | jq -c '.disposition.id')" 31
jq 'map(select(.id != 33 and .id != 31))' "$work/issue.all" > "$GH_FIX/issue.json"
run 7 --repo o/r
eq "no disposition" "$(echo "$out" | jq -c '.disposition')" null
cp "$work/issue.all" "$GH_FIX/issue.json"
ok "disposition null when you have none"

# --- --since: new or edited only, own items dropped, disposition still reported ---
run 7 --repo o/r; echo "$out" > "$work/snap.json"
jq '. + [{"id":40,"user":{"login":"codex[bot]"},"updated_at":"2026-01-05T00:00:00Z","html_url":"https://x/40","body":"new"}]
    | map(if .id == 30 then .updated_at = "2026-01-06T00:00:00Z" else . end)' "$work/issue.all" > "$GH_FIX/issue.json"
run 7 --repo o/r --since "$work/snap.json"
eq "since exit" "$rc" 0
eq "since issue ids" "$(echo "$out" | jq -c '[.issue[].id]')" '[30,40]'
eq "since inline" "$(echo "$out" | jq -c '.inline')" '[]'
eq "since disposition" "$(echo "$out" | jq -c '.disposition.id')" 33
cp "$work/issue.all" "$GH_FIX/issue.json"
ok "since keeps new and edited, and the disposition"

# --- --count ---
: > "$GH_LOG"; run 7 --repo o/r --count
eq "count out" "$(echo "$out" | jq -c .)" '{"pr":7,"head":"abc1234def","threads_open":1}'
eq "count calls" "$(wc -l < "$GH_LOG" | tr -d ' ')" 2
ok "count"

# --- a failing gh never reads as zero open threads ---
GH_FAIL='reviewThreads' run 7 --repo o/r --count
[ "$rc" -ne 0 ] || fail "count on a 403 must fail"
eq "count on 403 prints nothing" "$out" ""
GH_FAIL='reviewThreads' run 7 --repo o/r
[ "$rc" -ne 0 ] || fail "full run on a 403 must fail"
eq "full on 403 prints nothing" "$out" ""
GH_FAIL='issues/7/comments' run 7 --repo o/r
[ "$rc" -ne 0 ] || fail "a failed issue-comment read must fail"
# A GraphQL answer without the thread list (an error body) is a failure too.
cp "$GH_FIX/threads.json" "$work/threads.ok"
echo '{"data":{"repository":{"pullRequest":null}}}' > "$GH_FIX/threads.json"
run 7 --repo o/r --count
[ "$rc" -ne 0 ] || fail "a null pullRequest must fail"
cp "$work/threads.ok" "$GH_FIX/threads.json"
ok "failing gh exits non-zero"

# --- login lookup fails: disposition is not checked, the run still prints ---
GH_FAIL='^api user' run 7 --repo o/r
eq "no login exit" "$rc" 0
eq "no login me" "$(echo "$out" | jq -c '.me')" '""'
eq "no login disposition" "$(echo "$out" | jq -c '.disposition')" null
ok "unknown login leaves disposition null"

# --- usage ---
run; eq "no args" "$rc" 2
run 7 --since "$work/none.json"; eq "missing snapshot" "$rc" 2
run 7 --bogus; eq "unknown flag" "$rc" 2
rc=0; bash "$here/review-threads.sh" o/r abc 2>/dev/null || rc=$?; eq "helper bad pr" "$rc" 2
rc=0; bash "$here/review-threads.sh" nor 7 2>/dev/null || rc=$?; eq "helper bad repo" "$rc" 2
ok "usage errors exit 2"
