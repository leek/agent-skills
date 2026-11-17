#!/bin/bash
# The PR gate snapshot: the state of each pull request, as one JSON array on stdout.
#
# Usage: pr-state.sh <number> [<number> ...]
#        pr-state.sh <number> [<number> ...] --in-flight [--no-required] [--check <name>]...
# Run from inside the repository the PRs belong to. Read-only.
#
# Per PR:
#   number, url, title, state, draft
#   head, head_sha, base          head and base are branch names
#   mergeable, merge_state        gh's mergeable and mergeStateStatus
#   review                        gh's reviewDecision, or null
#   cross_repo, maintainer_can_modify
#   requested_reviewers  [login or team slug]     requested, not yet submitted
#   bot_reactions        [{user, content}]        reactions bots left on the PR (eyes, +1, ...)
#   reviews_owed         [{reviewer, why}]        reviews still owed, from the issue timeline:
#                        a request with no later review or removal (Copilot's pending request
#                        was seen here but not in requested_reviewers, 2026-11-14); a Codex
#                        review-state comment whose code review is not finished or unreadable,
#                        or whose security review is started and not finished; a bot that reviewed
#                        2+ commits of this PR but not the head
#   head_pushed_at       when the push that made the head landed (activity feed), or null
#   checks_failed        [{name, link}]           failed, errored, cancelled, timed out, or never started
#   checks_pending       [{name, required}]       not finished yet; required is null when unknown
#   threads_open         review threads not resolved
#   rounds               pushes to the head branch after the PR opened (GitHub's activity feed,
#                        read from the head repository, so a fork PR counts the fork's pushes)
#   stacked_above        [number]                 open PRs whose base is this PR's head; [] for a fork PR
#   repo                 {name, default_branch, delete_branch_on_merge, merge_methods: ["merge","squash","rebase"]}
#   merge_danger         the body's "## Merge Danger" section (the pr skill's format), or null
#   unchecked            the reads that failed: "threads", "repo", "rounds", "reactions", "timeline".
#                        Each leaves its fields null (threads_open; repo, stacked_above and every
#                        `required`; rounds and head_pushed_at; bot_reactions; reviews_owed).
#                        null means not checked, never zero.
#                        "checks" means the required-check list came back short of GitHub's own
#                        count (every page is read, 100 contexts a page): a pending check missing
#                        from it has `required: null`.
# A PR that gh cannot read prints {"number", "error"}. Exit 0 either way.
# Calls per PR: gh pr view, one GraphQL query, the activity feed, the reactions, the timeline,
# and the review-thread query (review_threads, below; when it fails, threads_open is null).
#
# --in-flight  Is a review or a required check still running? Prints one line, a JSON array of
#     {"pr", "in_flight", "reviewers", "bot_reactions", "reviews_owed", "checks_pending", "counted"}
#   and exits 0 when nothing is in flight on any PR, 1 when something is, 2 on any error
#   (a failed read, or a short required-check list: unknown is never "clear").
#   Counted: every requested reviewer, every bot `eyes` reaction, every review owed, a PR
#   pushed, opened, or marked ready under PR_STATE_SETTLE seconds ago (default 120: bots take
#   up to a minute to register one), and every pending required check. It skips the review-thread query.
#   --no-required leaves required checks out; --check <name> also counts that pending check,
#   required or not (repeatable). `checks_pending` lists every pending check by name,
#   counted or not: which one is a review bot's own is the caller's judgement.
#   The exit codes fit run-after's wait-until.sh:
#     wait-until.sh --timeout <s> -- bash pr-state.sh <number> --in-flight
set -e

usage() { echo "usage: pr-state.sh <number> [<number> ...] [--in-flight [--no-required] [--check <name>]...]" >&2; exit 2; }

