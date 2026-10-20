#!/bin/bash
# Print the git state of each checkout or worktree path, as one JSON array on stdout:
#   path          the path as given
#   branch        the checked-out branch, or null when HEAD is detached
#   upstream      the tracking branch, or null when none is set or its remote branch is gone
#   upstream_gone true when a tracking branch is set but its remote branch was deleted (often a merge)
#   unpushed      commits on HEAD not on unpushed_base, or null when there is no base
#   unpushed_base the upstream, else origin/<branch> (pushed without -u), else origin's default branch
#   operation     merge, rebase, cherry-pick, revert, or null when none is in progress
#   changes       every `git status --porcelain` line, one per untracked file (the caller keeps only its own files)
#
# Usage: git-state.sh <path> [<path> ...]
# A path that is missing or not inside a git repository prints {"path", "error"}.
# Read-only.
set -e

[ $# -gt 0 ] || { echo "usage: git-state.sh <path> [<path> ...]" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

i=0
for p in "$@"; do
  i=$((i + 1))
  out="$tmp/$(printf %03d "$i").json"
  if ! git -C "$p" rev-parse --git-dir >/dev/null 2>&1; then
    jq -n --arg path "$p" '{path: $path, error: "not a git checkout"}' > "$out"
    continue
  fi
  echo "Checking $p..." >&2

  branch=$(git -C "$p" symbolic-ref --quiet --short HEAD || true)
  # On a gone upstream, git prints "@{u}" before failing, so keep the output only on success.
  upstream=$(git -C "$p" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) || upstream=""
  upstream_gone=false
  base="$upstream"
  if [ -z "$base" ] && [ -n "$branch" ]; then
    if git -C "$p" config "branch.$branch.merge" >/dev/null; then
      upstream_gone=true
    fi
    if git -C "$p" rev-parse --verify --quiet "refs/remotes/origin/$branch" >/dev/null; then
      base="origin/$branch"
    fi
  fi
  if [ -z "$base" ]; then
    base=$(git -C "$p" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
  fi
  unpushed=null
  if [ -n "$base" ]; then
    unpushed=$(git -C "$p" rev-list --count "$base..HEAD" 2>/dev/null || echo null)
  fi

  gitdir=$(git -C "$p" rev-parse --absolute-git-dir)
  operation=null
  for pair in MERGE_HEAD:merge rebase-merge:rebase rebase-apply:rebase CHERRY_PICK_HEAD:cherry-pick REVERT_HEAD:revert; do
    if [ -e "$gitdir/${pair%%:*}" ]; then
      operation="\"${pair#*:}\""
      break
    fi
  done

  git -C "$p" status --porcelain --untracked-files=all > "$tmp/$i.status"
  jq -n --arg path "$p" --arg branch "$branch" --arg upstream "$upstream" \
    --argjson upstream_gone "$upstream_gone" --argjson unpushed "$unpushed" --arg base "$base" --argjson operation "$operation" \
    --rawfile status "$tmp/$i.status" \
    '{path: $path,
      branch: (if $branch == "" then null else $branch end),
      upstream: (if $upstream == "" then null else $upstream end),
      upstream_gone: $upstream_gone,
      unpushed: $unpushed,
      unpushed_base: (if $base == "" then null else $base end),
      operation: $operation,
      changes: ($status | split("\n") | map(select(. != "")))}' > "$out"
done

jq -s . "$tmp"/*.json
