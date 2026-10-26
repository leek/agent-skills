#!/bin/bash
# List the folders of the orphan `pr-assets` branch (PR screenshots uploaded by the pr
# skill's upload-screenshots.sh), then drop only the folders a human selected by name.
#
# Run with no arguments, the script changes nothing: it prints the plan. A folder is a
# candidate only when every PR whose head branch maps to it is merged or closed more
# than --days ago (default 90), or, with no such PR, its last upload is that old. A
# folder with an open PR is never a candidate.
#
# Dropping rewrites pr-assets as a fresh orphan commit holding every folder not dropped,
# pushed with a lease on the tip the plan showed, so the clone size really shrinks.
# Links of the form .../blob/pr-assets/<folder>/<file> keep working for kept folders.
# Older links pinned to a commit (.../blob/<sha>/...) then point at unreachable commits:
# GitHub may keep serving them, or stop once it garbage-collects.
#
# Usage: prune-pr-assets.sh [--days N]                       list the plan, change nothing
#        prune-pr-assets.sh [--days N] --tip <sha> --drop <folder> [--drop <folder>]...
# --tip must be the plan's tip, and every --drop a candidate in this run's plan; one
# that is not stops the run before anything changes.
#
# Output, listing: JSON {"tip","days","bytes","candidates":[{"folder","bytes","reason"}],
#   "kept":[{"folder","bytes","reason"}]}
# Output, dropping: JSON {"tip":<new sha>,"dropped":[folders],"freed_bytes"}
set -e

days=90
tip_arg=""
drops=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --days) days="${2:?--days needs a number}"; shift 2 ;;
    --tip) tip_arg="${2:?--tip needs a sha}"; shift 2 ;;
    --drop) drops+=("${2:?--drop needs a folder}"); shift 2 ;;
    --dry-run) shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
case "$days" in '' | *[!0-9]*) echo "--days must be a whole number" >&2; exit 2 ;; esac
if [ "${#drops[@]}" -gt 0 ] && [ -z "$tip_arg" ]; then
  echo "--drop needs --tip <the plan's tip>" >&2; exit 2
fi

if ! git fetch -q origin pr-assets 2>/dev/null; then
  jq -n --argjson days "$days" '{tip: null, days: $days, bytes: 0, candidates: [], kept: []}'
  exit 0
fi
tip="$(git rev-parse FETCH_HEAD)"
if [ -n "$tip_arg" ] && [ "$(git rev-parse "$tip_arg^{commit}" 2>/dev/null)" != "$tip" ]; then
  echo "pr-assets moved since the plan (now $tip): list again" >&2; exit 1
fi

prs="$(gh pr list --state all --limit 1000 --json number,headRefName,state,closedAt)"
cutoff=$(( $(date +%s) - days * 86400 ))

rows="$(mktemp)"
index="$(mktemp)"
trap 'rm -f "$rows" "$index"' EXIT

git ls-tree -d --name-only "$tip" | while IFS= read -r dir; do
  bytes="$(git ls-tree -r -l "$tip" -- "$dir" | awk '{ s += $4 } END { print s + 0 }')"
  last="$(git log -1 --format=%ct "$tip" -- "$dir")"
  printf '%s' "$prs" | jq -c --arg d "$dir" --argjson bytes "$bytes" \
    --argjson last "${last:-0}" --argjson cutoff "$cutoff" '
    [.[] | select((.headRefName | gsub("[^A-Za-z0-9._-]"; "-")) == $d)] as $m
    | ($m | map(select(.state == "OPEN"))) as $open
    | ($m | map(.closedAt // empty | fromdateiso8601) | max) as $closed
    | (if ($open | length) > 0 then
         {candidate: false, reason: "open PR #\($open[0].number)"}
       elif ($m | length) > 0 then
         {candidate: ($closed < $cutoff),
          reason: "PR #\($m | max_by(.closedAt // "") | .number) \($m | max_by(.closedAt // "") | .state | ascii_downcase) \($closed | todate | .[0:10])"}
       else
         {candidate: ($last < $cutoff), reason: "no PR found, last upload \($last | todate | .[0:10])"}
       end) as $v
    | {folder: $d, bytes: $bytes, candidate: $v.candidate, reason: $v.reason}' >> "$rows"
done

if [ "${#drops[@]}" -eq 0 ]; then
  jq -s --arg tip "$tip" --argjson days "$days" '{
    tip: $tip, days: $days, bytes: (map(.bytes) | add // 0),
    candidates: map(select(.candidate) | del(.candidate)),
    kept: map(select(.candidate | not) | del(.candidate))}' "$rows"
  exit 0
fi

for d in "${drops[@]}"; do
  jq -e -s --arg d "$d" 'any(.[]; .folder == $d and .candidate)' "$rows" > /dev/null \
    || { echo "not a candidate: $d (nothing changed)" >&2; exit 1; }
done

drop_json="$(printf '%s\n' "${drops[@]}" | jq -R . | jq -s .)"
rm -f "$index"
GIT_INDEX_FILE="$index" git read-tree --empty
git ls-tree "$tip" | while IFS=$'\t' read -r meta path; do
  type="$(printf '%s' "$meta" | cut -d' ' -f2)"
  sha="$(printf '%s' "$meta" | cut -d' ' -f3)"
  mode="$(printf '%s' "$meta" | cut -d' ' -f1)"
  if [ "$type" = tree ]; then
    printf '%s' "$drop_json" | jq -e --arg p "$path" 'index($p) != null' > /dev/null && continue
    GIT_INDEX_FILE="$index" git read-tree --prefix="$path/" "$sha"
  else
    GIT_INDEX_FILE="$index" git update-index --add --cacheinfo "$mode,$sha,$path"
  fi
done
tree="$(GIT_INDEX_FILE="$index" git write-tree)"
commit="$(git commit-tree "$tree" -m "pr-assets: prune ${#drops[@]} folder(s)")"
git push -q --force-with-lease="refs/heads/pr-assets:$tip" origin "$commit:refs/heads/pr-assets"

jq -s --arg tip "$commit" --argjson drop "$drop_json" '{
  tip: $tip, dropped: $drop,
  freed_bytes: (map(select(.folder as $f | $drop | index($f) != null) | .bytes) | add // 0)}' "$rows"
