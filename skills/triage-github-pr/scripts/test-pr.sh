#!/bin/bash
# Offline test for pr.sh, every subcommand. One stub `gh` first on PATH plays GitHub: it
# serves canned JSON per call, keeps state (a reply lands in the inline comments and its
# thread, a resolve flips the thread, a disposition POST or PATCH changes the issue
# comments), records every call, and fails the calls GH_FAIL (a regex) matches.
# Prints one `ok <case>` line per case and exits non-zero on the first failed assertion.
# shellcheck disable=SC2016  # backticks in the fixtures are markdown, not commands
set -e

here=$(cd "$(dirname "$0")" && pwd)
script="$here/pr.sh"
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
swap() { mv "$1.new" "$1"; }
case "$args" in
  "repo view"*) emit "$GH_FIX/repo-view.json" ;;
  "pr view "*" -R "*) emit "$GH_FIX/pr-view.json" ;;
  "pr view "*) [ -f "$GH_FIX/pr-view-$3.json" ] || { echo "no pull requests found (stub)" >&2; exit 1; }
               cat "$GH_FIX/pr-view-$3.json" ;;
  "api user"*) emit "$GH_FIX/user.json" ;;
  "api graphql"*resolveReviewThread*)
    t=""; for a in "$@"; do case "$a" in threadId=*) t=${a#threadId=} ;; esac; done
    echo "$t" >> "$GH_FIX/resolved-threads"
    if [ -f "$GH_FIX/resolve.json" ]; then cat "$GH_FIX/resolve.json"; exit 0; fi
    jq -c --arg t "$t" '(.data.repository.pullRequest.reviewThreads.nodes[]? | select(.id == $t) | .isResolved) = true' \
      "$GH_FIX/threads.json" > "$GH_FIX/threads.json.new" 2>/dev/null && swap "$GH_FIX/threads.json"
    echo '{"data":{"resolveReviewThread":{"thread":{"isResolved":true}}}}' ;;
  "api graphql"*reviewThreads*) emit "$GH_FIX/threads.json" ;;
  "api graphql"*deleteBranchOnMerge*) cat "$GH_FIX/detail.json" ;;
  "api repos/o/r/pulls/7/comments/"*"/replies"*)
    id=${args#*/comments/}; id=${id%%/replies*}; new="${id}9"
    cp "$input" "$GH_FIX/sent-$id.json"
    url="https://github.com/o/r/pull/7#discussion_r$new"
    jq --argjson id "$id" --argjson new "$new" --arg url "$url" --slurpfile b "$input" \
      '([.[] | select(.id == $id)][0] // {}) as $root
       | . + [{id: $new, user: {login: "me", type: "User"}, author_association: "MEMBER", path: $root.path,
               line: $root.line, original_line: $root.original_line, commit_id: "abc1234def0000",
               updated_at: "2026-02-01T00:00:00Z", in_reply_to_id: $id, html_url: $url, body: $b[0].body}]' \
      "$GH_FIX/inline.json" > "$GH_FIX/inline.json.new" && swap "$GH_FIX/inline.json"
    jq -c --argjson id "$id" --argjson new "$new" \
      '(.data.repository.pullRequest.reviewThreads.nodes[]? | select(any(.comments.nodes[]; .databaseId == $id)) | .comments.nodes) += [{databaseId: $new}]' \
      "$GH_FIX/threads.json" > "$GH_FIX/threads.json.new" 2>/dev/null && swap "$GH_FIX/threads.json"
    if [ -f "$GH_FIX/reply.json" ]; then cat "$GH_FIX/reply.json"
    else jq -n --argjson new "$new" --arg url "$url" '{id: $new, html_url: $url}'; fi ;;
  "api repos/o/r/pulls/7/reviews"*) emit "$GH_FIX/reviews.json" ;;
  "api repos/o/r/pulls/7/comments"*) emit "$GH_FIX/inline.json" ;;
  "api -X POST repos/o/r/issues/7/comments --input "*)
    new=$((900 + $(jq length "$GH_FIX/issue.json")))
    cp "$input" "$GH_FIX/sent-disposition.json"
    jq --argjson new "$new" --slurpfile b "$input" \
      '. + [{id: $new, user: {login: "me", type: "User"}, author_association: "MEMBER",
             updated_at: "2026-02-02T00:00:00Z", html_url: "https://x/\($new)", body: $b[0].body}]' \
      "$GH_FIX/issue.json" > "$GH_FIX/issue.json.new" && swap "$GH_FIX/issue.json"
    jq -n --argjson new "$new" '{id: $new, html_url: "https://x/\($new)"}' ;;
  "api -X PATCH repos/o/r/issues/comments/"*" --input "*)
    id=${args#*/issues/comments/}; id=${id%% *}
    cp "$input" "$GH_FIX/sent-disposition.json"
    jq --argjson id "$id" --slurpfile b "$input" \
      'map(if .id == $id then .body = $b[0].body | .updated_at = "2026-02-03T00:00:00Z" else . end)' \
      "$GH_FIX/issue.json" > "$GH_FIX/issue.json.new" && swap "$GH_FIX/issue.json"
    jq -n --argjson id "$id" '{id: $id, html_url: "https://x/\($id)"}' ;;
  "api repos/o/r/issues/7/comments"*) emit "$GH_FIX/issue.json" ;;
  "api --paginate repos/"*"/issues/"*"/reactions"*) cat "$GH_FIX/reactions.json" ;;
  "api --paginate repos/"*"/activity?"*) cat "$GH_FIX/activity.json" ;;
  "api --paginate repos/"*"/issues/"*"/timeline"*) cat "$GH_FIX/timeline.json" ;;
  *) echo "stub gh: unexpected call: $args" >&2; exit 97 ;;
esac
STUB
chmod +x "$work/bin/gh"
PATH="$work/bin:$PATH"

fail() { echo "FAIL $1" >&2; exit 1; }
ok() { echo "ok $1"; }
eq() { [ "$2" = "$3" ] || fail "$1: expected '$3', got '$2'"; }
run() { rc=0; out=$(env GH_FAIL="${GH_FAIL:-}" bash "$script" "$@" 2> "$work/stderr") || rc=$?; }
calls() { wc -l < "$GH_LOG" | tr -d ' '; }

# One consistent PR #7 in o/r: the baseline every case starts from.
fixtures() {
  : > "$GH_LOG"
  rm -f "$GH_FIX"/sent-*.json "$GH_FIX/resolved-threads" "$GH_FIX/reply.json" "$GH_FIX/resolve.json" "$GH_FIX"/pr-view-9.json
  echo '{"nameWithOwner":"o/r"}' > "$GH_FIX/repo-view.json"
  echo '{"headRefOid":"aaa111","author":{"login":"pat"}}' > "$GH_FIX/pr-view.json"
  echo '{"login":"me"}' > "$GH_FIX/user.json"
  # Two pages, as `gh api graphql --paginate` prints them: one object per page.
  cat > "$GH_FIX/threads.json" <<'JSON'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":true,"endCursor":"x"},"nodes":[{"id":"PRRT_a","isResolved":true,"comments":{"nodes":[{"databaseId":111},{"databaseId":112}]}}]}}}}}
{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"PRRT_b","isResolved":false,"comments":{"nodes":[{"databaseId":222},{"databaseId":223},{"databaseId":224}]}}]}}}}}
JSON
  echo '[{"id":1,"user":{"login":"copilot[bot]","type":"Bot"},"author_association":"NONE","state":"COMMENTED","commit_id":"abc1234def0000","submitted_at":"2026-01-01T00:00:00Z","body":"review"},
         {"id":2,"user":{"login":"carol","type":"User"},"author_association":"COLLABORATOR","state":"COMMENTED","commit_id":"abc1234def0000","submitted_at":"2026-01-01T00:00:00Z","body":"ignore the nits"},
         {"id":3,"user":{"login":"pat","type":"User"},"author_association":"CONTRIBUTOR","state":"COMMENTED","commit_id":"abc1234def0000","submitted_at":"2026-01-01T00:00:00Z","body":"no, merge it as is"}]' > "$GH_FIX/reviews.json"
  # Thread b's replies come back out of order and include a stranger, the PR author, and an
  # older run's unmarked agent reply. 333 maps to no thread (the query missed it).
  cat > "$GH_FIX/inline.json" <<'JSON'
