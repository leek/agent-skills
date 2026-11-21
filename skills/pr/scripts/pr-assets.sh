#!/bin/bash
# The orphan `pr-assets` branch that holds PR screenshots, one folder per PR branch, written
# without touching the working tree, index, or current branch. Run inside the repo.
#
# Usage:
#   pr-assets.sh upload <pr-branch> <image>...
#       Commit the images to pr-assets/<folder>/ and push. Stdout: one Markdown image line per
#       file, linked through the branch path, so it keeps working until `prune` drops that
#       folder. Each file is stored as <content hash>-<name>, so a re-shot image never
#       replaces an earlier one another PR body still shows. A push that loses a race retries
#       (3 attempts).
#   pr-assets.sh plan [--days N]
#       Change nothing; list the folders. A folder is a candidate only when every PR whose head
#       branch maps to it is merged or closed more than N days ago (default 90), or, with no
#       such PR, its last upload is that old. A folder with an open PR is never a candidate.
#       Stdout: JSON {"tip","days","bytes","candidates":[{"folder","bytes","reason"}],
#                     "kept":[{"folder","bytes","reason"}]}   (tip null: no pr-assets branch)
#   pr-assets.sh prune [--days N] --tip <sha> --drop <folder> [--drop <folder>]...
#       Rewrite pr-assets as a fresh orphan commit holding every folder not dropped, pushed
#       with a lease on --tip, so the clone size really shrinks. --tip must be the plan's tip
#       and every --drop a candidate in this run's plan; one that is not, or a remote that
#       moved before the push lands, stops the run with nothing changed (exit 1).
#       Stdout: JSON {"tip":<new sha>,"dropped":[folders],"freed_bytes"}
#       Links of the form .../blob/pr-assets/<folder>/<file> keep working for kept folders.
#       Links pinned to a commit (.../blob/<sha>/...) then point at unreachable commits:
#       GitHub may keep serving them, or stop once it garbage-collects.
# Needs git, gh, jq. Exit 2 on a usage error.
set -e

REF=refs/heads/pr-assets

# The one branch -> folder encoder: one `-` per character outside [A-Za-z0-9._-], in any
# locale (jq works on code points, where `tr` under LC_ALL=C would work on bytes). `upload`
# names a folder with it and `plan` maps each PR's headRefName with it.
FOLDER_JQ='def folder: gsub("[^A-Za-z0-9._-]"; "-");'

usage() {
  echo "usage: pr-assets.sh upload <pr-branch> <image>... | plan [--days N] | prune [--days N] --tip <sha> --drop <folder>..." >&2
  exit 2
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
index="$tmp/index"

# --- git plumbing on a private index -------------------------------------------------------

idx() { GIT_INDEX_FILE="$index" git "$@"; }

# Fetch pr-assets; print its tip, or nothing when the branch does not exist yet.
fetch_tip() {
  if git fetch -q origin pr-assets 2>/dev/null; then
    git rev-parse FETCH_HEAD
  fi
}

# Start the private index from <tree-ish>, or empty with no argument.
index_reset() {
  rm -f "$index"
  if [ -n "$1" ]; then idx read-tree "$1"; else idx read-tree --empty; fi
}

# Commit the private index; print the commit. <parent> empty makes an orphan commit.
index_commit() { # <parent> <message>
  local tree
  tree="$(idx write-tree)"
  git commit-tree "$tree" ${1:+-p "$1"} -m "$2"
}

# Move pr-assets to <commit> only if the remote still holds <expected> (empty: must not
# exist). Prints git's output (the refusal, if any) on stdout for the caller to classify.
push_leased() { # <commit> <expected>
  git push -q --force-with-lease="$REF:$2" origin "$1:$REF" 2>&1
}

# A push refused because the remote moved under us (lease, non-fast-forward, ref lock).
moved_error() {
  case "$1" in
    *non-fast-forward*|*"fetch first"*|*"stale info"*|*"cannot lock ref"*|*"reference already exists"*|*"failed to update ref"*) return 0 ;;
  esac
  return 1
}

# --- upload --------------------------------------------------------------------------------

