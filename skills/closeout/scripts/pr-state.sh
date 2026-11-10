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
#   checks_failed        [{name, link}]           failed, errored, cancelled, timed out, or never started
#   checks_pending       [{name, required}]       not finished yet; required is null when unknown
#   threads_open         review threads not resolved
#   rounds               pushes to the head branch after the PR opened (GitHub's activity feed,
#                        read from the head repository, so a fork PR counts the fork's pushes)
#   stacked_above        [number]                 open PRs whose base is this PR's head; [] for a fork PR
#   repo                 {name, default_branch, delete_branch_on_merge, merge_methods: ["merge","squash","rebase"]}
#   merge_danger         the body's "## Merge Danger" section (the pr skill's format), or null
#   unchecked            the reads that failed: "threads", "repo", "rounds", "reactions". Each one
#                        leaves its fields null (threads_open; repo, stacked_above and every
#                        `required`; rounds; bot_reactions). null means not checked, never zero.
#                        "checks" means the required-check list came back short of GitHub's own
#                        count (every page is read, 100 contexts a page): a pending check missing
#                        from it has `required: null`.
# A PR that gh cannot read prints {"number", "error"}. Exit 0 either way.
# Calls per PR: gh pr view, one GraphQL query, the activity feed, the reactions, and the
# review-thread query (triage-github-pr's scripts/review-threads.sh, installed beside this
# skill; without it threads_open is null).
#
# --in-flight  Is a review or a required check still running? Prints one line, a JSON array of
#     {"pr", "in_flight", "reviewers", "bot_reactions", "checks_pending", "counted"}
#   and exits 0 when nothing is in flight on any PR, 1 when something is, 2 on any error
#   (a failed read, or a short required-check list: unknown is never "clear").
#   Counted: every requested reviewer, every bot `eyes` reaction, and every pending required
#   check. --no-required leaves required checks out; --check <name> also counts that pending
#   check, required or not (repeatable). `checks_pending` lists every pending check by name,
#   counted or not: which one is a review bot's own is the caller's judgement.
#   The exit codes fit run-after's wait-until.sh:
#     wait-until.sh --timeout <s> -- bash pr-state.sh <number> --in-flight
set -e

usage() { echo "usage: pr-state.sh <number> [<number> ...] [--in-flight [--no-required] [--check <name>]...]" >&2; exit 2; }

in_flight=0; no_required=0; prs=()
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
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

threads_helper="$(dirname "$0")/../../triage-github-pr/scripts/review-threads.sh"
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

  echo "null" > "$tmp/threads.json"; echo "null" > "$tmp/rounds.json"
  if [ "$in_flight" = 0 ]; then
    if [ ! -f "$threads_helper" ] || ! bash "$threads_helper" "$repo" "$n" > "$tmp/threads.raw"; then
      [ -f "$threads_helper" ] || echo "triage-github-pr/scripts/review-threads.sh is not installed beside closeout" >&2
      echo threads >> "$tmp/unchecked"
    else
      jq '[.[] | select(.resolved | not)] | length' "$tmp/threads.raw" > "$tmp/threads.json"
    fi

    # A round is a push to the head branch after the PR opened. The feed lives in the head
    # repository: the fork, for a fork PR.
    feed=$(jq -r 'if .headRepositoryOwner.login and .headRepository.name
                  then "repos/\(.headRepositoryOwner.login)/\(.headRepository.name)/activity?ref=refs/heads/\(.headRefName | @uri | gsub("%2F"; "/"))&activity_type=push&per_page=100"
                  else "" end' "$tmp/pr.json")
    if [ -z "$feed" ] || ! gh api --paginate "$feed" > "$tmp/activity.raw" \
       || ! jq -s --slurpfile pr "$tmp/pr.json" '[.[][] | select(.timestamp > $pr[0].createdAt)] | length' "$tmp/activity.raw" > "$tmp/rounds.json" 2>/dev/null; then
      echo "null" > "$tmp/rounds.json"; echo rounds >> "$tmp/unchecked"
    fi
  fi

  jq --slurpfile d "$tmp/detail.json" --slurpfile reactions "$tmp/reactions.json" \
     --slurpfile threads "$tmp/threads.json" --slurpfile rounds "$tmp/rounds.json" \
     --rawfile unchecked "$tmp/unchecked" --rawfile names "$tmp/check-names" \
     --argjson in_flight "$in_flight" --argjson no_required "$no_required" '
    def outcome:
      if (.status // "COMPLETED" | ascii_upcase) != "COMPLETED" then "PENDING"
      else (.conclusion // .state // "") | ascii_upcase end;
    def lines: split("\n") | map(select(. != ""));
    ($d[0].data.repository) as $r
    | (if $r then [$r.pullRequest.statusCheckRollup.contexts.nodes[]? | {name: (.name // .context), required: .isRequired}] else null end) as $req
    | def required($n): if $req == null then null
        else ([$req[] | select(.name == $n) | .required] | if length == 0 then null else any end) end;
      [.reviewRequests[]? | (.login // .slug // .name)] as $reviewers
    | ([.statusCheckRollup[]? | select(outcome | IN("", "PENDING", "QUEUED", "IN_PROGRESS", "EXPECTED", "WAITING", "REQUESTED")) | (.name // .context)]
       | unique | map({name: ., required: required(.)})) as $pending
    | if $in_flight == 1 then
        ([$reviewers[] | "reviewer \(.)"]
         + [$reactions[0][]? | select(.content == "eyes") | "reaction \(.user) eyes"]
         + [$pending[] | select((.required == true and $no_required == 0) or (.name | IN($names | lines | .[]))) | "check \(.name)"]) as $counted
        | {pr: .number, in_flight: ($counted | length > 0), reviewers: $reviewers, bot_reactions: $reactions[0],
           checks_pending: $pending, counted: $counted}
      else
        {number, url, title, state, draft: .isDraft,
         head: .headRefName, head_sha: .headRefOid, base: .baseRefName,
         mergeable, merge_state: .mergeStateStatus,
         review: (if .reviewDecision == "" then null else .reviewDecision end),
         cross_repo: .isCrossRepository, maintainer_can_modify: .maintainerCanModify,
         requested_reviewers: $reviewers,
         bot_reactions: $reactions[0],
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