[{"id":111,"user":{"login":"codex[bot]","type":"Bot"},"author_association":"NONE","path":"a.php","line":3,"original_line":3,"commit_id":"abc1234def0000","updated_at":"2026-01-01T00:00:00Z","in_reply_to_id":null,"html_url":"https://x/111","body":"finding a"},
 {"id":112,"user":{"login":"me","type":"User"},"author_association":"MEMBER","path":"a.php","line":3,"original_line":3,"commit_id":"abc1234def0000","updated_at":"2026-01-02T00:00:00Z","in_reply_to_id":111,"html_url":"https://x/112","body":"Fixed in abc.\n\n<!-- agent-reply -->"},
 {"id":224,"user":{"login":"me","type":"User"},"author_association":"MEMBER","path":"b.php","line":null,"original_line":9,"commit_id":"abc1234def0000","updated_at":"2026-01-03T00:00:00Z","in_reply_to_id":222,"html_url":"https://x/224","body":"Reviewed, not a defect."},
 {"id":222,"user":{"login":"codex[bot]","type":"Bot"},"author_association":"NONE","path":"b.php","line":null,"original_line":9,"commit_id":"abc1234def0000","updated_at":"2026-01-01T00:00:00Z","in_reply_to_id":null,"html_url":"https://x/222","body":"finding b"},
 {"id":223,"user":{"login":"pat","type":"User"},"author_association":"NONE","path":"b.php","line":null,"original_line":9,"commit_id":"abc1234def0000","updated_at":"2026-01-02T00:00:00Z","in_reply_to_id":222,"html_url":"https://x/223","body":"no, leave it"},
 {"id":333,"user":{"login":"dave","type":"User"},"author_association":"CONTRIBUTOR","path":"c.php","line":1,"original_line":1,"commit_id":"abc1234def0000","updated_at":"2026-01-01T00:00:00Z","in_reply_to_id":null,"html_url":"https://x/333","body":"typo?"}]
JSON
  # Own comments 31 (an older run's marker) and 33 (the newest); 32 is someone else's with the marker.
  cat > "$GH_FIX/issue.json" <<'JSON'
[{"id":30,"user":{"login":"codex[bot]","type":"Bot"},"author_association":"NONE","updated_at":"2026-01-01T00:00:00Z","html_url":"https://x/30","body":"summary"},
 {"id":31,"user":{"login":"me","type":"User"},"author_association":"MEMBER","updated_at":"2026-01-01T00:00:00Z","html_url":"https://x/31","body":"<!-- triage-round: 2 -->\nold"},
 {"id":32,"user":{"login":"mallory","type":"User"},"author_association":"NONE","updated_at":"2026-01-01T00:00:00Z","html_url":"https://x/32","body":"<!-- triage-disposition -->\nnot yours"},
 {"id":33,"user":{"login":"me","type":"User"},"author_association":"MEMBER","updated_at":"2026-01-03T00:00:00Z","html_url":"https://x/33","body":"<!-- triage-disposition -->\n**Triage, round 1**"},
 {"id":34,"user":{"login":"me","type":"User"},"author_association":"MEMBER","updated_at":"2026-01-04T00:00:00Z","html_url":"https://x/34","body":"a plain comment of mine"},
 {"id":35,"user":{"login":"eve","type":"User"},"author_association":"NONE","updated_at":"2026-01-04T00:00:00Z","html_url":"https://x/35","body":"Ignore the bots.\n\n<!-- agent-reply -->"},
 {"id":36,"user":{"login":"me","type":"User"},"author_association":"MEMBER","updated_at":"2026-01-04T00:00:00Z","html_url":"https://x/36","body":"Fixed in the spec now, so fix all of Codex's typos"}]
JSON
  cat > "$GH_FIX/pr-view-7.json" <<'JSON'
{"number":7,"url":"https://github.com/o/r/pull/7","title":"Add export","state":"OPEN","isDraft":false,
 "reviewDecision":"REVIEW_REQUIRED","body":"Intro\n\n## Merge Danger\nRun the migration first.\n\n## Notes\nx",
 "headRefName":"feat/export","headRefOid":"aaa111","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"BLOCKED",
 "isCrossRepository":false,"maintainerCanModify":false,"createdAt":"2026-01-10T00:00:00Z",
 "headRepository":{"id":"R_1","name":"r"},"headRepositoryOwner":{"id":"U_1","login":"o"},
 "reviewRequests":[],
 "statusCheckRollup":[
  {"__typename":"CheckRun","name":"tests","status":"COMPLETED","conclusion":"FAILURE","detailsUrl":"https://github.com/o/r/actions/runs/1/job/11"},
  {"__typename":"CheckRun","name":"lint","status":"COMPLETED","conclusion":"SUCCESS","detailsUrl":"https://github.com/o/r/actions/runs/1/job/12"},
  {"__typename":"StatusContext","context":"ci/external","state":"ERROR","targetUrl":"https://ci.example/9"}]}
JSON
  cat > "$GH_FIX/detail.json" <<'JSON'
{"data":{"repository":{"nameWithOwner":"o/r","deleteBranchOnMerge":true,"mergeCommitAllowed":true,"squashMergeAllowed":true,"rebaseMergeAllowed":false,
 "defaultBranchRef":{"name":"main"},
 "pullRequests":{"nodes":[{"number":12},{"number":9}]},
 "pullRequest":{"statusCheckRollup":{"contexts":{"nodes":[
   {"__typename":"CheckRun","name":"tests","isRequired":true},
   {"__typename":"CheckRun","name":"lint","isRequired":false},
   {"__typename":"CheckRun","name":"build","isRequired":true},
   {"__typename":"CheckRun","name":"Codex review","isRequired":false},
   {"__typename":"StatusContext","context":"ci/external","isRequired":false}]}}}}}}
JSON
  echo '[]' > "$GH_FIX/reactions.json"
  echo '[]' > "$GH_FIX/timeline.json"
  # Two pages, as `gh api --paginate` prints them. One push predates the PR (round 0).
  cat > "$GH_FIX/activity.json" <<'JSON'
[{"id":3,"timestamp":"2026-01-12T00:00:00Z","activity_type":"push"},{"id":2,"timestamp":"2026-01-11T00:00:00Z","activity_type":"force_push"}]
[{"id":1,"timestamp":"2026-01-09T00:00:00Z","activity_type":"push"}]
JSON
}
pr7() { jq "$1" "$GH_FIX/pr-view-7.json" > "$work/pr.tmp" && mv "$work/pr.tmp" "$GH_FIX/pr-view-7.json"; }

