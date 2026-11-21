#!/bin/bash
# The one gateway to a pull request's review state on GitHub. It owns the review-thread
# query, the agent's comment markers, thread grouping, the owner flag, and the disposition
# comment, so no skill writes a raw `gh api` call or a marker by hand.
#
# Usage: pr.sh state <number> [<number> ...] [--in-flight [--no-required] [--check <name>]...]
#        pr.sh comments <pr> [--repo OWNER/REPO] [--since <earlier output.json>] [--count]
#        pr.sh reply <pr> <file.json> [--repo OWNER/REPO]
#        pr.sh disposition <pr> <body.md> [--repo OWNER/REPO]
# Run from inside the repository the PR belongs to (`state` needs it; the others take --repo).
# `state` and `comments` are read-only; `reply` and `disposition` write to GitHub.
# Every subcommand needs gh and jq, prints JSON on stdout, and exits 2 on a usage error.
#
# Markers. The agent posts from its user's login, so its comments carry an HTML marker:
#   <!-- agent-reply -->         appended by `reply` to every reply body
#   <!-- triage-disposition -->  put on the first line by `disposition` (an older run's
#                                <!-- triage-round: N --> is read too, and replaced on write)
#
# ---------------------------------------------------------------------------------------
# state: the PR gate snapshot, one JSON array on stdout, one row per PR:
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
# state --in-flight  Is a review or a required check still running? Prints one line, a JSON
#   array of {"pr", "in_flight", "reviewers", "bot_reactions", "reviews_owed", "checks_pending", "counted"}
#   and exits 0 when nothing is in flight on any PR, 1 when something is, 2 on any error
#   (a failed read, or a short required-check list: unknown is never "clear").
#   Counted: every requested reviewer, every bot `eyes` reaction, every review owed, a PR
#   pushed, opened, or marked ready under PR_STATE_SETTLE seconds ago (default 120: bots take
#   up to a minute to register one), and every pending required check. It skips the review-thread query.
#   --no-required leaves required checks out; --check <name> also counts that pending check,
#   required or not (repeatable). `checks_pending` lists every pending check by name,
#   counted or not: which one is a review bot's own is the caller's judgement.
#   The exit codes fit run-after's wait-until.sh:
#     wait-until.sh --timeout <s> -- bash pr.sh state <number> --in-flight
#
# ---------------------------------------------------------------------------------------
# comments: the three comment surfaces in one read-only pass, as one JSON object:
#   pr, head (headRefOid), me (your login), pr_author (the PR author's login),
#   threads_open (unresolved review threads),
#   reviews  [{id, user, bot, assoc, agent, owner, state, commit, at, body}]   at = submitted_at
#   threads  [{thread, resolved, root, path, line, commit, url, agent_reply, comments: [
#              {id, user, bot, assoc, agent, owner, line, commit, at, url, body}]}]
#   issue    [{id, user, bot, assoc, agent, owner, at, url, body}]              at = updated_at
#   disposition {id, url, body} | null
# Every row:
#   bot    the author is a GitHub App or bot account (user.type "Bot")
#   assoc  the author's author_association (OWNER, MEMBER, COLLABORATOR, CONTRIBUTOR, NONE, ...)
#   agent  an agent wrote it under your login: it is yours (never anyone else's, since a
#          marker can be pasted) and carries the agent-reply or disposition marker, or it
#          is your unmarked inline reply opening with an agent reply form ("Fixed in",
#          "Reviewed,", "Left as is", "repeat of", "decided by owner"), from before the
#          marker existed. false for everything when `me` is "".
#   owner  a human owner wrote it: not bot, not agent, and your login or assoc OWNER,
#          MEMBER, or COLLABORATOR. The PR author alone is not enough (an outside
#          contributor's fork PR). An owner's answer is a direction.
# threads: every inline comment grouped into its review thread, threads by root id, each
#   thread's comments oldest first (the root first). `thread` is the GraphQL id (PRRT_...)
#   that resolves it, null when the thread query did not map it; `root` is the comment id a
#   reply goes to; path, line, commit, and url are the root's (line falls back to
#   original_line); `agent_reply` is the url of the newest agent comment in it, or null.
# disposition: your newest issue comment carrying the disposition marker (an older run's
#   triage-round marker counts), with or without --since. null also when `me` is "" (the
#   login lookup failed): not checked.
#   --since  keep only rows new or edited since that snapshot: an id not in it, or an id
#            whose `at` changed (bots edit summaries in place). Agent rows are dropped; your
#            user's own comments are kept. A thread is kept, whole, when any of its comments
#            is new, and each of its comments then carries `new` (true or false).
#            Snapshots from the older flat `inline` format still read.
#   --count  print only {"pr","head","threads_open"}: the re-query before a push or merge.
# Save a full run to a file as the snapshot (`> <scratch>/pr-<N>-snapshot.json`).
#
# ---------------------------------------------------------------------------------------
# reply: reply to review threads and resolve them, a whole batch in one run. One reply per
# item, then one resolveReviewThread mutation per item that asks for it. Bodies are read from
# the JSON file and sent as a JSON request body, so no shell quoting touches them.
#   <file.json>  [{"comment_id": 123, "thread": "PRRT_..." | null, "body": "..." | null, "resolve": true | false}]
#     comment_id  the thread's `root` in the comments output
#     thread      the thread's `thread`; needed only to resolve
#     body        the reply text, posted with the agent-reply marker appended. An explicit
#                 `"body": null` makes the item resolve-only: no reply is posted; it needs
#                 `thread` and `"resolve": true`
#     resolve     true resolves the thread after the reply; false (or absent) leaves it open
#   The whole file is checked before the first write: a non-numeric comment_id, an empty or
#   absent body, a null body without `resolve: true`, a non-boolean resolve, or `resolve: true`
#   without a thread exits 2 with nothing sent.
# Output: {"pr": N, "replies": [{"comment_id", "reply_url": "..." | null, "replied": bool,
#          "resolved": bool, "error": null | "..."}], "threads_open": n | null}
#   `replied` is true when this run posted the item's reply (`reply_url` may still be null:
#   GitHub accepted the reply but the response had no html_url). A failed reply skips its
#   resolve (an unanswered thread is never resolved) and the run goes on to the next item.
#   `threads_open` is re-queried once at the end; null when that query failed: not checked.
# Exit: 0 every item sent, 1 any item has an `error`, 2 usage or an invalid file.
# Retry after exit 1, items with an `error` only, never the whole file:
#   `replied: false`                    send the item again as it was
#   `replied: true, resolved: false`    the reply is on GitHub: send it resolve-only
#                                       (`"body": null`, same thread, `"resolve": true`)
#   An `error` on the resolve means no write access or a stale thread id: run `comments`
#   again for the thread id first.
#
# ---------------------------------------------------------------------------------------
# disposition: create or update your one disposition comment on the PR from a markdown file.
#   The disposition marker is put on the first line (any marker already in the file is
#   dropped first, an older triage-round one included); write the body without it.
#   It edits your newest comment carrying the marker, or posts a new one when you have none.
#   A body that @-mentions anyone exits 2 with nothing sent: a mention notifies, and
#   mentioning a review bot starts a review. Write the login without the @, or put it (or
#   code such as `@param`) in backticks.
#   When your login cannot be read it exits 1 with nothing sent (it could not find the
#   comment to edit, and a second one would split the record).
# Output: {"pr": N, "id": <comment id>, "url": "...", "action": "created" | "updated"}
# Exit: 0 written, 1 a read or the write failed, 2 usage or an invalid body.
#
# pipefail: every `gh api … | jq -s .` must fail when gh does, or a 403 reads as "no threads".
# This file is self-contained on purpose: a sourced helper would need a path computed at
# run time, which the plugin directory refuses in a pre-approved script.
set -e
set -o pipefail

