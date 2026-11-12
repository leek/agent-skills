#!/bin/bash
# Offline test for pr-state.sh: a stub `gh` first on PATH returns canned JSON per subcommand
# and fails the calls GH_FAIL (a regex) matches.
# Prints one `ok <case>` line per case and exits non-zero on the first failed assertion.
set -e

here=$(cd "$(dirname "$0")" && pwd)
script="$here/pr-state.sh"
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
case "$args" in
  "pr view "*) [ -f "$GH_FIX/pr-view-$3.json" ] || { echo "no pull requests found (stub)" >&2; exit 1; }
               cat "$GH_FIX/pr-view-$3.json" ;;
  "api graphql"*reviewThreads*) cat "$GH_FIX/threads.json" ;;
  "api graphql"*deleteBranchOnMerge*) cat "$GH_FIX/detail.json" ;;
  "api --paginate repos/"*"/issues/"*"/reactions"*) cat "$GH_FIX/reactions.json" ;;
  "api --paginate repos/"*"/activity?"*) cat "$GH_FIX/activity.json" ;;
  *) echo "stub gh: unexpected call: $args" >&2; exit 97 ;;
esac
STUB
chmod +x "$work/bin/gh"
PATH="$work/bin:$PATH"

fail() { echo "FAIL $1" >&2; exit 1; }
ok() { echo "ok $1"; }
eq() { [ "$2" = "$3" ] || fail "$1: expected '$3', got '$2'"; }
run() { rc=0; out=$(env GH_FAIL="${GH_FAIL:-}" bash "$script" "$@" 2> "$work/stderr") || rc=$?; }

fixtures() {
  : > "$GH_LOG"
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
  # Two pages, as `gh api --paginate` prints them. One push predates the PR (round 0).
  cat > "$GH_FIX/activity.json" <<'JSON'
[{"id":3,"timestamp":"2026-01-12T00:00:00Z","activity_type":"push"},{"id":2,"timestamp":"2026-01-11T00:00:00Z","activity_type":"force_push"}]
[{"id":1,"timestamp":"2026-01-09T00:00:00Z","activity_type":"push"}]
JSON
  echo '{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
    {"id":"PRRT_a","isResolved":true,"comments":{"nodes":[{"databaseId":111}]}},
    {"id":"PRRT_b","isResolved":false,"comments":{"nodes":[{"databaseId":222}]}},
    {"id":"PRRT_c","isResolved":false,"comments":{"nodes":[{"databaseId":333}]}}]}}}}}' > "$GH_FIX/threads.json"
}
pr7() { jq "$1" "$GH_FIX/pr-view-7.json" > "$work/pr.tmp" && mv "$work/pr.tmp" "$GH_FIX/pr-view-7.json"; }
pending='.statusCheckRollup = [
  {"__typename":"CheckRun","name":"build","status":"IN_PROGRESS","conclusion":""},
  {"__typename":"CheckRun","name":"Codex review","status":"QUEUED","conclusion":""},
  {"__typename":"StatusContext","context":"ci/external","state":"PENDING"},
  {"__typename":"CheckRun","name":"lint","status":"COMPLETED","conclusion":"SUCCESS"}]'

# --- the snapshot ---
fixtures; run 7
eq "snapshot exit" "$rc" 0
p=$(echo "$out" | jq -c '.[0]')
eq "snapshot keys" "$(echo "$p" | jq -c 'keys')" '["base","bot_reactions","checks_failed","checks_pending","cross_repo","draft","head","head_sha","maintainer_can_modify","merge_danger","merge_state","mergeable","number","repo","requested_reviewers","review","rounds","stacked_above","state","threads_open","title","unchecked","url"]'
eq "snapshot facts" "$(echo "$p" | jq -c '[.number,.state,.draft,.head,.head_sha,.base,.mergeable,.merge_state,.review,.cross_repo,.maintainer_can_modify]')" '[7,"OPEN",false,"feat/export","aaa111","main","MERGEABLE","BLOCKED","REVIEW_REQUIRED",false,false]'
eq "snapshot checks_failed" "$(echo "$p" | jq -c '.checks_failed')" '[{"name":"tests","link":"https://github.com/o/r/actions/runs/1/job/11"},{"name":"ci/external","link":"https://ci.example/9"}]'
eq "snapshot checks_pending" "$(echo "$p" | jq -c '.checks_pending')" '[]'
eq "snapshot threads_open" "$(echo "$p" | jq -c '.threads_open')" 2
eq "snapshot rounds" "$(echo "$p" | jq -c '.rounds')" 2
eq "snapshot stacked_above" "$(echo "$p" | jq -c '.stacked_above')" '[9,12]'
eq "snapshot repo" "$(echo "$p" | jq -c '.repo')" '{"name":"o/r","default_branch":"main","delete_branch_on_merge":true,"merge_methods":["merge","squash"]}'
eq "snapshot merge_danger" "$(echo "$p" | jq -c '.merge_danger')" '"Run the migration first.\n"'
eq "snapshot unchecked" "$(echo "$p" | jq -c '.unchecked')" '[]'
eq "snapshot calls" "$(wc -l < "$GH_LOG" | tr -d ' ')" 5
grep -q '^api --paginate repos/o/r/activity?ref=refs/heads/feat/export&activity_type=push&per_page=100' "$GH_LOG" || fail "snapshot: activity call"
grep -q 'head=feat/export' "$GH_LOG" || fail "snapshot: head passed to the query"
ok "snapshot fields"