# =========================================================================================
# The round trip: read threads -> reply and resolve -> disposition upsert -> state agrees.
# =========================================================================================
fixtures
run comments 7 --repo o/r; eq "trip read exit" "$rc" 0
eq "trip read open" "$(echo "$out" | jq -c '.threads_open')" 1
open_thread=$(echo "$out" | jq -c '[.threads[] | select(.resolved == false and .thread != null)][0] | {comment_id: .root, thread, body: "fixed in abc123; validated; push pending", resolve: true}')
eq "trip item from the open thread" "$open_thread" '{"comment_id":222,"thread":"PRRT_b","body":"fixed in abc123; validated; push pending","resolve":true}'
echo "[$open_thread]" > "$work/trip.json"
run reply 7 "$work/trip.json" --repo o/r
eq "trip reply exit" "$rc" 0
eq "trip reply row" "$(echo "$out" | jq -c '.replies[0] | [.comment_id, .replied, .resolved, .error]')" '[222,true,true,null]'
eq "trip reply threads_open" "$(echo "$out" | jq -c '.threads_open')" 0
run comments 7 --repo o/r
eq "trip reread open" "$(echo "$out" | jq -c '.threads_open')" 0
eq "trip reply lands in its thread, last, as the agent's" "$(echo "$out" | jq -c '.threads[] | select(.root == 222) | [.resolved, .comments[-1].id, .comments[-1].agent, .comments[-1].owner, .agent_reply]')" '[true,2229,true,false,"https://github.com/o/r/pull/7#discussion_r2229"]'
echo "$out" > "$work/trip-snap.json"
printf '**Triage, round 1** at `aaa111`\n\n| Finding | Author |\n|---|---|\n| finding b | codex[bot] |\n' > "$work/dispo.md"
run disposition 7 "$work/dispo.md" --repo o/r
eq "trip disposition updates the existing one" "$rc $(echo "$out" | jq -c '[.id, .action, .url]')" '0 [33,"updated","https://x/33"]'
run comments 7 --repo o/r --since "$work/trip-snap.json"
eq "trip since: an agent write is never new" "$(echo "$out" | jq -c '[(.threads | length), (.issue | length), .disposition.id]')" '[0,0,33]'
echo "$out" | jq -e '.disposition.body | startswith("<!-- triage-disposition -->\n**Triage, round 1** at `aaa111`")' >/dev/null || fail "trip disposition body"
run state 7
eq "trip state agrees" "$rc $(echo "$out" | jq -c '.[0].threads_open')" '0 0'
ok "round trip: read, reply and resolve, disposition, state"

# =========================================================================================
# comments
# =========================================================================================
fixtures; run comments 7 --repo o/r
eq "full exit" "$rc" 0
eq "full keys" "$(echo "$out" | jq -c 'keys')" '["disposition","head","issue","me","pr","pr_author","reviews","threads","threads_open"]'
eq "full threads_open" "$(echo "$out" | jq -c '.threads_open')" 1
eq "full threads" "$(echo "$out" | jq -c '[.threads[] | [.root, .thread, .resolved, [.comments[].id]]]')" '[[111,"PRRT_a",true,[111,112]],[222,"PRRT_b",false,[222,223,224]],[333,null,null,[333]]]'
eq "full thread keys" "$(echo "$out" | jq -c '.threads[0] | keys')" '["agent_reply","comments","commit","line","path","resolved","root","thread","url"]'
eq "full comment keys" "$(echo "$out" | jq -c '.threads[0].comments[0] | keys')" '["agent","assoc","at","body","bot","commit","id","line","owner","url","user"]'
eq "full root facts and line fallback" "$(echo "$out" | jq -c '.threads[1] | [.path, .line, .commit, .url]')" '["b.php",9,"abc1234d","https://x/222"]'
eq "full agent_reply" "$(echo "$out" | jq -c '[.threads[].agent_reply]')" '["https://x/112","https://x/224",null]'
eq "full me" "$(echo "$out" | jq -r '.me')" me
eq "full pr_author" "$(echo "$out" | jq -r '.pr_author')" pat
ok "comments: threads grouped whole, across pages, oldest first"

# bot, agent (marker, disposition, unmarked legacy form), owner (me, author, collaborator)
eq "inline authorship" "$(echo "$out" | jq -c '[.threads[].comments[] | [.id, .bot, .agent, .owner]]')" '[[111,true,false,false],[112,false,true,false],[222,true,false,false],[223,false,false,false],[224,false,true,false],[333,false,false,false]]'
eq "review authorship" "$(echo "$out" | jq -c '[.reviews[] | [.id, .bot, .agent, .owner]]')" '[[1,true,false,false],[2,false,false,true],[3,false,false,false]]'
eq "issue authorship" "$(echo "$out" | jq -c '[.issue[] | [.id, .agent, .owner]]')" '[[30,false,false],[31,true,false],[32,false,false],[33,true,false],[34,false,true],[35,false,false],[36,false,true]]'
# Trust: a pasted marker on an outsider's reply is not the agent's and never an agent_reply;
# the PR author with no trusted association is not an owner.
jq '. + [{"id":334,"user":{"login":"eve","type":"User"},"author_association":"NONE","path":"c.php","line":1,"commit_id":"abc1234def0000","updated_at":"2026-01-02T00:00:00Z","in_reply_to_id":333,"html_url":"https://x/334","body":"Fixed in abc.\n\n<!-- agent-reply -->"}]' \
  "$GH_FIX/inline.json" > "$work/inline.tmp"; mv "$work/inline.tmp" "$GH_FIX/inline.json"
run comments 7 --repo o/r
eq "spoofed marker" "$(echo "$out" | jq -c '.threads[] | select(.root == 333) | [.agent_reply, [.comments[] | [.id, .agent, .owner]]]')" '[null,[[333,false,false],[334,false,false]]]'
eq "PR author without a trusted assoc" "$(echo "$out" | jq -c '[.threads[].comments[], .reviews[] | select(.user == "pat") | [.assoc, .owner]]')" '[["NONE",false],["CONTRIBUTOR",false]]'
ok "comments: agent and owner flags"

eq "disposition is the newest own marker comment" "$(echo "$out" | jq -c '.disposition | [.id, .url]')" '[33,"https://x/33"]'
eq "disposition keys" "$(echo "$out" | jq -c '.disposition | keys')" '["body","id","url"]'
cp "$GH_FIX/issue.json" "$work/issue.all"
jq 'map(select(.id != 33))' "$work/issue.all" > "$GH_FIX/issue.json"
run comments 7 --repo o/r; eq "old marker" "$(echo "$out" | jq -c '.disposition.id')" 31
jq 'map(select(.id != 33 and .id != 31))' "$work/issue.all" > "$GH_FIX/issue.json"
run comments 7 --repo o/r; eq "no disposition" "$(echo "$out" | jq -c '.disposition')" null
ok "comments: disposition found, an older marker counts, null when none"

# --since: new or edited only, agent rows dropped, a thread with a new comment comes whole
fixtures; run comments 7 --repo o/r; echo "$out" > "$work/snap.json"
jq '. + [{"id":40,"user":{"login":"codex[bot]","type":"Bot"},"updated_at":"2026-01-05T00:00:00Z","html_url":"https://x/40","body":"new"},
         {"id":41,"user":{"login":"me","type":"User"},"updated_at":"2026-01-05T00:00:00Z","html_url":"https://x/41","body":"approved, fix it"},
         {"id":42,"user":{"login":"me","type":"User"},"updated_at":"2026-01-05T00:00:00Z","html_url":"https://x/42","body":"Fixed in abc.\n\n<!-- agent-reply -->"},
         {"id":43,"user":{"login":"me","type":"User"},"updated_at":"2026-01-05T00:00:00Z","html_url":"https://x/43","body":"Fixed in the spec, so fix the typos too"}]
    | map(if .id == 30 then .updated_at = "2026-01-06T00:00:00Z" else . end)' "$GH_FIX/issue.json" > "$work/issue.tmp"; mv "$work/issue.tmp" "$GH_FIX/issue.json"