in_flight=0; no_required=0; prs=()
settle=${PR_STATE_SETTLE:-120}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Every review thread of the PR, all pages, as one JSON array on stdout:
#   [{"thread": "PRRT_...", "resolved": bool, "ids": [<comment databaseId>, ...]}]
# `ids` holds every comment in the thread, so a reply maps to its thread as well as the root.
# The same function sits in pr-comments.sh, pr-reply.sh, and closeout's pr-state.sh: keep the
# three in step. A shared file would need a path computed at run time, which the plugin
# directory refuses in a pre-approved script. Fails (never an empty list) when gh fails or a
# page lacks the thread list, so a 403 never reads as "no threads".
review_threads() {
  local rc=0
  # shellcheck disable=SC2016  # $owner and friends are GraphQL variables, not shell ones
  gh api graphql --paginate -f owner="${1%/*}" -f repo="${1#*/}" -F pr="$2" -f query='
query($owner: String!, $repo: String!, $pr: Int!, $endCursor: String) {
  repository(owner: $owner, name: $repo) { pullRequest(number: $pr) {
    reviewThreads(first: 100, after: $endCursor) {
      pageInfo { hasNextPage endCursor }
      nodes { id isResolved comments(first: 100) { nodes { databaseId } } } } } } }' > "$tmp/review-threads.raw" || return 1
  jq -s '[.[] | .data.repository.pullRequest.reviewThreads.nodes[]
          | {thread: .id, resolved: .isResolved, ids: [.comments.nodes[].databaseId]}]' "$tmp/review-threads.raw" || rc=$?
  return "$rc"
}
: > "$tmp/check-names"
while [ $# -gt 0 ]; do
  case "$1" in
    --in-flight) in_flight=1 ;;
    --no-required) no_required=1 ;;
    --check) [ -n "${2:-}" ] || usage; printf '%s\n' "$2" >> "$tmp/check-names"; shift ;;
    -*) echo "Unknown arg: $1" >&2; usage ;;
    *) [[ "$1" =~ ^[0-9]+$ ]] || { echo "not a PR number: $1" >&2; usage; }; prs+=("$1") ;;
  esac
  shift