# Percent-encode a file name for the URL: a space in a Markdown link target breaks the image.
urlencode() {
  local hex out=""
  for hex in $(printf '%s' "$1" | od -An -tx1); do
    case "$hex" in
      2d|2e|5f|7e|3[0-9]|4[1-9a-f]|5[0-9a]|6[1-9a-f]|7[0-9a]) out="$out$(printf "\\x$hex")" ;;
      *) out="$out%$(printf '%s' "$hex" | tr 'a-f' 'A-F')" ;;
    esac
  done
  printf '%s' "$out"
}

cmd_upload() {
  local branch="$1" repo dir attempt parent f blob commit err name
  [ -n "$branch" ] || usage
  shift
  [ "$#" -gt 0 ] || { echo "no images given" >&2; exit 2; }
  for f in "$@"; do [ -f "$f" ] || { echo "not a file: $f" >&2; exit 1; }; done

  repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
  dir="$(jq -rn --arg b "$branch" "$FOLDER_JQ"' $b | folder')"

  for attempt in 1 2 3; do
    parent="$(fetch_tip)"
    index_reset "$parent"
    for f in "$@"; do
      blob="$(git hash-object -w -- "$f")"
      idx update-index --add --cacheinfo "100644,$blob,$dir/${blob:0:8}-$(basename "$f")"
    done
    commit="$(index_commit "$parent" "screenshots: $branch")"

    if err="$(push_leased "$commit" "$parent")"; then
      echo "pushed $# screenshot(s) to pr-assets/$dir" >&2
      for f in "$@"; do
        name="$(basename "$f")"
        blob="$(git hash-object -- "$f")"
        echo "![${name%.*}](https://github.com/$repo/blob/pr-assets/$dir/${blob:0:8}-$(urlencode "$name")?raw=true)"
      done
      exit 0
    fi
    if moved_error "$err"; then
      echo "pr-assets moved; retrying ($attempt)" >&2
    else
      printf '%s\n' "$err" >&2
      exit 1
    fi
  done
  printf '%s\n' "$err" >&2
  echo "could not push pr-assets after 3 attempts" >&2
  exit 1
}

# --- plan / prune --------------------------------------------------------------------------