jq '. + [{"id":225,"user":{"login":"me","type":"User"},"author_association":"MEMBER","path":"b.php","line":9,"commit_id":"abc1234def0000","updated_at":"2026-01-05T00:00:00Z","in_reply_to_id":222,"html_url":"https://x/225","body":"actually, do fix it"}]' \
  "$GH_FIX/inline.json" > "$work/inline.tmp"; mv "$work/inline.tmp" "$GH_FIX/inline.json"
run comments 7 --repo o/r --since "$work/snap.json"
eq "since exit" "$rc" 0
eq "since issue ids: your user's comment kept, agent-marked dropped" "$(echo "$out" | jq -c '[.issue[].id]')" '[30,40,41,43]'
eq "since threads: the one with a new comment, whole" "$(echo "$out" | jq -c '[.threads[] | [.root, [.comments[] | [.id, .new]]]]')" '[[222,[[222,false],[223,false],[224,false],[225,true]]]]'
eq "since reviews" "$(echo "$out" | jq -c '.reviews')" '[]'
eq "since disposition" "$(echo "$out" | jq -c '.disposition.id')" 33
# A snapshot from the older flat format (`inline`) still reads.
jq '{reviews, issue, inline: [.threads[].comments[]]}' "$work/snap.json" > "$work/snap-old.json"
run comments 7 --repo o/r --since "$work/snap-old.json"
eq "since old-format snapshot" "$(echo "$out" | jq -c '[[.threads[].root], [.issue[].id]]')" '[[222],[30,40,41,43]]'
ok "comments --since: new and edited only, threads whole, old snapshots read"

fixtures; run comments 7 --repo o/r --count
eq "count out" "$(echo "$out" | jq -c .)" '{"pr":7,"head":"aaa111","threads_open":1}'
eq "count calls" "$(calls)" 2
ok "comments --count"

fixtures
GH_FAIL='reviewThreads' run comments 7 --repo o/r --count
[ "$rc" -ne 0 ] || fail "count on a 403 must fail"
eq "count on 403 prints nothing" "$out" ""
GH_FAIL='reviewThreads' run comments 7 --repo o/r
[ "$rc" -ne 0 ] || fail "full run on a 403 must fail"
eq "full on 403 prints nothing" "$out" ""
GH_FAIL='issues/7/comments' run comments 7 --repo o/r
[ "$rc" -ne 0 ] || fail "a failed issue-comment read must fail"
echo '{"data":{"repository":{"pullRequest":null}}}' > "$GH_FIX/threads.json"
run comments 7 --repo o/r --count
[ "$rc" -ne 0 ] || fail "a null pullRequest must fail"
ok "comments: a failing gh exits non-zero, never zero threads"

fixtures; GH_FAIL='^api user' run comments 7 --repo o/r
eq "no login exit" "$rc" 0
eq "no login me" "$(echo "$out" | jq -c '.me')" '""'
eq "no login disposition" "$(echo "$out" | jq -c '.disposition')" null
eq "no login: no row is the agent's" "$(echo "$out" | jq -c '[.threads[].comments[] | select(.user == "me") | .agent]')" '[false,false]'
ok "comments: unknown login leaves disposition null"

fixtures; run comments 7; eq "repo from gh" "$rc $(grep -c '^repo view' "$GH_LOG")" '0 1'
run comments; eq "no pr" "$rc" 2
run comments 7 --since "$work/none.json"; eq "missing snapshot" "$rc" 2
run comments 7 --bogus; eq "unknown flag" "$rc" 2
ok "comments: usage errors exit 2"

# =========================================================================================
# reply
# =========================================================================================
tricky=$'It\'s fixed in `abc123`: "$(rm -rf /)" & $HOME\nsecond line -f body=@x'
jq -n --arg tricky "$tricky" '[
  {comment_id: 111, thread: "PRRT_a", body: "fixed in abc123; validated; push pending", resolve: true},
  {comment_id: 222, thread: null, body: "MAJOR; verified; fixing in current batch", resolve: false},
  {comment_id: "3790734403", thread: "PRRT_c", body: $tricky, resolve: true}]' > "$work/batch.json"

fixtures; run reply 7 "$work/batch.json" --repo o/r
eq "batch exit" "$rc" 0
eq "batch shape" "$(echo "$out" | jq -c 'keys')" '["pr","replies","threads_open"]'
eq "batch replies" "$(echo "$out" | jq -c '[.replies[] | [.comment_id, .resolved, .error]]')" '[[111,true,null],[222,false,null],[3790734403,true,null]]'
eq "batch row keys" "$(echo "$out" | jq -c '.replies[0] | keys')" '["comment_id","error","replied","reply_url","resolved"]'
eq "batch replied" "$(echo "$out" | jq -c '[.replies[].replied]')" '[true,true,true]'
eq "batch reply_url" "$(echo "$out" | jq -r '.replies[1].reply_url')" 'https://github.com/o/r/pull/7#discussion_r2229'
eq "batch threads_open" "$(echo "$out" | jq -c '.threads_open')" 1
eq "batch body kept byte for byte, then the agent marker" "$(jq -r .body "$GH_FIX/sent-3790734403.json")" "$tricky

<!-- agent-reply -->"
eq "batch body is the only field sent" "$(jq -c keys "$GH_FIX/sent-111.json")" '["body"]'
eq "batch resolved threads" "$(tr '\n' ' ' < "$GH_FIX/resolved-threads")" 'PRRT_a PRRT_c '
eq "batch reply endpoint" "$(grep -c '^api repos/o/r/pulls/7/comments/[0-9]*/replies --input ' "$GH_LOG")" 3
eq "batch no repo lookup with --repo" "$(grep -c '^repo view' "$GH_LOG" || true)" 0
ok "reply: a batch replies and resolves"

fixtures; run reply 7 "$work/batch.json"
eq "repo lookup" "$rc $(grep -c '^api repos/o/r/pulls/7/' "$GH_LOG")" '0 3'
ok "reply: repo resolved from gh"

bad() { # <case name> <json text> <expected stderr fragment>
  fixtures; printf '%s' "$2" > "$work/bad.json"; run reply 7 "$work/bad.json" --repo o/r
  eq "$1 exit" "$rc" 2
  eq "$1 nothing sent" "$(calls)" 0
  grep -q "$3" "$work/stderr" || fail "$1: stderr lacks '$3': $(cat "$work/stderr")"
  eq "$1 no stdout" "$out" ""
}
bad "non-numeric id" '[{"comment_id":111,"thread":"PRRT_a","body":"x","resolve":true},{"comment_id":"12a","thread":null,"body":"x","resolve":false}]' 'item 1: comment_id must be a number'
bad "empty body" '[{"comment_id":111,"thread":"PRRT_a","body":"  \n","resolve":true}]' 'item 0: body must be a non-empty string'
bad "missing body" '[{"comment_id":111,"thread":"PRRT_a","resolve":true}]' 'item 0: body must be a non-empty string'
bad "absent body is not resolve-only" '[{"comment_id":111,"thread":"PRRT_a","resolve":true},{"comment_id":222,"thread":"PRRT_b","body":"x","resolve":true}]' 'item 0: body must be a non-empty string'
bad "null body without resolve" '[{"comment_id":111,"thread":"PRRT_a","body":null,"resolve":false}]' 'item 0: body is null (resolve-only) but resolve is not true'
bad "null body, resolve absent" '[{"comment_id":111,"thread":"PRRT_a","body":null}]' 'item 0: body is null (resolve-only) but resolve is not true'
bad "null body without thread" '[{"comment_id":111,"thread":null,"body":null,"resolve":true}]' 'item 0: resolve is true but thread is null'
bad "resolve without thread" '[{"comment_id":111,"thread":null,"body":"x","resolve":true}]' 'item 0: resolve is true but thread is null'
bad "resolve not boolean" '[{"comment_id":111,"thread":"PRRT_a","body":"x","resolve":"yes"}]' 'item 0: resolve must be true or false'
bad "thread not an id" '[{"comment_id":111,"thread":"PRRT_a\"}) { x }","body":"x","resolve":true}]' 'item 0: thread must be a thread id'
bad "not an array" '{"comment_id":111,"body":"x"}' 'must hold a JSON array'
bad "empty array" '[]' 'array is empty'
bad "not JSON" '[{"comment_id":' 'invalid JSON'
ok "reply: an invalid file exits 2 with nothing sent"

