#!/bin/bash
# Offline test for pr-reply.sh: a stub `gh` first on PATH returns canned JSON, records every
# call, keeps each request body it was sent, and fails the calls GH_FAIL (a regex) matches.
# Prints one `ok <case>` line per case and exits non-zero on the first failed assertion.
set -e

here=$(cd "$(dirname "$0")" && pwd)
script="$here/pr-reply.sh"
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
jqf=""; input=""; prev=""
for a in "$@"; do
  case "$prev" in --jq|-q) jqf=$a ;; --input) input=$a ;; esac
  prev=$a
done
emit() { if [ -n "$jqf" ]; then jq -rc "$jqf" "$1"; else cat "$1"; fi; }
case "$args" in
  "repo view"*) emit "$GH_FIX/repo-view.json" ;;
  "api graphql"*resolveReviewThread*)
    for a in "$@"; do case "$a" in threadId=*) echo "${a#threadId=}" >> "$GH_FIX/resolved-threads" ;; esac; done
    emit "$GH_FIX/resolve.json" ;;
  "api graphql"*reviewThreads*) emit "$GH_FIX/threads.json" ;;
  "api repos/"*"/comments/"*"/replies"*)
    id=${args#*/comments/}; id=${id%%/replies*}
    cp "$input" "$GH_FIX/sent-$id.json"
    jq -n --arg id "$id" '{id: 9, html_url: "https://github.com/o/r/pull/7#discussion_r\($id)9"}' ;;
  *) echo "stub gh: unexpected call: $args" >&2; exit 97 ;;
esac
STUB
chmod +x "$work/bin/gh"
PATH="$work/bin:$PATH"

fail() { echo "FAIL $1" >&2; exit 1; }
ok() { echo "ok $1"; }
eq() { [ "$2" = "$3" ] || fail "$1: expected '$3', got '$2'"; }
reset() {
  rm -f "$GH_FIX"/sent-*.json "$GH_FIX/resolved-threads"
  : > "$GH_LOG"
  echo '{"nameWithOwner":"o/r"}' > "$GH_FIX/repo-view.json"
  echo '{"data":{"resolveReviewThread":{"thread":{"isResolved":true}}}}' > "$GH_FIX/resolve.json"
  # One page: two threads, one still open.
  echo '{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
    {"id":"PRRT_a","isResolved":true,"comments":{"nodes":[{"databaseId":111}]}},
    {"id":"PRRT_b","isResolved":false,"comments":{"nodes":[{"databaseId":222}]}}]}}}}}' > "$GH_FIX/threads.json"
}
run() { rc=0; out=$(env GH_FAIL="${GH_FAIL:-}" bash "$script" "$@" 2> "$work/stderr") || rc=$?; }

# A body no shell quoting would survive.
tricky=$'It\'s fixed in `abc123`: "$(rm -rf /)" & $HOME\nsecond line -f body=@x'
jq -n --arg tricky "$tricky" '[
  {comment_id: 111, thread: "PRRT_a", body: "fixed in abc123; validated; push pending", resolve: true},
  {comment_id: 222, thread: null, body: "MAJOR; verified; fixing in current batch", resolve: false},
  {comment_id: "3790734403", thread: "PRRT_c", body: $tricky, resolve: true}]' > "$work/batch.json"

# --- a whole batch: replies posted, bodies intact, only the asked threads resolved ---
reset; run 7 "$work/batch.json" --repo o/r
eq "batch exit" "$rc" 0
eq "batch shape" "$(echo "$out" | jq -c 'keys')" '["pr","replies","threads_open"]'
eq "batch pr" "$(echo "$out" | jq -c '.pr')" 7
eq "batch replies" "$(echo "$out" | jq -c '[.replies[] | [.comment_id, .resolved, .error]]')" '[[111,true,null],[222,false,null],[3790734403,true,null]]'
eq "batch reply_url" "$(echo "$out" | jq -r '.replies[1].reply_url')" 'https://github.com/o/r/pull/7#discussion_r2229'
eq "batch threads_open" "$(echo "$out" | jq -c '.threads_open')" 1
eq "batch body kept byte for byte" "$(jq -r .body "$GH_FIX/sent-3790734403.json")" "$tricky"
eq "batch body is the only field sent" "$(jq -c keys "$GH_FIX/sent-111.json")" '["body"]'
eq "batch resolved threads" "$(tr '\n' ' ' < "$GH_FIX/resolved-threads")" 'PRRT_a PRRT_c '
eq "batch reply endpoint" "$(grep -c '^api repos/o/r/pulls/7/comments/[0-9]*/replies --input ' "$GH_LOG")" 3
eq "batch no repo lookup with --repo" "$(grep -c '^repo view' "$GH_LOG" || true)" 0
ok "batch replies and resolves"