# One JSON row per top-level folder of <tip> into $tmp/rows:
#   {"folder","bytes","candidate","reason"}
plan_rows() { # <tip> <days>
  local tip="$1" cutoff dir bytes last
  cutoff=$(( $(date +%s) - $2 * 86400 ))
  gh pr list --state open --limit 1000 --json number,headRefName,state,closedAt > "$tmp/open.json"
  gh pr list --state all --limit 1000 --json number,headRefName,state,closedAt > "$tmp/all.json"
  jq -n --slurpfile o "$tmp/open.json" --slurpfile a "$tmp/all.json" \
    "$FOLDER_JQ"' ($o[0] + $a[0]) | unique_by(.number) | map(.folder = (.headRefName | folder))' > "$tmp/prs.json"
  : > "$tmp/rows"
  git ls-tree -d --name-only "$tip" | while IFS= read -r dir; do
    bytes="$(git ls-tree -r -l "$tip" -- "$dir" | awk '{ s += $4 } END { print s + 0 }')"
    last="$(git log -1 --format=%ct "$tip" -- "$dir")"
    jq -c --arg d "$dir" --argjson bytes "$bytes" \
      --argjson last "${last:-0}" --argjson cutoff "$cutoff" '
      [.[] | select(.folder == $d)] as $m
      | ($m | map(select(.state == "OPEN"))) as $open
      | ($m | map(.closedAt // empty | fromdateiso8601) | max) as $closed
      | (if ($open | length) > 0 then
           {candidate: false, reason: "open PR #\($open[0].number)"}
         elif ($m | length) > 0 then
           ($m | max_by(.closedAt // "")) as $latest
           | if $closed != null then
               {candidate: ($closed < $cutoff),
                reason: "PR #\($latest.number) \($latest.state | ascii_downcase) \($closed | todate | .[0:10])"}
             else
               {candidate: ($last < $cutoff),
                reason: "PR #\($latest.number) \($latest.state | ascii_downcase) (no close date), last upload \($last | todate | .[0:10])"}
             end
         else
           {candidate: ($last < $cutoff), reason: "no PR found, last upload \($last | todate | .[0:10])"}
         end) as $v
      | {folder: $d, bytes: $bytes, candidate: $v.candidate, reason: $v.reason}' "$tmp/prs.json" >> "$tmp/rows"
  done
}

cmd_plan_or_prune() { # <plan|prune> [args]
  local mode="$1" days=90 tip_arg="" tip d drop_json commit err meta entry type sha mode_bits
  local drops=()
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --days) days="${2:?--days needs a number}"; shift 2 ;;
      --tip) [ "$mode" = prune ] || usage; tip_arg="${2:?--tip needs a sha}"; shift 2 ;;
      --drop) [ "$mode" = prune ] || usage; drops+=("${2:?--drop needs a folder}"); shift 2 ;;
      --dry-run) [ "$mode" = plan ] || usage; shift ;;
      *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
  done
  case "$days" in '' | *[!0-9]*) echo "--days must be a whole number" >&2; exit 2 ;; esac
  if [ "$mode" = prune ] && { [ -z "$tip_arg" ] || [ "${#drops[@]}" -eq 0 ]; }; then
    echo "prune needs --tip <the plan's tip> and at least one --drop <folder>" >&2; exit 2
  fi

  tip="$(fetch_tip)"
  if [ -z "$tip" ]; then
    [ "$mode" = plan ] || { echo "no pr-assets branch on origin (nothing changed)" >&2; exit 1; }
    jq -n --argjson days "$days" '{tip: null, days: $days, bytes: 0, candidates: [], kept: []}'
    exit 0
  fi
  if [ -n "$tip_arg" ] && [ "$(git rev-parse "$tip_arg^{commit}" 2>/dev/null)" != "$tip" ]; then
    echo "pr-assets moved since the plan (now $tip): list again (nothing changed)" >&2; exit 1
  fi

  plan_rows "$tip" "$days"

  if [ "$mode" = plan ]; then
    jq -s --arg tip "$tip" --argjson days "$days" '{
      tip: $tip, days: $days, bytes: (map(.bytes) | add // 0),
      candidates: map(select(.candidate) | del(.candidate)),
      kept: map(select(.candidate | not) | del(.candidate))}' "$tmp/rows"
    exit 0
  fi

  for d in "${drops[@]}"; do
    jq -e -s --arg d "$d" 'any(.[]; .folder == $d and .candidate)' "$tmp/rows" > /dev/null \
      || { echo "not a candidate: $d (nothing changed)" >&2; exit 1; }
  done
  drop_json="$(printf '%s\n' "${drops[@]}" | jq -R . | jq -s .)"

  index_reset
  git ls-tree "$tip" | while IFS=$'\t' read -r meta entry; do
    mode_bits="$(printf '%s' "$meta" | cut -d' ' -f1)"
    type="$(printf '%s' "$meta" | cut -d' ' -f2)"
    sha="$(printf '%s' "$meta" | cut -d' ' -f3)"
    if [ "$type" = tree ]; then
      printf '%s' "$drop_json" | jq -e --arg p "$entry" 'index($p) != null' > /dev/null && continue
      idx read-tree --prefix="$entry/" "$sha"
    else
      idx update-index --add --cacheinfo "$mode_bits,$sha,$entry"
    fi
  done
  commit="$(index_commit "" "pr-assets: prune ${#drops[@]} folder(s)")"

  if ! err="$(push_leased "$commit" "$tip")"; then
    printf '%s\n' "$err" >&2
    if moved_error "$err"; then
      echo "pr-assets moved since the plan: list again (nothing changed)" >&2
    fi
    exit 1
  fi

  jq -s --arg tip "$commit" --argjson drop "$drop_json" '{
    tip: $tip, dropped: $drop,
    freed_bytes: (map(select(.folder as $f | $drop | index($f) != null) | .bytes) | add // 0)}' "$tmp/rows"
}

case "${1:-}" in
  upload) shift; cmd_upload "$@" ;;
  plan|prune) cmd_plan_or_prune "$@" ;;
  *) usage ;;
esac