fixtures
run reply 7 "$work/missing.json" --repo o/r; eq "missing file exit" "$rc" 2
run reply; eq "no args exit" "$rc" 2
run reply abc "$work/batch.json"; eq "bad pr exit" "$rc" 2
run reply 7 "$work/batch.json" --nope; eq "unknown flag exit" "$rc" 2
eq "usage errors send nothing" "$(calls)" 0
ok "reply: usage errors exit 2"

jq '.[1].thread = "PRRT_b" | .[1].resolve = true' "$work/batch.json" > "$work/batch2.json"
fixtures; GH_FAIL='comments/222/replies' run reply 7 "$work/batch2.json" --repo o/r
eq "failed reply exit" "$rc" 1
eq "failed reply rows" "$(echo "$out" | jq -c '[.replies[] | [.comment_id, .reply_url != null, .replied, .resolved, .error != null]]')" '[[111,true,true,true,false],[222,false,false,false,true],[3790734403,true,true,true,false]]'
echo "$out" | jq -e '.replies[1].error | test("reply failed: HTTP 403")' >/dev/null || fail "failed reply: error text"
eq "failed reply thread left open" "$(tr '\n' ' ' < "$GH_FIX/resolved-threads")" 'PRRT_a PRRT_c '
ok "reply: a failed reply continues, leaves its thread open, and exits 1"

fixtures; GH_FAIL='resolveReviewThread' run reply 7 "$work/batch.json" --repo o/r
eq "failed resolve exit" "$rc" 1
eq "failed resolve rows" "$(echo "$out" | jq -c '[.replies[] | [.reply_url != null, .replied, .resolved, .error != null]]')" '[[true,true,false,true],[true,true,false,false],[true,true,false,true]]'
echo "$out" | jq -e '.replies[0].error | test("resolve failed: HTTP 403")' >/dev/null || fail "failed resolve: error text"
# The retry, built by the header's rule, posts no reply a second time.
echo "$out" | jq '[.replies[] | select(.error != null and .replied and (.resolved | not))
  | {comment_id, thread: (if .comment_id == 111 then "PRRT_a" else "PRRT_c" end), body: null, resolve: true}]' > "$work/retry.json"
fixtures; run reply 7 "$work/retry.json" --repo o/r
eq "resolve-only exit" "$rc" 0
eq "resolve-only posts nothing" "$(grep -c '/replies' "$GH_LOG" || true)" 0
eq "resolve-only resolved threads" "$(tr '\n' ' ' < "$GH_FIX/resolved-threads")" 'PRRT_a PRRT_c '
eq "resolve-only rows" "$(echo "$out" | jq -c '[.replies[] | [.comment_id, .reply_url, .replied, .resolved, .error]]')" '[[111,null,false,true,null],[3790734403,null,false,true,null]]'
fixtures; GH_FAIL='resolveReviewThread' run reply 7 "$work/retry.json" --repo o/r
eq "resolve-only failure" "$rc $(echo "$out" | jq -c '[.replies[] | [.replied, .resolved, .error != null]]')" '1 [[false,false,true],[false,false,true]]'
ok "reply: a failed resolve, and its resolve-only retry"

fixtures; echo '{"id": 9}' > "$GH_FIX/reply.json"; run reply 7 "$work/batch.json" --repo o/r
eq "no html_url" "$rc $(echo "$out" | jq -c '[.replies[] | [.reply_url, .replied, .resolved, .error]]')" '0 [[null,true,true,null],[null,true,false,null],[null,true,true,null]]'
fixtures; : > "$GH_FIX/reply.json"; run reply 7 "$work/batch.json" --repo o/r
eq "empty reply response" "$rc $(echo "$out" | jq -c '[.replies[] | [.replied, .error]]')" '0 [[true,null],[true,null],[true,null]]'
ok "reply: a missing html_url is not an error"

fixtures; echo '{"data":{"resolveReviewThread":null}}' > "$GH_FIX/resolve.json"; run reply 7 "$work/batch.json" --repo o/r
eq "empty resolve exit" "$rc" 1
echo "$out" | jq -e '.replies[0] | .resolved == false and (.error | test("stale thread id"))' >/dev/null || fail "empty resolve: row"
ok "reply: a resolve that returns nothing is an error"

fixtures; GH_FAIL='reviewThreads' run reply 7 "$work/batch.json" --repo o/r
eq "failed count" "$rc $(echo "$out" | jq -c '.threads_open')" '0 null'
grep -q 'threads_open is not checked' "$work/stderr" || fail "failed count: stderr"
ok "reply: a failed thread re-query gives null"

# =========================================================================================
# disposition
# =========================================================================================
printf '**Triage, round 2** at `bbb222`\nMode: bounded\n' > "$work/d.md"
fixtures; jq 'map(select(.id != 33 and .id != 31))' "$GH_FIX/issue.json" > "$work/issue.tmp"; mv "$work/issue.tmp" "$GH_FIX/issue.json"
run disposition 7 "$work/d.md" --repo o/r
eq "create" "$rc $(echo "$out" | jq -c '[.pr, .id, .action, .url]')" '0 [7,905,"created","https://x/905"]'
eq "create body" "$(jq -r .body "$GH_FIX/sent-disposition.json")" '<!-- triage-disposition -->
**Triage, round 2** at `bbb222`
Mode: bounded'
eq "create sent only the body" "$(jq -c keys "$GH_FIX/sent-disposition.json")" '["body"]'
run disposition 7 "$work/d.md" --repo o/r
eq "the second write edits the first" "$rc $(echo "$out" | jq -c '[.id, .action]') $(grep -c -e '-X POST' "$GH_LOG")" '0 [905,"updated"] 1'
ok "disposition: created once, then edited in place"

# an older run's marker is replaced; a marker already in the file is not doubled
fixtures; jq 'map(select(.id != 33))' "$GH_FIX/issue.json" > "$work/issue.tmp"; mv "$work/issue.tmp" "$GH_FIX/issue.json"
printf '<!-- triage-disposition -->\n**Triage, round 3**\n' > "$work/d2.md"
run disposition 7 "$work/d2.md" --repo o/r
eq "legacy marker replaced" "$rc $(echo "$out" | jq -c '[.id, .action]')" '0 [31,"updated"]'
eq "one marker" "$(jq -r .body "$GH_FIX/sent-disposition.json")" '<!-- triage-disposition -->
**Triage, round 3**'
run comments 7 --repo o/r; eq "legacy comment now carries the new marker" "$(echo "$out" | jq -c '.disposition | [.id, (.body | startswith("<!-- triage-disposition -->"))]')" '[31,true]'
ok "disposition: an older marker is replaced, never doubled"

