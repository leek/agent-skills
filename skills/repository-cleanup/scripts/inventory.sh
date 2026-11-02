#!/bin/bash
# Read-only inventory of a repository's git and GitHub state, as one JSON object, for the
# Workflow's steps 1-3. It changes nothing but remote-tracking refs, through a fetch that
# never prunes: a pruning fetch would delete stale remote-tracking refs and local-only
# tags (an archive/* tag made to preserve work) nobody selected, even when the user's
# config sets fetch.prune or fetch.pruneTags. Stale refs are listed instead.
#
# Usage: inventory.sh [--no-fetch] [--graph <n>]
#   --no-fetch   skip `git fetch --all --no-prune --no-prune-tags`
#   --graph <n>  add the last <n> lines of `git log --all --graph` (off by default)
#
# Output: JSON {
#   "fetched": bool, "base": the ref "merged" is checked against (origin's default branch, else HEAD),
#   "status": {"branch","upstream","ahead","behind","changes":[porcelain lines]},
#   "stashes": [{"ref","subject","files"}],
#   "remotes": [{"name","url"}],
#   "stale_remote_refs": [{"remote","ref"}],
#   "worktrees": [{"path","head","branch","locked","prunable","dirty"}],
#   "branches": [{"name","upstream","upstream_gone","last_commit","merged"}],
#   "prs": {"open":[...],"closed":[last 30]} or null when gh is unavailable,
#   "graph": [lines] (only with --graph)
# }

set -e

fetch=1; graph=0
while [ $# -gt 0 ]; do
  case "$1" in
    --no-fetch) fetch=0 ;;
    --graph) [ -n "${2:-}" ] || { echo "--graph needs a line count" >&2; exit 2; }; graph=$2; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
git rev-parse --git-dir >/dev/null

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
lines() { jq -R . | jq -s .; }   # stdin lines -> JSON array of strings

fetched=false
if [ "$fetch" = 1 ]; then
  echo ">> git fetch --all --no-prune --no-prune-tags" >&2
  if git fetch --all --no-prune --no-prune-tags >&2; then fetched=true; else echo ">> fetch failed; using local refs" >&2; fi
fi

base=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)
[ -n "$base" ] || base=HEAD

# status
{
  ab=$(git rev-list --left-right --count 'HEAD...@{upstream}' 2>/dev/null || true)
  jq -n --arg b "$(git branch --show-current)" --arg u "$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)" \
    --arg ab "$ab" --argjson c "$(git status --porcelain | lines)" \
    '($ab | split("\t")) as $n
     | {branch: ($b | select(. != "") // null), upstream: ($u | select(. != "") // null),
        ahead: (if ($n|length)==2 then ($n[0]|tonumber) else null end),
        behind: (if ($n|length)==2 then ($n[1]|tonumber) else null end), changes: $c}'
} > "$tmp/status.json"

# stashes, each with the files it touches
: > "$tmp/stashes.jsonl"
git stash list --format='%gd%x09%gs' | while IFS=$'\t' read -r ref subject; do
  [ -n "$ref" ] || continue
  jq -n --arg r "$ref" --arg s "$subject" --argjson f "$(git stash show --name-only "$ref" 2>/dev/null | lines)" \
    '{ref: $r, subject: $s, files: $f}' >> "$tmp/stashes.jsonl"
done

# remotes and the stale remote-tracking refs a prune would delete
git remote -v | awk '$3 == "(fetch)" { print $1 "\t" $2 }' | jq -R 'split("\t") | {name: .[0], url: .[1]}' | jq -s . > "$tmp/remotes.json"
: > "$tmp/stale.jsonl"
for r in $(git remote); do
  git remote prune --dry-run "$r" 2>/dev/null | sed -n 's/^ \* \[would prune\] //p' | while read -r ref; do
    jq -n --arg r "$r" --arg f "$ref" '{remote: $r, ref: $f}' >> "$tmp/stale.jsonl"
  done
done

# worktrees
git worktree list --porcelain | awk '
  function flush() { if (p != "") print p "\t" (h ? h : "-") "\t" (b ? b : "-") "\t" l "\t" pr; p = "" }
  /^worktree / { flush(); p = substr($0, 10); h = ""; b = ""; l = 0; pr = 0 }
  /^HEAD /     { h = $2 }
  /^branch /   { b = substr($0, 8); sub("^refs/heads/", "", b) }
  /^locked/    { l = 1 }
  /^prunable/  { pr = 1 }
  END { flush() }' > "$tmp/wt.tsv"
: > "$tmp/wt.jsonl"
while IFS=$'\t' read -r p h b l pr; do
  d=false
  if [ "$pr" = 0 ] && [ -n "$(git -C "$p" status --porcelain 2>/dev/null)" ]; then d=true; fi
  jq -n --arg p "$p" --arg h "$h" --arg b "$b" --argjson l "$l" --argjson pr "$pr" --argjson d "$d" \
    '{path: $p, head: $h, branch: (if $b == "-" then null else $b end), locked: ($l == 1), prunable: ($pr == 1), dirty: $d}' >> "$tmp/wt.jsonl"
done < "$tmp/wt.tsv"

# local branches, with merged-into-base
git branch --merged "$base" --format='%(refname:short)' > "$tmp/merged.txt"
git branch --format='%(refname:short)%09%(upstream:short)%09%(upstream:track)%09%(committerdate:iso8601)' |
  jq -R --rawfile m "$tmp/merged.txt" '
    split("\t") as $f
    | {name: $f[0], upstream: ($f[1] | select(. != "") // null), upstream_gone: ($f[2] == "[gone]"),
       last_commit: $f[3], merged: (($m | split("\n")) | index($f[0]) != null)}' | jq -s . > "$tmp/branches.json"

# pull requests
prs=null
if command -v gh >/dev/null 2>&1; then
  if open=$(gh pr list --state open --json number,title,headRefName,baseRefName,author,updatedAt,url 2>/dev/null) &&
     closed=$(gh pr list --state closed --limit 30 --json number,title,headRefName,baseRefName,author,updatedAt,closedAt,mergedAt,url 2>/dev/null); then
    prs=$(jq -n --argjson o "$open" --argjson c "$closed" '{open: $o, closed: $c}')
  else
    echo ">> gh pr list failed; prs is null (report the PR visibility gap)" >&2
  fi
else
  echo ">> gh not found; prs is null (report the PR visibility gap)" >&2
fi

g=null
if [ "$graph" -gt 0 ] 2>/dev/null; then
  g=$(git log --all --decorate --oneline --graph --date-order -n "$graph" | lines)
fi

jq -n --argjson fetched "$fetched" --arg base "$base" \
  --slurpfile status "$tmp/status.json" --slurpfile stashes "$tmp/stashes.jsonl" \
  --slurpfile remotes "$tmp/remotes.json" --slurpfile stale "$tmp/stale.jsonl" \
  --slurpfile wts "$tmp/wt.jsonl" --slurpfile branches "$tmp/branches.json" \
  --argjson prs "$prs" --argjson graph "$g" \
  '{fetched: $fetched, base: $base, status: $status[0], stashes: $stashes, remotes: $remotes[0],
    stale_remote_refs: $stale, worktrees: $wts, branches: $branches[0], prs: $prs}
   + (if $graph == null then {} else {graph: $graph} end)'