# --- pending checks carry required; reviewers and bot reactions are listed ---
fixtures; pr7 "$pending | .reviewRequests = [{\"__typename\":\"User\",\"login\":\"alice\"},{\"__typename\":\"Team\",\"name\":\"Core\",\"slug\":\"core\"}] | .reviewDecision = \"\""
echo '[{"content":"eyes","user":{"login":"chatgpt-codex-connector[bot]","type":"Bot"}},{"content":"heart","user":{"login":"bob","type":"User"}}]' > "$GH_FIX/reactions.json"
run 7; p=$(echo "$out" | jq -c '.[0]')
eq "pending list" "$(echo "$p" | jq -c '.checks_pending')" '[{"name":"Codex review","required":false},{"name":"build","required":true},{"name":"ci/external","required":false}]'
eq "pending reviewers" "$(echo "$p" | jq -c '.requested_reviewers')" '["alice","core"]'
eq "pending bot reactions" "$(echo "$p" | jq -c '.bot_reactions')" '[{"user":"chatgpt-codex-connector[bot]","content":"eyes"}]'
eq "pending review null" "$(echo "$p" | jq -c '.review')" null
ok "pending checks, reviewers, reactions"

# --- a fork PR counts rounds in the fork, and is never a stack parent ---
fixtures; pr7 '.isCrossRepository = true | .maintainerCanModify = true | .headRefName = "main" | .headRepositoryOwner.login = "forker" | .headRepository.name = "r-fork"'
run 7; p=$(echo "$out" | jq -c '.[0]')
grep -q '^api --paginate repos/forker/r-fork/activity?ref=refs/heads/main&' "$GH_LOG" || fail "fork: activity read from the fork"
eq "fork stacked_above" "$(echo "$p" | jq -c '[.cross_repo, .maintainer_can_modify, .stacked_above, .rounds]')" '[true,true,[],2]'
ok "fork PR"

# --- failing reads give null and name themselves; never zero ---
fixtures; GH_FAIL='reviewThreads' run 7; p=$(echo "$out" | jq -c '.[0]')
eq "threads 403 exit" "$rc" 0
eq "threads 403" "$(echo "$p" | jq -c '[.threads_open, .unchecked, .rounds]')" '[null,["threads"],2]'
fixtures; GH_FAIL='deleteBranchOnMerge' run 7; p=$(echo "$out" | jq -c '.[0]')
eq "repo 403" "$(echo "$p" | jq -c '[.repo, .stacked_above, .unchecked, .threads_open]')" '[null,null,["repo"],2]'
fixtures; pr7 "$pending"; GH_FAIL='deleteBranchOnMerge' run 7
eq "repo 403 required unknown" "$(echo "$out" | jq -c '[.[0].checks_pending[].required]')" '[null,null,null]'
fixtures; GH_FAIL='/activity' run 7; p=$(echo "$out" | jq -c '.[0]')
eq "activity 403" "$(echo "$p" | jq -c '[.rounds, .unchecked]')" '[null,["rounds"]]'
fixtures; GH_FAIL='/reactions' run 7; p=$(echo "$out" | jq -c '.[0]')
eq "reactions 403" "$(echo "$p" | jq -c '[.bot_reactions, .unchecked]')" '[null,["reactions"]]'
fixtures; echo '{"data":{"repository":null}}' > "$GH_FIX/detail.json"; run 7
eq "empty detail" "$(echo "$out" | jq -c '.[0].unchecked')" '["repo"]'
ok "failed reads are null and listed in unchecked"

# --- a PR gh cannot read prints an error row; the others still print ---
fixtures; run 8 7
eq "unreadable exit" "$rc" 0
eq "unreadable rows" "$(echo "$out" | jq -c '[.[0], .[1].number]')" '[{"number":8,"error":"gh pr view failed"},7]'
ok "unreadable PR"