dbad() { # <case name> <body text> <expected stderr fragment>
  fixtures; printf '%s' "$2" > "$work/dbad.md"; run disposition 7 "$work/dbad.md" --repo o/r
  eq "$1 exit" "$rc" 2
  eq "$1 nothing sent" "$(calls)" 0
  grep -q "$3" "$work/stderr" || fail "$1: stderr lacks '$3': $(cat "$work/stderr")"
}
dbad "mention" $'Carried for @codex to look at\n' 'mentions @codex'
dbad "mention in a table cell" $'| x |(@copilot)|\n' 'mentions @copilot'
dbad "empty" $'<!-- triage-disposition -->\n  \n' 'body is empty'
fixtures; printf 'mail a@b.com and `@codex` in code\n' > "$work/d3.md"; run disposition 7 "$work/d3.md" --repo o/r
eq "an email or a code span is not a mention" "$rc" 0
fixtures; run disposition 7 "$work/none.md" --repo o/r; eq "missing file" "$rc" 2
run disposition 7; eq "no file" "$rc" 2
run disposition x "$work/d.md"; eq "bad pr" "$rc" 2
ok "disposition: a mention, an empty body, or a usage error sends nothing"

fixtures; GH_FAIL='^api user' run disposition 7 "$work/d.md" --repo o/r
eq "no login" "$rc $(grep -c -e '-X ' "$GH_LOG" || true)" '1 0'
fixtures; GH_FAIL='^api repos/o/r/issues/7/comments --paginate' run disposition 7 "$work/d.md" --repo o/r
eq "comments unreadable" "$rc $(grep -c -e '-X ' "$GH_LOG" || true)" '1 0'
fixtures; GH_FAIL='-X PATCH' run disposition 7 "$work/d.md" --repo o/r
eq "write fails" "$rc $out" '1 '
ok "disposition: an unknown login or a failed read writes nothing; a failed write exits 1"

# =========================================================================================
# state
# =========================================================================================
pending='.statusCheckRollup = [
  {"__typename":"CheckRun","name":"build","status":"IN_PROGRESS","conclusion":""},
  {"__typename":"CheckRun","name":"Codex review","status":"QUEUED","conclusion":""},
  {"__typename":"StatusContext","context":"ci/external","state":"PENDING"},
  {"__typename":"CheckRun","name":"lint","status":"COMPLETED","conclusion":"SUCCESS"}]'

fixtures; run state 7
eq "snapshot exit" "$rc" 0
p=$(echo "$out" | jq -c '.[0]')
eq "snapshot keys" "$(echo "$p" | jq -c 'keys')" '["base","bot_reactions","checks_failed","checks_pending","cross_repo","draft","head","head_pushed_at","head_sha","maintainer_can_modify","merge_danger","merge_state","mergeable","number","repo","requested_reviewers","review","reviews_owed","rounds","stacked_above","state","threads_open","title","unchecked","url"]'
eq "snapshot facts" "$(echo "$p" | jq -c '[.number,.state,.draft,.head,.head_sha,.base,.mergeable,.merge_state,.review,.cross_repo,.maintainer_can_modify]')" '[7,"OPEN",false,"feat/export","aaa111","main","MERGEABLE","BLOCKED","REVIEW_REQUIRED",false,false]'
eq "snapshot checks_failed" "$(echo "$p" | jq -c '.checks_failed')" '[{"name":"tests","link":"https://github.com/o/r/actions/runs/1/job/11"},{"name":"ci/external","link":"https://ci.example/9"}]'
eq "snapshot checks_pending" "$(echo "$p" | jq -c '.checks_pending')" '[]'
eq "snapshot threads_open" "$(echo "$p" | jq -c '.threads_open')" 1
eq "snapshot rounds" "$(echo "$p" | jq -c '.rounds')" 2
eq "snapshot stacked_above" "$(echo "$p" | jq -c '.stacked_above')" '[9,12]'
eq "snapshot repo" "$(echo "$p" | jq -c '.repo')" '{"name":"o/r","default_branch":"main","delete_branch_on_merge":true,"merge_methods":["merge","squash"]}'
eq "snapshot merge_danger" "$(echo "$p" | jq -c '.merge_danger')" '"Run the migration first.\n"'
eq "snapshot unchecked" "$(echo "$p" | jq -c '.unchecked')" '[]'
eq "snapshot calls" "$(calls)" 6
grep -q '^api --paginate repos/o/r/activity?ref=refs/heads/feat/export&activity_type=push&per_page=100' "$GH_LOG" || fail "snapshot: activity call"
grep -q 'head=feat/export' "$GH_LOG" || fail "snapshot: head passed to the query"
ok "state: snapshot fields"

fixtures; pr7 "$pending | .reviewRequests = [{\"__typename\":\"User\",\"login\":\"alice\"},{\"__typename\":\"Team\",\"name\":\"Core\",\"slug\":\"core\"}] | .reviewDecision = \"\""
echo '[{"content":"eyes","user":{"login":"chatgpt-codex-connector[bot]","type":"Bot"}},{"content":"heart","user":{"login":"bob","type":"User"}}]' > "$GH_FIX/reactions.json"
run state 7; p=$(echo "$out" | jq -c '.[0]')
eq "pending list" "$(echo "$p" | jq -c '.checks_pending')" '[{"name":"Codex review","required":false},{"name":"build","required":true},{"name":"ci/external","required":false}]'
eq "pending reviewers" "$(echo "$p" | jq -c '.requested_reviewers')" '["alice","core"]'
eq "pending bot reactions" "$(echo "$p" | jq -c '.bot_reactions')" '[{"user":"chatgpt-codex-connector[bot]","content":"eyes"}]'
eq "pending review null" "$(echo "$p" | jq -c '.review')" null
ok "state: pending checks, reviewers, reactions"

fixtures; pr7 '.isCrossRepository = true | .maintainerCanModify = true | .headRefName = "main" | .headRepositoryOwner.login = "forker" | .headRepository.name = "r-fork"'
run state 7; p=$(echo "$out" | jq -c '.[0]')
grep -q '^api --paginate repos/forker/r-fork/activity?ref=refs/heads/main&' "$GH_LOG" || fail "fork: activity read from the fork"
eq "fork stacked_above" "$(echo "$p" | jq -c '[.cross_repo, .maintainer_can_modify, .stacked_above, .rounds]')" '[true,true,[],2]'
ok "state: a fork PR"

fixtures; GH_FAIL='reviewThreads' run state 7; p=$(echo "$out" | jq -c '.[0]')
eq "threads 403" "$rc $(echo "$p" | jq -c '[.threads_open, .unchecked, .rounds]')" '0 [null,["threads"],2]'
fixtures; GH_FAIL='deleteBranchOnMerge' run state 7; p=$(echo "$out" | jq -c '.[0]')
eq "repo 403" "$(echo "$p" | jq -c '[.repo, .stacked_above, .unchecked, .threads_open]')" '[null,null,["repo"],1]'
fixtures; pr7 "$pending"; GH_FAIL='deleteBranchOnMerge' run state 7
eq "repo 403 required unknown" "$(echo "$out" | jq -c '[.[0].checks_pending[].required]')" '[null,null,null]'
fixtures; GH_FAIL='/activity' run state 7; p=$(echo "$out" | jq -c '.[0]')
eq "activity 403" "$(echo "$p" | jq -c '[.rounds, .unchecked]')" '[null,["rounds"]]'
fixtures; GH_FAIL='/reactions' run state 7; p=$(echo "$out" | jq -c '.[0]')
eq "reactions 403" "$(echo "$p" | jq -c '[.bot_reactions, .unchecked]')" '[null,["reactions"]]'
fixtures; echo '{"data":{"repository":null}}' > "$GH_FIX/detail.json"; run state 7
eq "empty detail" "$(echo "$out" | jq -c '.[0].unchecked')" '["repo"]'
ok "state: failed reads are null and listed in unchecked"

fixtures; run state 8 7
eq "unreadable" "$rc $(echo "$out" | jq -c '[.[0], .[1].number]')" '0 [{"number":8,"error":"gh pr view failed"},7]'
ok "state: an unreadable PR prints an error row"