# --- without --repo the repository comes from gh repo view ---
reset; run 7 "$work/batch.json"
eq "repo lookup exit" "$rc" 0
eq "repo lookup used" "$(grep -c '^api repos/o/r/pulls/7/' "$GH_LOG")" 3
ok "repo resolved from gh"

# --- an invalid file sends nothing ---
bad() { # <case name> <json text> <expected stderr fragment>
  reset; printf '%s' "$2" > "$work/bad.json"; run 7 "$work/bad.json" --repo o/r
  eq "$1 exit" "$rc" 2
  eq "$1 nothing sent" "$(wc -l < "$GH_LOG" | tr -d ' ')" 0
  grep -q "$3" "$work/stderr" || fail "$1: stderr lacks '$3': $(cat "$work/stderr")"
  eq "$1 no stdout" "$out" ""
}
bad "non-numeric id" '[{"comment_id":111,"thread":"PRRT_a","body":"x","resolve":true},{"comment_id":"12a","thread":null,"body":"x","resolve":false}]' 'item 1: comment_id must be a number'
bad "empty body" '[{"comment_id":111,"thread":"PRRT_a","body":"  \n","resolve":true}]' 'item 0: body must be a non-empty string'
bad "missing body" '[{"comment_id":111,"thread":"PRRT_a","resolve":true}]' 'item 0: body must be a non-empty string'
bad "resolve without thread" '[{"comment_id":111,"thread":null,"body":"x","resolve":true}]' 'item 0: resolve is true but thread is null'
bad "resolve not boolean" '[{"comment_id":111,"thread":"PRRT_a","body":"x","resolve":"yes"}]' 'item 0: resolve must be true or false'
bad "thread not an id" '[{"comment_id":111,"thread":"PRRT_a\"}) { x }","body":"x","resolve":true}]' 'item 0: thread must be a thread id'
bad "not an array" '{"comment_id":111,"body":"x"}' 'must hold a JSON array'
bad "empty array" '[]' 'array is empty'
bad "not JSON" '[{"comment_id":' 'invalid JSON'
ok "invalid file exits 2 with nothing sent"

reset; run 7 "$work/missing.json" --repo o/r
eq "missing file exit" "$rc" 2
reset; run; eq "no args exit" "$rc" 2
reset; run abc "$work/batch.json"; eq "bad pr exit" "$rc" 2
reset; run 7 "$work/batch.json" --nope; eq "unknown flag exit" "$rc" 2
eq "usage errors send nothing" "$(wc -l < "$GH_LOG" | tr -d ' ')" 0
ok "usage errors exit 2"

# --- a failed reply is recorded, its thread is not resolved, and the rest still goes ---
jq '.[1].thread = "PRRT_b" | .[1].resolve = true' "$work/batch.json" > "$work/batch2.json"
reset; GH_FAIL='comments/222/replies' run 7 "$work/batch2.json" --repo o/r
eq "failed reply exit" "$rc" 1
eq "failed reply rows" "$(echo "$out" | jq -c '[.replies[] | [.comment_id, .reply_url != null, .resolved, .error != null]]')" '[[111,true,true,false],[222,false,false,true],[3790734403,true,true,false]]'
echo "$out" | jq -e '.replies[1].error | test("reply failed: HTTP 403")' >/dev/null || fail "failed reply: error text"
eq "failed reply thread left open" "$(tr '\n' ' ' < "$GH_FIX/resolved-threads")" 'PRRT_a PRRT_c '
ok "failed reply continues and exits 1"

# --- a failed resolve keeps the reply url and reports the error ---
reset; GH_FAIL='resolveReviewThread' run 7 "$work/batch.json" --repo o/r
eq "failed resolve exit" "$rc" 1
eq "failed resolve rows" "$(echo "$out" | jq -c '[.replies[] | [.reply_url != null, .resolved, .error != null]]')" '[[true,false,true],[true,false,false],[true,false,true]]'
ok "failed resolve is recorded"

# --- a resolve that returns nothing is an error, not a success ---
reset; echo '{"data":{"resolveReviewThread":null}}' > "$GH_FIX/resolve.json"; run 7 "$work/batch.json" --repo o/r
eq "empty resolve exit" "$rc" 1
echo "$out" | jq -e '.replies[0] | .resolved == false and (.error | test("stale thread id"))' >/dev/null || fail "empty resolve: row"
ok "empty resolve is an error"

# --- a failing thread re-query reads as not checked, never as zero ---
reset; GH_FAIL='reviewThreads' run 7 "$work/batch.json" --repo o/r
eq "failed count exit" "$rc" 0
eq "failed count is null" "$(echo "$out" | jq -c '.threads_open')" null
grep -q 'threads_open is not checked' "$work/stderr" || fail "failed count: stderr"
ok "failed thread re-query gives null"