# --- --in-flight ---
fixtures; run 7 --in-flight
eq "clear exit" "$rc" 0
eq "clear out" "$out" '[{"pr":7,"in_flight":false,"reviewers":[],"bot_reactions":[],"checks_pending":[],"counted":[]}]'
eq "clear calls" "$(wc -l < "$GH_LOG" | tr -d ' ')" 3
[ "$(grep -c -E 'reviewThreads|/activity' "$GH_LOG" || true)" = 0 ] || fail "in-flight must skip threads and rounds"
ok "in-flight: nothing running exits 0"

fixtures; pr7 '.reviewRequests = [{"__typename":"Bot","login":"copilot-pull-request-reviewer"}]'; run 7 --in-flight
eq "reviewer" "$rc $(echo "$out" | jq -c '.[0].counted')" '1 ["reviewer copilot-pull-request-reviewer"]'
fixtures; echo '[{"content":"eyes","user":{"login":"codex[bot]","type":"Bot"}}]' > "$GH_FIX/reactions.json"; run 7 --in-flight
eq "eyes" "$rc $(echo "$out" | jq -c '.[0].counted')" '1 ["reaction codex[bot] eyes"]'
fixtures; echo '[{"content":"+1","user":{"login":"codex[bot]","type":"Bot"}},{"content":"eyes","user":{"login":"bob","type":"User"}}]' > "$GH_FIX/reactions.json"; run 7 --in-flight
eq "finished reaction" "$rc $(echo "$out" | jq -c '.[0] | [.in_flight, .bot_reactions]')" '0 [false,[{"user":"codex[bot]","content":"+1"}]]'
ok "in-flight: reviewers and bot eyes"

fixtures; pr7 "$pending"; run 7 --in-flight
eq "required pending" "$rc $(echo "$out" | jq -c '.[0].counted')" '1 ["check build"]'
eq "raw names listed" "$(echo "$out" | jq -c '[.[0].checks_pending[].name]')" '["Codex review","build","ci/external"]'
[ "$(echo "$out" | wc -l | tr -d ' ')" = 1 ] || fail "in-flight output must be one line"
run 7 --in-flight --no-required
eq "no-required" "$rc $(echo "$out" | jq -c '.[0].counted')" '0 []'
run 7 --in-flight --no-required --check "Codex review"
eq "named check" "$rc $(echo "$out" | jq -c '.[0].counted')" '1 ["check Codex review"]'
run 7 --in-flight --no-required --check "not there"
eq "named check absent" "$rc" 0
fixtures; pr7 "$pending | .statusCheckRollup |= map(select(.name != \"build\"))"; run 7 --in-flight
eq "only optional pending" "$rc $(echo "$out" | jq -c '.[0] | [.in_flight, (.checks_pending | length)]')" '0 [false,2]'
ok "in-flight: required checks, --no-required, --check"

fixtures; pr7 "$pending"; cp "$GH_FIX/pr-view-7.json" "$GH_FIX/pr-view-9.json"; fixtures; run 7 9 --in-flight
eq "two PRs" "$rc $(echo "$out" | jq -c '[.[] | .in_flight]')" '1 [false,true]'
rm -f "$GH_FIX/pr-view-9.json"
ok "in-flight: several PRs"

# --- more than 100 check contexts: every page is read, so a required check on page 2 counts ---
page2() { # the detail query as gh --paginate prints it: page 1, then a page holding "deploy"
  jq -c '.data.repository.pullRequest.statusCheckRollup.contexts += {totalCount: 6, pageInfo: {hasNextPage: true, endCursor: "c1"}}' "$GH_FIX/detail.json" > "$work/p1.json"
  jq -c '.data.repository.pullRequest.statusCheckRollup.contexts = {totalCount: 6, pageInfo: {hasNextPage: false, endCursor: "c2"},
         nodes: [{"__typename":"CheckRun","name":"deploy","isRequired":true}]}' "$GH_FIX/detail.json" > "$work/p2.json"
}
late='.statusCheckRollup = [{"__typename":"CheckRun","name":"deploy","status":"IN_PROGRESS","conclusion":""}]'
fixtures; pr7 "$late"; page2; cat "$work/p1.json" "$work/p2.json" > "$GH_FIX/detail.json"; run 7 --in-flight
eq "page 2 required check" "$rc $(echo "$out" | jq -c '.[0].counted')" '1 ["check deploy"]'
grep -q '^api graphql --paginate .*endCursor' "$GH_LOG" || fail "paginated: the detail query must paginate on endCursor"
run 7; p=$(echo "$out" | jq -c '.[0]')
eq "page 2 snapshot" "$(echo "$p" | jq -c '[.checks_pending, .unchecked, .stacked_above, .repo.name]')" '[[{"name":"deploy","required":true}],[],[9,12],"o/r"]'
ok "check contexts beyond the first page are read"