fixtures; run state 7 --in-flight
eq "clear exit" "$rc" 0
eq "clear out" "$out" '[{"pr":7,"in_flight":false,"reviewers":[],"bot_reactions":[],"reviews_owed":[],"checks_pending":[],"counted":[]}]'
eq "clear calls" "$(calls)" 5
[ "$(grep -c -E 'reviewThreads' "$GH_LOG" || true)" = 0 ] || fail "in-flight must skip threads"
fixtures; pr7 '.reviewRequests = [{"__typename":"Bot","login":"copilot-pull-request-reviewer"}]'; run state 7 --in-flight
eq "reviewer" "$rc $(echo "$out" | jq -c '.[0].counted')" '1 ["reviewer copilot-pull-request-reviewer"]'
fixtures; echo '[{"content":"eyes","user":{"login":"codex[bot]","type":"Bot"}}]' > "$GH_FIX/reactions.json"; run state 7 --in-flight
eq "eyes" "$rc $(echo "$out" | jq -c '.[0].counted')" '1 ["reaction codex[bot] eyes"]'
fixtures; echo '[{"content":"+1","user":{"login":"codex[bot]","type":"Bot"}},{"content":"eyes","user":{"login":"bob","type":"User"}}]' > "$GH_FIX/reactions.json"; run state 7 --in-flight
eq "finished reaction" "$rc $(echo "$out" | jq -c '.[0] | [.in_flight, .bot_reactions]')" '0 [false,[{"user":"codex[bot]","content":"+1"}]]'
ok "state --in-flight: clear, reviewers, bot eyes"