AGENT_MARK='<!-- agent-reply -->'
DISPOSITION_MARK='<!-- triage-disposition -->'

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

usage_all() {
  cat >&2 <<'USAGE'
usage: pr.sh state <number> [<number> ...] [--in-flight [--no-required] [--check <name>]...]
       pr.sh comments <pr> [--repo OWNER/REPO] [--since <file>] [--count]
       pr.sh reply <pr> <file.json> [--repo OWNER/REPO]
       pr.sh disposition <pr> <body.md> [--repo OWNER/REPO]
USAGE
}

need_tools() {
  command -v gh >/dev/null || { echo "gh is required" >&2; exit 1; }
  command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
}

# Every review thread of the PR, all pages, as one JSON array on stdout:
#   [{"thread": "PRRT_...", "resolved": bool, "ids": [<comment databaseId>, ...]}]
# `ids` holds every comment in the thread, so a reply maps to its thread as well as the root.
# Fails (never an empty list) when gh fails or a page lacks the thread list, so a 403 never
# reads as "no threads".
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

# Row classification, shared by `comments` and `disposition`. Needs $agent_mark, $me, $author.
# shellcheck disable=SC2016  # jq variables, not shell ones
ROWS_JQ='
def own_mark: test("<!-- triage-(?:disposition|round: [0-9]+) -->");
def legacy_reply: test("^\\s*(?:fixed in|reviewed,|left as is|repeat of|decided by owner)"; "i");
def mine: $me != "" and .user == $me;
def tag:
  (.body // "") as $b
  | mine as $mine
  # Markers count only on your own comments: anyone can paste one into theirs.
  | ($mine and (($b | contains($agent_mark)) or ($b | own_mark)
                or (.reply_to != null and ($b | legacy_reply)))) as $agent
  | del(.body)
  + {agent: $agent,
     owner: ((.bot | not) and ($agent | not)
             and ($mine or (.assoc // "" | IN("OWNER", "MEMBER", "COLLABORATOR"))))}
  + {body: $b};
def disposition_of: [.[] | select(mine and (.body // "" | own_mark))] | last;
'

resolve_repo() { # <repo or "">: prints OWNER/REPO
  local r=$1
  [ -n "$r" ] || r=$(gh repo view --json nameWithOwner -q .nameWithOwner)
  case "$r" in */*) printf '%s\n' "$r" ;; *) echo "could not resolve OWNER/REPO" >&2; exit 2 ;; esac
}

# ---------------------------------------------------------------------------------------
cmd_state() {
  local in_flight=0 no_required=0 settle errors=0 i=0 n out repo head feed
  local prs=()
  settle=${PR_STATE_SETTLE:-120}
  : > "$tmp/check-names"
  mkdir -p "$tmp/rows"
  while [ $# -gt 0 ]; do
    case "$1" in
      --in-flight) in_flight=1 ;;
      --no-required) no_required=1 ;;
      --check) [ -n "${2:-}" ] || { usage_all; exit 2; }; printf '%s\n' "$2" >> "$tmp/check-names"; shift ;;
      -*) echo "Unknown arg: $1" >&2; usage_all; exit 2 ;;
      *) [[ "$1" =~ ^[0-9]+$ ]] || { echo "not a PR number: $1" >&2; usage_all; exit 2; }; prs+=("$1") ;;
    esac
    shift
  done
  [ ${#prs[@]} -gt 0 ] || { usage_all; exit 2; }
  if [ "$in_flight" = 0 ] && { [ "$no_required" = 1 ] || [ -s "$tmp/check-names" ]; }; then
    echo "--no-required and --check need --in-flight" >&2; usage_all; exit 2
  fi
  need_tools

  for n in "${prs[@]}"; do
    i=$((i + 1))
    out="$tmp/rows/$(printf %03d "$i").json"
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
      jq -sc . "$tmp"/rows/*.json
      exit 2
    fi
    jq -sc . "$tmp"/rows/*.json
    jq -se 'any(.[]; .in_flight) | not' "$tmp"/rows/*.json >/dev/null || exit 1
    exit 0
  fi
  jq -s . "$tmp"/rows/*.json
}

# ---------------------------------------------------------------------------------------
cmd_comments() {
  local pr="" repo="" since="" count=0 delta=true
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo)  [ -n "${2:-}" ] || { echo "--repo needs OWNER/REPO" >&2; exit 2; }; repo=$2; shift ;;
      --since) [ -f "${2:-}" ] || { echo "--since needs an existing snapshot file" >&2; exit 2; }; since=$2; shift ;;
      --count) count=1 ;;
      -*) echo "Unknown arg: $1" >&2; exit 2 ;;
      *) [ -z "$pr" ] || { usage_all; exit 2; }; pr=$1 ;;
    esac
    shift
  done
  [[ "$pr" =~ ^[0-9]+$ ]] || { usage_all; exit 2; }
  need_tools
  repo=$(resolve_repo "$repo")

  echo ">> PR #$pr in $repo" >&2
  gh pr view "$pr" -R "$repo" --json headRefOid -q .headRefOid > "$tmp/head"
  review_threads "$repo" "$pr" > "$tmp/threads.json"

  if [ "$count" = 1 ]; then
    jq -n --argjson pr "$pr" --arg head "$(cat "$tmp/head")" --slurpfile t "$tmp/threads.json" \
      '{pr: $pr, head: $head, threads_open: ([$t[0][] | select(.resolved | not)] | length)}'
    return 0
  fi

  gh pr view "$pr" -R "$repo" --json author -q .author.login > "$tmp/author"
  gh api user --jq .login > "$tmp/me" 2>/dev/null || { echo ">> gh api user failed; own comments are not recognised" >&2; : > "$tmp/me"; }
  gh api "repos/$repo/pulls/$pr/reviews" --paginate \
    --jq '.[] | {id, user: .user.login, bot: (.user.type == "Bot"), assoc: .author_association, state, commit: (.commit_id // "")[:8], at: .submitted_at, body}' | jq -s . > "$tmp/reviews.json"
  gh api "repos/$repo/pulls/$pr/comments" --paginate \
    --jq '.[] | {id, user: .user.login, bot: (.user.type == "Bot"), assoc: .author_association, path, line: (.line // .original_line), commit: (.commit_id // "")[:8], at: .updated_at, reply_to: .in_reply_to_id, url: .html_url, body}' | jq -s . > "$tmp/inline.json"
  gh api "repos/$repo/issues/$pr/comments" --paginate \
    --jq '.[] | {id, user: .user.login, bot: (.user.type == "Bot"), assoc: .author_association, at: .updated_at, url: .html_url, body}' | jq -s . > "$tmp/issue.json"

  if [ -z "$since" ]; then
    echo '{}' > "$tmp/since.json"; since="$tmp/since.json"; delta=false
  fi

  jq -n --argjson pr "$pr" --arg head "$(cat "$tmp/head")" --arg me "$(cat "$tmp/me")" --arg author "$(cat "$tmp/author")" \
    --arg agent_mark "$AGENT_MARK" --argjson delta "$delta" \
    --slurpfile t "$tmp/threads.json" --slurpfile r "$tmp/reviews.json" \
    --slurpfile i "$tmp/inline.json" --slurpfile c "$tmp/issue.json" --slurpfile old "$since" "$ROWS_JQ"'
    def key: "\(.id)@\(.at)";
    def seen($rows): [$rows[] | key];
    def fresh($seen): (.agent | not) and (key | IN($seen[]) | not);
    ($t[0]) as $threads
    | seen([$old[0].reviews[]?]) as $seen_reviews
    | seen([$old[0].issue[]?]) as $seen_issue
    | seen([$old[0].inline[]?, $old[0].threads[]?.comments[]?]) as $seen_inline
    | ($r[0] | map(tag)) as $reviews
    | ($c[0] | map(tag)) as $issue
    | ($i[0] | map(tag | . as $x | ([$threads[] | select(any(.ids[]; . == $x.id))][0]) as $th
                   | . + {thread: $th.thread, resolved: $th.resolved})) as $inline
    | ($inline
       | group_by(.reply_to // .id)
       | map(sort_by(.id)
             | ((map(select(.reply_to == null)) | first) // first) as $root
             | (map(select(.thread != null)) | first) as $mapped
             | {thread: $mapped.thread, resolved: $mapped.resolved, root: $root.id,
                path: $root.path, line: $root.line, commit: $root.commit, url: $root.url,
                agent_reply: ([.[] | select(.agent) | .url] | last),
                comments: map(del(.thread, .resolved, .path, .reply_to)
                              | if $delta then . + {new: fresh($seen_inline)} else . end)})
       | sort_by(.root)
       | if $delta then map(select(any(.comments[]; .new))) else . end) as $grouped
    | {pr: $pr, head: $head, me: $me, pr_author: $author,
       threads_open: ([$threads[] | select(.resolved | not)] | length),
       reviews: (if $delta then $reviews | map(select(fresh($seen_reviews))) else $reviews end),
       threads: $grouped,
       issue: (if $delta then $issue | map(select(fresh($seen_issue))) else $issue end),
       disposition: ($issue | disposition_of | if . then {id, url, body} else null end)}'
}

# ---------------------------------------------------------------------------------------
cmd_reply() {
  local pr="" file="" repo="" count i failed=0 id thread resolve resolve_only url replied resolved error open
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) [ -n "${2:-}" ] || { echo "--repo needs OWNER/REPO" >&2; exit 2; }; repo=$2; shift ;;
      -*) echo "Unknown arg: $1" >&2; exit 2 ;;
      *) if [ -z "$pr" ]; then pr=$1; elif [ -z "$file" ]; then file=$1; else usage_all; exit 2; fi ;;
    esac
    shift
  done
  [[ "$pr" =~ ^[0-9]+$ ]] || { usage_all; exit 2; }
  [ -n "$file" ] || { usage_all; exit 2; }
  [ -f "$file" ] || { echo "no such file: $file" >&2; exit 2; }
  need_tools

  # Validate everything before the first write.
  if ! jq -r '
    if type != "array" then "the file must hold a JSON array"
    elif length == 0 then "the array is empty: nothing to send"
    else to_entries[] | .key as $i | .value as $v
      | (if ($v | type) != "object" then "is not an object"
         elif (($v.comment_id | type) == "number" and $v.comment_id > 0 and ($v.comment_id | floor) == $v.comment_id
               or (($v.comment_id | type) == "string" and ($v.comment_id | test("^(?:[0-9]+$)")))) | not
           then "comment_id must be a number"
         elif ($v | has("body")) and $v.body == null and $v.resolve != true
           then "body is null (resolve-only) but resolve is not true"
         elif (($v | has("body")) and $v.body == null) | not
              and ((($v.body | type) == "string" and ($v.body | test("\\S"))) | not)
           then "body must be a non-empty string"
         elif ($v | has("resolve")) and ($v.resolve | type) != "boolean" then "resolve must be true or false"
         elif ($v.thread != null) and ((($v.thread | type) == "string" and ($v.thread | test("^(?:[A-Za-z0-9_=-]+$)"))) | not)
           then "thread must be a thread id (PRRT_...) or null"
         elif $v.resolve == true and $v.thread == null then "resolve is true but thread is null"
         else empty end)
      | "item \($i): \(.)"
    end' "$file" > "$tmp/invalid" 2> "$tmp/parse-error"; then
    echo "invalid JSON in $file: $(cat "$tmp/parse-error")" >&2
    exit 2
  fi
  if [ -s "$tmp/invalid" ]; then
    cat "$tmp/invalid" >&2
    echo "nothing was sent" >&2
    exit 2
  fi

  repo=$(resolve_repo "$repo")
  mkdir -p "$tmp/rows"
  count=$(jq length "$file")
  echo ">> $count items on PR #$pr in $repo" >&2
  i=0
  while [ "$i" -lt "$count" ]; do
    jq --argjson i "$i" '.[$i]' "$file" > "$tmp/item.json"
    id=$(jq -r '.comment_id | tostring' "$tmp/item.json")
    thread=$(jq -r '.thread // ""' "$tmp/item.json")
    resolve=$(jq -r '.resolve // false' "$tmp/item.json")
    resolve_only=$(jq -r '.body == null' "$tmp/item.json")
    url=""; replied=false; resolved=false; error=""

    if [ "$resolve_only" = true ]; then
      : # the reply is already on GitHub (an earlier run posted it); only the resolve is sent
    elif jq --arg mark "$AGENT_MARK" '{body: (.body + "\n\n" + $mark)}' "$tmp/item.json" > "$tmp/body.json" \
        && gh api "repos/$repo/pulls/$pr/comments/$id/replies" --input "$tmp/body.json" > "$tmp/reply.json" 2> "$tmp/err"; then
      # An exit-0 POST is a posted reply, with or without an html_url in the response.
      replied=true
      url=$(jq -r '.html_url // ""' "$tmp/reply.json" 2>/dev/null || true)
      [ -n "$url" ] || echo ">> comment $id: reply posted, but the response had no html_url" >&2
    else
      error="reply failed: $(tr '\n' ' ' < "$tmp/err" | cut -c1-300)"
    fi

    if [ -z "$error" ] && [ "$resolve" = true ]; then
      # shellcheck disable=SC2016  # $threadId is a GraphQL variable, not a shell one
      if gh api graphql -f threadId="$thread" -f query='
mutation($threadId: ID!) { resolveReviewThread(input: {threadId: $threadId}) { thread { isResolved } } }' \
          > "$tmp/resolve.json" 2> "$tmp/err"; then
        if [ "$(jq -r '.data.resolveReviewThread.thread.isResolved // false' "$tmp/resolve.json" 2>/dev/null)" = true ]; then
          resolved=true
        else
          error="resolve returned nothing: no write access, or a stale thread id (run pr.sh comments again)"
        fi
      else
        error="resolve failed: $(tr '\n' ' ' < "$tmp/err" | cut -c1-300)"
      fi
    fi

    if [ -n "$error" ]; then
      failed=$((failed + 1))
      echo ">> comment $id: $error" >&2
    fi
    jq -n --slurpfile item "$tmp/item.json" --arg url "$url" --argjson replied "$replied" \
        --argjson resolved "$resolved" --arg error "$error" \
      '{comment_id: ($item[0].comment_id | tonumber),
        reply_url: (if $url == "" then null else $url end),
        replied: $replied,
        resolved: $resolved,
        error: (if $error == "" then null else $error end)}' > "$tmp/rows/$(printf %05d "$i").json"
    i=$((i + 1))
  done

  open=null
  if review_threads "$repo" "$pr" > "$tmp/threads.json" 2> "$tmp/err"; then
    open=$(jq '[.[] | select(.resolved | not)] | length' "$tmp/threads.json")
  else
    echo ">> thread re-query failed; threads_open is not checked: $(tr '\n' ' ' < "$tmp/err" | cut -c1-300)" >&2
  fi

  jq -s --argjson pr "$pr" --argjson open "$open" '{pr: $pr, replies: ., threads_open: $open}' "$tmp"/rows/*.json
  [ "$failed" -eq 0 ] || exit 1
}

# ---------------------------------------------------------------------------------------
cmd_disposition() {
  local pr="" file="" repo="" me id action
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) [ -n "${2:-}" ] || { echo "--repo needs OWNER/REPO" >&2; exit 2; }; repo=$2; shift ;;
      -*) echo "Unknown arg: $1" >&2; exit 2 ;;
      *) if [ -z "$pr" ]; then pr=$1; elif [ -z "$file" ]; then file=$1; else usage_all; exit 2; fi ;;
    esac
    shift
  done
  [[ "$pr" =~ ^[0-9]+$ ]] || { usage_all; exit 2; }
  [ -n "$file" ] || { usage_all; exit 2; }
  [ -f "$file" ] || { echo "no such file: $file" >&2; exit 2; }
  need_tools

  # The body: every marker the file already carries dropped, then the one marker on line 1.
  jq -n --rawfile b "$file" --arg mark "$DISPOSITION_MARK" \
    '{body: ($mark + "\n" + ($b | gsub("<!-- triage-(?:disposition|round: [0-9]+) -->[ \\t]*\\n?"; "") | sub("^\\s+"; "")))}' > "$tmp/body.json"
  if ! jq -e '.body | sub("<!-- triage-disposition -->"; "") | test("\\S")' "$tmp/body.json" >/dev/null; then
    echo "the body is empty: nothing was sent" >&2; exit 2
  fi
  if jq -e '.body | test("(?:^|[\\s(\\[])@[A-Za-z0-9]")' "$tmp/body.json" >/dev/null; then
    echo "the body @-mentions $(jq -r '[.body | match("(?:^|[\\s(\\[])(@[A-Za-z0-9][A-Za-z0-9_-]*)"; "g") | .captures[0].string] | unique | join(", ")' "$tmp/body.json"): a mention notifies, and a review bot's starts a review. Write the login without the @, or put it in backticks; nothing was sent" >&2
    exit 2
  fi

  repo=$(resolve_repo "$repo")
  if ! me=$(gh api user --jq .login 2> "$tmp/err") || [ -z "$me" ]; then
    echo "could not read your login, so the comment to edit is unknown; nothing was sent: $(tr '\n' ' ' < "$tmp/err" | cut -c1-300)" >&2
    exit 1
  fi
  if ! gh api "repos/$repo/issues/$pr/comments" --paginate \
      --jq '.[] | {id, user: .user.login, url: .html_url, body}' > "$tmp/issue.raw" 2> "$tmp/err"; then
    echo "could not read the PR's comments; nothing was sent: $(tr '\n' ' ' < "$tmp/err" | cut -c1-300)" >&2
    exit 1
  fi
  id=$(jq -rs --arg me "$me" --arg author "" --arg agent_mark "$AGENT_MARK" "$ROWS_JQ"'disposition_of | .id // ""' "$tmp/issue.raw")

  if [ -n "$id" ]; then
    action=updated
    gh api -X PATCH "repos/$repo/issues/comments/$id" --input "$tmp/body.json" > "$tmp/out.json" 2> "$tmp/err" \
      || { echo "update of comment $id failed: $(tr '\n' ' ' < "$tmp/err" | cut -c1-300)" >&2; exit 1; }
  else
    action=created
    gh api -X POST "repos/$repo/issues/$pr/comments" --input "$tmp/body.json" > "$tmp/out.json" 2> "$tmp/err" \
      || { echo "posting the disposition failed: $(tr '\n' ' ' < "$tmp/err" | cut -c1-300)" >&2; exit 1; }
  fi
  echo ">> disposition $action on PR #$pr in $repo" >&2
  jq --argjson pr "$pr" --arg action "$action" --arg id "$id" \
    '{pr: $pr, id: (.id // ($id | tonumber? // null)), url: (.html_url // null), action: $action}' "$tmp/out.json"
}

sub=${1:-}
[ $# -eq 0 ] || shift
case "$sub" in
  state) cmd_state "$@" ;;
  comments) cmd_comments "$@" ;;
  reply) cmd_reply "$@" ;;
  disposition) cmd_disposition "$@" ;;
  -h|--help|help) usage_all; exit 0 ;;
  *) [ -z "$sub" ] || echo "unknown subcommand: $sub" >&2; usage_all; exit 2 ;;
esac