done
[ ${#prs[@]} -gt 0 ] || usage
if [ "$in_flight" = 0 ] && { [ "$no_required" = 1 ] || [ -s "$tmp/check-names" ]; }; then
  echo "--no-required and --check need --in-flight" >&2; usage
fi
command -v gh >/dev/null || { echo "gh is required" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

errors=0

i=0
for n in "${prs[@]}"; do
  i=$((i + 1))
  out="$tmp/$(printf %03d "$i").json"
  echo "Checking PR #$n..." >&2
  if ! gh pr view "$n" --json number,url,title,state,isDraft,reviewDecision,statusCheckRollup,body,headRefName,headRefOid,baseRefName,mergeable,mergeStateStatus,isCrossRepository,maintainerCanModify,reviewRequests,createdAt,headRepository,headRepositoryOwner > "$tmp/pr.json"; then
    errors=$((errors + 1))
    jq -n --arg number "$n" '{number: ($number | tonumber? // $number), error: "gh pr view failed"}' > "$out"
    continue
  fi
  repo=$(jq -r '.url | split("/") | .[3] + "/" + .[4]' "$tmp/pr.json")
  head=$(jq -r '.headRefName' "$tmp/pr.json")
  : > "$tmp/unchecked"

  # Repo settings, the PRs stacked on this head, and which checks are required: one query,
  # paginated over the check contexts (gh prints one JSON object per page; a PR can carry
  # more than 100 contexts, and a required one past the first page must not be dropped).
  # shellcheck disable=SC2016  # $owner and friends are GraphQL variables, not shell ones
  if ! gh api graphql --paginate -f owner="${repo%/*}" -f repo="${repo#*/}" -F pr="$n" -f head="$head" -f query='
query($owner: String!, $repo: String!, $pr: Int!, $head: String!, $endCursor: String) {
  repository(owner: $owner, name: $repo) {
    nameWithOwner deleteBranchOnMerge mergeCommitAllowed squashMergeAllowed rebaseMergeAllowed
    defaultBranchRef { name }
    pullRequests(baseRefName: $head, states: OPEN, first: 100) { nodes { number } }
    pullRequest(number: $pr) { statusCheckRollup { contexts(first: 100, after: $endCursor) {
      totalCount pageInfo { hasNextPage endCursor }
      nodes {
        __typename
        ... on CheckRun { name isRequired(pullRequestNumber: $pr) }
        ... on StatusContext { context isRequired(pullRequestNumber: $pr) } } } } } } }' > "$tmp/detail.raw" \
     || ! jq -se 'length > 0 and all(.[]; .data.repository.pullRequest != null)' "$tmp/detail.raw" >/dev/null 2>&1; then
    echo "null" > "$tmp/detail.json"; echo repo >> "$tmp/unchecked"
  else
    # Join the pages: the first page's repository, with every page's contexts.
    jq -s '([.[] | .data.repository.pullRequest.statusCheckRollup.contexts.nodes[]?]) as $nodes
           | (.[0].data.repository.pullRequest.statusCheckRollup.contexts) as $first
           | (.[-1].data.repository.pullRequest.statusCheckRollup.contexts) as $last
           | .[0]
           | if $first == null then . else .data.repository.pullRequest.statusCheckRollup.contexts.nodes = $nodes end
           | .checks_short = (($last.pageInfo.hasNextPage // false) or (($first.totalCount // 0) > ($nodes | length)))' \
      "$tmp/detail.raw" > "$tmp/detail.json"
    if [ "$(jq -r '.checks_short' "$tmp/detail.json")" = true ]; then
      echo "PR #$n: the required-check list is shorter than GitHub's count; required checks are not fully known" >&2
      echo checks >> "$tmp/unchecked"
    fi
  fi

  if ! gh api --paginate "repos/$repo/issues/$n/reactions?per_page=100" > "$tmp/reactions.raw" \
     || ! jq -s '[.[][] | select(.user.type == "Bot") | {user: .user.login, content}]' "$tmp/reactions.raw" > "$tmp/reactions.json" 2>/dev/null; then
    echo "null" > "$tmp/reactions.json"; echo reactions >> "$tmp/unchecked"
  fi

  # The issue timeline: review requests, submitted reviews (with the commit each covers), and
  # comments with their current body (Codex edits its review-state comment in place).
  if ! gh api --paginate "repos/$repo/issues/$n/timeline?per_page=100" > "$tmp/timeline.raw" \
     || ! jq -s 'add // []' "$tmp/timeline.raw" > "$tmp/timeline.json" 2>/dev/null; then
    echo "null" > "$tmp/timeline.json"; echo timeline >> "$tmp/unchecked"
  fi

  # A round is a push to the head branch after the PR opened; the push that made the current
  # head dates it. The feed lives in the head repository: the fork, for a fork PR.
  echo "null" > "$tmp/rounds.json"; echo "null" > "$tmp/pushed.json"
  feed=$(jq -r 'if .headRepositoryOwner.login and .headRepository.name
                then "repos/\(.headRepositoryOwner.login)/\(.headRepository.name)/activity?ref=refs/heads/\(.headRefName | @uri | gsub("%2F"; "/"))&activity_type=push&per_page=100"
                else "" end' "$tmp/pr.json")
  if [ -z "$feed" ] || ! gh api --paginate "$feed" > "$tmp/activity.raw" \
     || ! jq -s --slurpfile pr "$tmp/pr.json" '[.[][] | select(.timestamp > $pr[0].createdAt)] | length' "$tmp/activity.raw" > "$tmp/rounds.json" 2>/dev/null; then
    echo "null" > "$tmp/rounds.json"; echo rounds >> "$tmp/unchecked"
  else
    jq -s --slurpfile pr "$tmp/pr.json" '[.[][] | select(.after == $pr[0].headRefOid) | .timestamp] | max' "$tmp/activity.raw" > "$tmp/pushed.json"
  fi

  echo "null" > "$tmp/threads.json"
  if [ "$in_flight" = 0 ]; then
    if ! review_threads "$repo" "$n" > "$tmp/threads.raw"; then
      echo threads >> "$tmp/unchecked"
    else
      jq '[.[] | select(.resolved | not)] | length' "$tmp/threads.raw" > "$tmp/threads.json"
    fi
  fi

  jq --slurpfile d "$tmp/detail.json" --slurpfile reactions "$tmp/reactions.json" \
     --slurpfile threads "$tmp/threads.json" --slurpfile rounds "$tmp/rounds.json" \
     --slurpfile timeline "$tmp/timeline.json" --slurpfile pushed "$tmp/pushed.json" \
     --argjson settle "$settle" --rawfile unchecked "$tmp/unchecked" --rawfile names "$tmp/check-names" \
     --argjson in_flight "$in_flight" --argjson no_required "$no_required" '
    def outcome:
      if (.status // "COMPLETED" | ascii_upcase) != "COMPLETED" then "PENDING"
      else (.conclusion // .state // "") | ascii_upcase end;
    def lines: split("\n") | map(select(. != ""));
    def t: .submitted_at // .updated_at // .created_at // "";
    # The review-state comment Codex posts as a bot; a state that does not parse reads "unreadable", never clear.
    # It carries a code review and a security review; the security review is null until Codex starts one.
    def codex_state: [.[] | select(.event == "commented" and .user.type == "Bot"
                                    and (.body // "" | contains("<!-- codex-review-state:v1 ")))] | last
      | if . == null then null else
          ((.body | capture("<!-- codex-review-state:v1 (?<j>\\{.*?\\}) -->")? | .j | fromjson?) // null) as $j
          | {user: .user,
             state: ($j.code_review // {status: "unreadable", commit_sha: null}),
             security: ($j.security_review // null)} end;
    def unfinished: (. // "completed") | ascii_downcase
      | IN("completed", "failed", "error", "cancelled", "canceled", "skipped") | not;
    # Reviews owed on this PR, from the timeline:
    #  requested: a review request with no later review by that reviewer (any human review for a
    #             team) and no later removal. Copilot shows here, not in reviewRequests.
    #  running:   Codex review-state comment whose status is not finished.
    #  head:      a bot that reviewed two or more commits of this PR (it reviews pushes) and has
    #             not reviewed the head.
    def owed($tl; $head):
      if $tl == null then null else
      def key: if .requested_team then "team:\(.requested_team.slug)" else ((.requested_reviewer // .user).id | tostring) end;
      ($tl | codex_state) as $cx
      | ([$tl[] | select(.event == "review_requested")] | group_by(key) | map(max_by(t))
         | map(. as $r | ($r | key) as $k | ($r | t) as $at
           | select([$tl[] | select(t > $at)
                     | select((.event == "review_request_removed" and key == $k)
                              or (.event == "reviewed" and (if ($k | startswith("team:")) then .user.type != "Bot"
                                                            else (.user.id | tostring) == $k end)))] | length == 0)
           | {reviewer: ($r.requested_team.slug // $r.requested_reviewer.login), why: "requested \($at), not submitted"}))
        + (if $cx.state and ($cx.state.status | unfinished)
           then [{reviewer: $cx.user.login, why: "\($cx.state.status) on \($cx.state.commit_sha // "?" | .[0:7])"}] else [] end)
        + (if $cx.security.status and ($cx.security.status | unfinished)
           then [{reviewer: "\($cx.user.login) security", why: "security review \($cx.security.status) on \($cx.security.commit_sha // "?" | .[0:7])"}] else [] end)
        + ([$tl[] | select(.event == "reviewed" and .user.type == "Bot") | {id: (.user.id | tostring), login: .user.login, c: .commit_id}]
           + (if $cx.state.commit_sha and $cx.state.status == "completed"
              then [{id: ($cx.user.id | tostring), login: $cx.user.login, c: $cx.state.commit_sha}] else [] end)
           | group_by(.id)
           | map(select((map(.c) | unique) as $cs | ($cs | length) >= 2 and ($cs | index($head) | not)))
           | map({reviewer: .[0].login, why: "reviewed earlier pushes, not \($head[0:7])"}))
      | unique_by(.reviewer) end;
    ($d[0].data.repository) as $r
    | (if $r then [$r.pullRequest.statusCheckRollup.contexts.nodes[]? | {name: (.name // .context), required: .isRequired}] else null end) as $req
    | def required($n): if $req == null then null
        else ([$req[] | select(.name == $n) | .required] | if length == 0 then null else any end) end;
      [.reviewRequests[]? | (.login // .slug // .name)] as $reviewers
    | owed($timeline[0]; .headRefOid) as $owed
    # Bots start on a push, on opening, and on leaving draft: settle from the latest of the three.
    | ([$pushed[0], .createdAt, ($timeline[0] // [] | map(select(.event == "ready_for_review") | .created_at) | max)]
       | map(select(. != null)) | max
       | if . then (now - fromdateiso8601 | floor) else null end) as $pushed_ago
    | ([.statusCheckRollup[]? | select(outcome | IN("", "PENDING", "QUEUED", "IN_PROGRESS", "EXPECTED", "WAITING", "REQUESTED")) | (.name // .context)]
       | unique | map({name: ., required: required(.)})) as $pending
    | if $in_flight == 1 then
        ([$reviewers[] | "reviewer \(.)"]
         + [$reactions[0][]? | select(.content == "eyes") | "reaction \(.user) eyes"]
         + [$owed[]? | "owed \(.reviewer): \(.why)"]
         + (if $pushed_ago != null and $pushed_ago < $settle then ["settling: pushed, opened or marked ready \($pushed_ago)s ago"] else [] end)
         + [$pending[] | select((.required == true and $no_required == 0) or (.name | IN($names | lines | .[]))) | "check \(.name)"]) as $counted
        | {pr: .number, in_flight: ($counted | length > 0), reviewers: $reviewers, bot_reactions: $reactions[0],
           reviews_owed: $owed, checks_pending: $pending, counted: $counted}
      else
        {number, url, title, state, draft: .isDraft,
         head: .headRefName, head_sha: .headRefOid, base: .baseRefName,
         mergeable, merge_state: .mergeStateStatus,
         review: (if .reviewDecision == "" then null else .reviewDecision end),
         cross_repo: .isCrossRepository, maintainer_can_modify: .maintainerCanModify,
         requested_reviewers: $reviewers,
         bot_reactions: $reactions[0],
         reviews_owed: $owed,
         head_pushed_at: $pushed[0],
         checks_failed: [.statusCheckRollup[]? | select(outcome | IN("FAILURE", "CANCELLED", "TIMED_OUT", "ERROR", "ACTION_REQUIRED", "STARTUP_FAILURE", "STALE"))
                         | {name: (.name // .context), link: (.detailsUrl // .targetUrl // null)}],
         checks_pending: $pending,
         threads_open: $threads[0],
         rounds: $rounds[0],
         stacked_above: (if $r == null then null elif .isCrossRepository then [] else [$r.pullRequests.nodes[].number] | sort end),
         repo: (if $r == null then null else
           {name: $r.nameWithOwner, default_branch: $r.defaultBranchRef.name,
            delete_branch_on_merge: $r.deleteBranchOnMerge,
            merge_methods: ([(if $r.mergeCommitAllowed then "merge" else empty end),
                             (if $r.squashMergeAllowed then "squash" else empty end),
                             (if $r.rebaseMergeAllowed then "rebase" else empty end)])} end),
         merge_danger: ((.body // "") | (capture("## Merge Danger\\s*(?<s>[\\s\\S]*?)(\\n## |\\z)").s)? // null),
         unchecked: ($unchecked | lines)}
      end' "$tmp/pr.json" > "$out"
  [ ! -s "$tmp/unchecked" ] || errors=$((errors + 1))
done

if [ "$in_flight" = 1 ]; then
  if [ "$errors" -gt 0 ]; then
    echo "a read failed; in-flight state is not known" >&2
    jq -sc . "$tmp"/[0-9]*.json
    exit 2
  fi
  jq -sc . "$tmp"/[0-9]*.json
  jq -se 'any(.[]; .in_flight) | not' "$tmp"/[0-9]*.json >/dev/null || exit 1
  exit 0
fi

jq -s . "$tmp"/[0-9]*.json