cop='{"id":175728472,"login":"Copilot","type":"Bot"}'
cdx='{"id":199175422,"login":"chatgpt-codex-connector[bot]","type":"Bot"}'
codex() { # a Codex review-state comment: status, commit
  printf '{"event":"commented","created_at":"2026-01-10T00:01:00Z","updated_at":"2026-01-12T00:01:00Z","user":%s,"body":"<!-- codex-pull-request-review-summary -->\\n<!-- codex-review-state:v1 {\\"code_review\\":{\\"commit_sha\\":\\"%s\\",\\"status\\":\\"%s\\"},\\"security_review\\":{\\"commit_sha\\":null,\\"status\\":null}} -->\\nCodex Review Summary"}' "$cdx" "$2" "$1"
}
fixtures; echo "[{\"event\":\"review_requested\",\"created_at\":\"2026-01-12T00:00:30Z\",\"requested_reviewer\":$cop}]" > "$GH_FIX/timeline.json"; run state 7 --in-flight --no-required
eq "requested bot" "$rc $(echo "$out" | jq -c '.[0].counted')" '1 ["owed Copilot: requested 2026-01-12T00:00:30Z, not submitted"]'
fixtures; echo "[{\"event\":\"review_requested\",\"created_at\":\"2026-01-12T00:00:30Z\",\"requested_reviewer\":$cop},
  {\"event\":\"reviewed\",\"submitted_at\":\"2026-01-12T00:06:00Z\",\"commit_id\":\"aaa111\",\"user\":$cop}]" > "$GH_FIX/timeline.json"; run state 7 --in-flight --no-required
eq "requested then reviewed" "$rc $(echo "$out" | jq -c '.[0].counted')" '0 []'
fixtures; echo "[{\"event\":\"review_requested\",\"created_at\":\"2026-01-12T00:00:30Z\",\"requested_team\":{\"slug\":\"core\"}}]" > "$GH_FIX/timeline.json"; run state 7 --in-flight --no-required
eq "requested team" "$rc $(echo "$out" | jq -c '.[0].counted')" '1 ["owed core: requested 2026-01-12T00:00:30Z, not submitted"]'
fixtures; echo "[$(codex running aaa111)]" > "$GH_FIX/timeline.json"; run state 7 --in-flight --no-required
eq "codex running" "$rc $(echo "$out" | jq -c '.[0].counted')" '1 ["owed chatgpt-codex-connector[bot]: running on aaa111"]'
fixtures; echo "[$(codex completed aaa111)]" > "$GH_FIX/timeline.json"; run state 7 --in-flight --no-required
eq "codex completed on head" "$rc" 0
fixtures; codex completed aaa111 | jq -c '[.body = "<!-- codex-pull-request-review-summary -->\n<!-- codex-review-state:v1 {not json} -->"]' > "$GH_FIX/timeline.json"; run state 7 --in-flight --no-required
eq "codex unreadable" "$rc $(echo "$out" | jq -c '.[0].counted')" '1 ["owed chatgpt-codex-connector[bot]: unreadable on ?"]'
fixtures; echo "[$(codex running aaa111 | jq -c '.user = {"id":1,"login":"leek","type":"User"}')]" > "$GH_FIX/timeline.json"; run state 7 --in-flight --no-required
eq "quoted marker from a person" "$rc" 0
security() { codex completed aaa111 | jq -c --arg s "$1" '.body |= sub("\"security_review\":\\{[^}]*\\}"; "\"security_review\":{\"commit_sha\":\"aaa111\",\"status\":\"\($s)\"}")'; }
fixtures; echo "[$(security running)]" > "$GH_FIX/timeline.json"; run state 7 --in-flight --no-required
eq "codex security running" "$rc $(echo "$out" | jq -c '.[0].counted')" '1 ["owed chatgpt-codex-connector[bot] security: security review running on aaa111"]'
fixtures; echo "[$(security completed)]" > "$GH_FIX/timeline.json"; run state 7 --in-flight --no-required
eq "codex security completed" "$rc" 0
fixtures; echo "[{\"event\":\"reviewed\",\"submitted_at\":\"2026-01-10T00:06:00Z\",\"commit_id\":\"old1\",\"user\":$cop},
  {\"event\":\"reviewed\",\"submitted_at\":\"2026-01-11T00:06:00Z\",\"commit_id\":\"old2\",\"user\":$cop},
  {\"event\":\"reviewed\",\"submitted_at\":\"2026-01-11T00:07:00Z\",\"commit_id\":\"old2\",\"user\":$cdx}]" > "$GH_FIX/timeline.json"; run state 7 --in-flight --no-required
eq "push reviewer owes head" "$rc $(echo "$out" | jq -c '.[0].counted')" '1 ["owed Copilot: reviewed earlier pushes, not aaa111"]'
ok "state --in-flight: reviews owed from the timeline"

fixtures; printf '[{"id":4,"timestamp":"%s","activity_type":"push","after":"aaa111"}]\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$GH_FIX/activity.json"; run state 7 --in-flight --no-required
eq "settling" "$rc $(echo "$out" | jq -c '.[0].counted | length')" '1 1'
echo "$out" | jq -r '.[0].counted[0]' | grep -qE '^settling: pushed, opened or marked ready [0-9]+s ago' || fail "settling text"
PR_STATE_SETTLE=0 run state 7 --in-flight --no-required; eq "settled" "$rc" 0
run state 7; eq "head_pushed_at" "$(echo "$out" | jq -r '.[0].head_pushed_at | type')" string
fixtures; printf '[{"event":"ready_for_review","created_at":"%s"}]\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$GH_FIX/timeline.json"; run state 7 --in-flight --no-required
eq "settling after ready" "$rc" 1
fixtures; pr7 ".createdAt = \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""; run state 7 --in-flight --no-required
eq "settling after open" "$rc" 1
ok "state --in-flight: a just-pushed head settles first"

fixtures; pr7 "$pending"; run state 7 --in-flight
eq "required pending" "$rc $(echo "$out" | jq -c '.[0].counted')" '1 ["check build"]'
eq "raw names listed" "$(echo "$out" | jq -c '[.[0].checks_pending[].name]')" '["Codex review","build","ci/external"]'
[ "$(echo "$out" | wc -l | tr -d ' ')" = 1 ] || fail "in-flight output must be one line"
run state 7 --in-flight --no-required
eq "no-required" "$rc $(echo "$out" | jq -c '.[0].counted')" '0 []'
run state 7 --in-flight --no-required --check "Codex review"
eq "named check" "$rc $(echo "$out" | jq -c '.[0].counted')" '1 ["check Codex review"]'
run state 7 --in-flight --no-required --check "not there"
eq "named check absent" "$rc" 0
fixtures; pr7 "$pending | .statusCheckRollup |= map(select(.name != \"build\"))"; run state 7 --in-flight
eq "only optional pending" "$rc $(echo "$out" | jq -c '.[0] | [.in_flight, (.checks_pending | length)]')" '0 [false,2]'
ok "state --in-flight: required checks, --no-required, --check"

fixtures; pr7 "$pending"; mv "$GH_FIX/pr-view-7.json" "$work/pending.json"; fixtures; cp "$work/pending.json" "$GH_FIX/pr-view-9.json"
run state 7 9 --in-flight
eq "two PRs" "$rc $(echo "$out" | jq -c '[.[] | .in_flight]')" '1 [false,true]'
ok "state --in-flight: several PRs"

page2() { # the detail query as gh --paginate prints it: page 1, then a page holding "deploy"
  jq -c '.data.repository.pullRequest.statusCheckRollup.contexts += {totalCount: 6, pageInfo: {hasNextPage: true, endCursor: "c1"}}' "$GH_FIX/detail.json" > "$work/p1.json"
  jq -c '.data.repository.pullRequest.statusCheckRollup.contexts = {totalCount: 6, pageInfo: {hasNextPage: false, endCursor: "c2"},
         nodes: [{"__typename":"CheckRun","name":"deploy","isRequired":true}]}' "$GH_FIX/detail.json" > "$work/p2.json"
}
late='.statusCheckRollup = [{"__typename":"CheckRun","name":"deploy","status":"IN_PROGRESS","conclusion":""}]'
fixtures; pr7 "$late"; page2; cat "$work/p1.json" "$work/p2.json" > "$GH_FIX/detail.json"; run state 7 --in-flight
eq "page 2 required check" "$rc $(echo "$out" | jq -c '.[0].counted')" '1 ["check deploy"]'
grep -q '^api graphql --paginate .*endCursor' "$GH_LOG" || fail "paginated: the detail query must paginate on endCursor"
run state 7; p=$(echo "$out" | jq -c '.[0]')
eq "page 2 snapshot" "$(echo "$p" | jq -c '[.checks_pending, .unchecked, .stacked_above, .repo.name]')" '[[{"name":"deploy","required":true}],[],[9,12],"o/r"]'
ok "state: check contexts beyond the first page are read"

fixtures; pr7 "$late"; page2; cp "$work/p1.json" "$GH_FIX/detail.json"; run state 7 --in-flight
eq "hasNextPage left" "$rc $(echo "$out" | jq -c '.[0] | [.in_flight, .checks_pending]')" '2 [false,[{"name":"deploy","required":null}]]'
grep -q 'required checks are not fully known' "$work/stderr" || fail "short list: stderr"
run state 7; p=$(echo "$out" | jq -c '.[0]')
eq "short list snapshot" "$rc $(echo "$p" | jq -c '[.unchecked, .checks_pending[0].required, .repo.name]')" '0 [["checks"],null,"o/r"]'
fixtures; pr7 "$late"; jq -c '.data.repository.pullRequest.statusCheckRollup.contexts += {totalCount: 140, pageInfo: {hasNextPage: false, endCursor: null}}' "$GH_FIX/detail.json" > "$work/p1.json"
cp "$work/p1.json" "$GH_FIX/detail.json"; run state 7 --in-flight
eq "totalCount above nodes exit" "$rc" 2
fixtures; jq -c '.data.repository.pullRequest.statusCheckRollup.contexts += {totalCount: 5, pageInfo: {hasNextPage: false, endCursor: null}}' "$GH_FIX/detail.json" > "$work/p1.json"
cp "$work/p1.json" "$GH_FIX/detail.json"; run state 7 --in-flight
eq "complete list exit" "$rc" 0
fixtures; jq -c '.data.repository.pullRequest.statusCheckRollup = null' "$GH_FIX/detail.json" > "$work/p1.json"
cp "$work/p1.json" "$GH_FIX/detail.json"; run state 7 --in-flight
eq "no checks at all exit" "$rc" 0
ok "state: a short required-check list is unchecked and exits 2 in flight"

fixtures; GH_FAIL='deleteBranchOnMerge' run state 7 --in-flight;  eq "in-flight graphql 403" "$rc" 2
fixtures; GH_FAIL='/reactions' run state 7 --in-flight;           eq "in-flight reactions 403" "$rc" 2
fixtures; GH_FAIL='/timeline' run state 7 --in-flight;            eq "in-flight timeline 403" "$rc" 2
fixtures; GH_FAIL='/activity' run state 7 --in-flight;            eq "in-flight activity 403" "$rc" 2
fixtures; GH_FAIL='^pr view' run state 7 --in-flight;             eq "in-flight pr view 403" "$rc" 2
ok "state --in-flight: a failed read exits 2"

# The documented wait: run-after's wait-until.sh around state --in-flight.
wait_until="$here/../../run-after/scripts/wait-until.sh"
if [ -f "$wait_until" ]; then
  fixtures; rc=0; out=$(bash "$wait_until" --interval 1 --timeout 0 -- bash "$script" state 7 --in-flight --no-required 2>/dev/null) || rc=$?
  eq "wait passed" "$rc $(echo "$out" | jq -r '.result')" '0 passed'
  echo "$out" | jq -e '.detail | fromjson | .[0].in_flight == false' >/dev/null || fail "wait: detail is the in-flight JSON"
  fixtures; pr7 '.reviewRequests = [{"__typename":"User","login":"alice"}]'
  rc=0; out=$(bash "$wait_until" --interval 1 --timeout 0 -- bash "$script" state 7 --in-flight --no-required 2>/dev/null) || rc=$?
  eq "wait timeout" "$rc $(echo "$out" | jq -r '.result')" '3 timeout'
  eq "wait timeout detail" "$(echo "$out" | jq -c '.detail | fromjson | .[0].counted')" '["reviewer alice"]'
  fixtures; rc=0; out=$(GH_FAIL='/reactions' bash "$wait_until" --interval 1 --timeout 0 -- bash "$script" state 7 --in-flight 2>/dev/null) || rc=$?
  eq "wait failed" "$rc $(echo "$out" | jq -r '.result')" '2 failed'
  ok "state: wait-until.sh wraps --in-flight"
else
  ok "state: wait-until.sh wraps --in-flight (skipped: run-after is not installed beside triage-github-pr)"
fi

run state; eq "no args" "$rc" 2
run state abc; eq "not a number" "$rc" 2
run state 7 --check x; eq "--check without --in-flight" "$rc" 2
run state 7 --no-required; eq "--no-required without --in-flight" "$rc" 2
run state 7 --in-flight --check; eq "--check without a name" "$rc" 2
run state 7 --bogus; eq "unknown flag" "$rc" 2
ok "state: usage errors exit 2"

# =========================================================================================
run; eq "no subcommand" "$rc" 2
run frobnicate 7; eq "unknown subcommand" "$rc" 2
grep -q 'unknown subcommand: frobnicate' "$work/stderr" || fail "unknown subcommand: stderr"
run --help; eq "help" "$rc" 0
ok "pr.sh: a missing or unknown subcommand exits 2"