# --- a required-check list that came back short is unknown: unchecked, and --in-flight exits 2 ---
fixtures; pr7 "$late"; page2; cp "$work/p1.json" "$GH_FIX/detail.json"; run 7 --in-flight
eq "hasNextPage left exit" "$rc" 2
eq "hasNextPage left row" "$(echo "$out" | jq -c '.[0] | [.in_flight, .checks_pending]')" '[false,[{"name":"deploy","required":null}]]'
grep -q 'required checks are not fully known' "$work/stderr" || fail "short list: stderr"
run 7; p=$(echo "$out" | jq -c '.[0]')
eq "short list snapshot" "$rc $(echo "$p" | jq -c '[.unchecked, .checks_pending[0].required, .repo.name]')" '0 [["checks"],null,"o/r"]'
fixtures; pr7 "$late"; jq -c '.data.repository.pullRequest.statusCheckRollup.contexts += {totalCount: 140, pageInfo: {hasNextPage: false, endCursor: null}}' "$GH_FIX/detail.json" > "$work/p1.json"
cp "$work/p1.json" "$GH_FIX/detail.json"; run 7 --in-flight
eq "totalCount above nodes exit" "$rc" 2
fixtures; jq -c '.data.repository.pullRequest.statusCheckRollup.contexts += {totalCount: 5, pageInfo: {hasNextPage: false, endCursor: null}}' "$GH_FIX/detail.json" > "$work/p1.json"
cp "$work/p1.json" "$GH_FIX/detail.json"; run 7 --in-flight
eq "complete list exit" "$rc" 0
fixtures; jq -c '.data.repository.pullRequest.statusCheckRollup = null' "$GH_FIX/detail.json" > "$work/p1.json"
cp "$work/p1.json" "$GH_FIX/detail.json"; run 7 --in-flight
eq "no checks at all exit" "$rc" 0
ok "a short required-check list is unchecked and exits 2 in flight"

fixtures; GH_FAIL='deleteBranchOnMerge' run 7 --in-flight;  eq "in-flight graphql 403" "$rc" 2
fixtures; GH_FAIL='/reactions' run 7 --in-flight;           eq "in-flight reactions 403" "$rc" 2
fixtures; GH_FAIL='^pr view' run 7 --in-flight;             eq "in-flight pr view 403" "$rc" 2
ok "in-flight: a failed read exits 2"

# --- the documented wait: run-after's wait-until.sh around --in-flight ---
wait_until="$here/../../run-after/scripts/wait-until.sh"
if [ -f "$wait_until" ]; then
  fixtures; rc=0; out=$(bash "$wait_until" --interval 1 --timeout 0 -- bash "$script" 7 --in-flight --no-required 2>/dev/null) || rc=$?
  eq "wait passed" "$rc $(echo "$out" | jq -r '.result')" '0 passed'
  echo "$out" | jq -e '.detail | fromjson | .[0].in_flight == false' >/dev/null || fail "wait: detail is the in-flight JSON"
  fixtures; pr7 '.reviewRequests = [{"__typename":"User","login":"alice"}]'
  rc=0; out=$(bash "$wait_until" --interval 1 --timeout 0 -- bash "$script" 7 --in-flight --no-required 2>/dev/null) || rc=$?
  eq "wait timeout" "$rc $(echo "$out" | jq -r '.result')" '3 timeout'
  eq "wait timeout detail" "$(echo "$out" | jq -c '.detail | fromjson | .[0].counted')" '["reviewer alice"]'
  fixtures; rc=0; out=$(GH_FAIL='/reactions' bash "$wait_until" --interval 1 --timeout 0 -- bash "$script" 7 --in-flight 2>/dev/null) || rc=$?
  eq "wait failed" "$rc $(echo "$out" | jq -r '.result')" '2 failed'
  ok "wait-until.sh wraps --in-flight"
else
  ok "wait-until.sh wraps --in-flight (skipped: run-after is not installed beside closeout)"
fi

# --- usage ---
run; eq "no args" "$rc" 2
run abc; eq "not a number" "$rc" 2
run 7 --check x; eq "--check without --in-flight" "$rc" 2
run 7 --no-required; eq "--no-required without --in-flight" "$rc" 2
run 7 --in-flight --check; eq "--check without a name" "$rc" 2
run 7 --bogus; eq "unknown flag" "$rc" 2
ok "usage errors exit 2"
