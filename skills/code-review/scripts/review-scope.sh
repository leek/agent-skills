#!/bin/bash
# Pin a review's scope: resolve the fixed point, list the commits and changed files since
# its merge-base with HEAD, and name the diff's size class. Read-only. Run it inside the
# repository; paths are relative to the current directory, as they are for git.
#
# Usage: review-scope.sh <fixed-point> [--wip] [-- <paths>...]
#   <fixed-point>  a commit SHA, branch, tag, HEAD~5, ...
#   --wip          also cover uncommitted work: staged and unstaged changes, plus
#                  untracked files that are not ignored. The diff is then the working
#                  tree against the merge-base (panel's WIP review, code-smells-audit's
#                  `diff` target).
#   -- <paths>     path scope, appended to both commands.
#
# Stdout: one JSON object
#   {"fixed_point": "main", "fixed_point_sha": "<sha>", "head_sha": "<sha>",
#    "merge_base": "<sha>",
#    "diff_cmd": "git diff main...HEAD [-- <paths>]",   with --wip: "git diff <merge_base> [-- <paths>]"
#    "log_cmd": "git log main..HEAD --oneline [-- <paths>]",
#    "commits": [{"sha": "<sha>", "subject": "..."}],   newest first, as git log prints them
#    "files": ["path", ...],          repo-root-relative, sorted; with --wip includes "untracked"
#    "untracked": ["path", ...],      only with --wip: files diff_cmd does not print
#    "files_changed": n, "lines_changed": n,   insertions + deletions, as `git diff --shortstat`
#                                              counts them, plus every line of an untracked file
#    "empty": bool, "size": "inline" | "fanout" | "split"}
# Stderr: status and errors.
# Exit: 0 a non-empty scope; 1 the fixed point does not resolve (no stdout) or the diff is
#       empty (the object is printed, with "empty": true); 2 usage; 3 no jq or not in a
#       git repository.
#
# Three-dot semantics: the comparison is against the merge-base of the fixed point and
# HEAD, so commits the fixed point gained since the branch forked are not in the diff.
#
# "size" uses the numbers in skills/code-review/SKILL.md step 4, and nothing else:
#   inline  "When step 1's `size` is `inline` (at most 3 files and 150 changed lines),
#           three fresh contexts each re-reading it cost more than they find"
#           -> files_changed <= 3 and lines_changed <= 150
#   split   "When `size` is `split` (more than 25 files), one Correctness reviewer runs
#           out of turns before it reports."
#           -> files_changed > 25
#   fanout  everything else.
# The script only names the class. How to split a large diff (a file stays with its
# tests) is the agent's call.

set -e
set -o pipefail

usage() {
  echo "Usage: review-scope.sh <fixed-point> [--wip] [-- <paths>...]" >&2
  exit 2
}

fp=""
wip=0
paths=()
while [ $# -gt 0 ]; do
  case "$1" in
    --wip) wip=1 ;;
    --) shift; paths=("$@"); break ;;
    -*) echo "review-scope.sh: unknown option: $1" >&2; usage ;;
    *) [ -z "$fp" ] || usage; fp=$1 ;;
  esac
  shift
done
[ -n "$fp" ] || usage

command -v jq >/dev/null || { echo "review-scope.sh: jq is required" >&2; exit 3; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "review-scope.sh: not inside a git repository" >&2; exit 3; }

head_sha=$(git rev-parse --verify --quiet 'HEAD^{commit}') ||
  { echo "review-scope.sh: HEAD does not resolve (no commits yet)" >&2; exit 1; }
fp_sha=$(git rev-parse --verify --quiet "${fp}^{commit}") ||
  { echo "review-scope.sh: fixed point '$fp' does not resolve to a commit" >&2; exit 1; }
merge_base=$(git merge-base "$fp_sha" "$head_sha") ||
  { echo "review-scope.sh: '$fp' and HEAD share no history (no merge-base)" >&2; exit 1; }

# The commands the agent hands on, shell-quoted so a path with a space survives a paste.
scope=""
if [ ${#paths[@]} -gt 0 ]; then
  scope=" --"
  for p in "${paths[@]}"; do scope="$scope $(printf '%q' "$p")"; done
fi
fp_q=$(printf '%q' "$fp")
if [ "$wip" = 1 ]; then
  range=("$merge_base")
  diff_cmd="git diff ${merge_base}${scope}"
else
  range=("${fp_sha}...${head_sha}")
  diff_cmd="git diff ${fp_q}...HEAD${scope}"
fi
log_cmd="git log ${fp_q}..HEAD --oneline${scope}"

gdiff() { git --no-pager diff --no-ext-diff "${range[@]}" "$@" -- "${paths[@]}"; }
untracked() { git ls-files --others --exclude-standard "$@" -- "${paths[@]}"; }
nul_list() { jq -Rs 'split("\u0000") | map(select(. != "")) | unique'; }

tracked_json=$(gdiff --name-only -z | nul_list)
lines=$(gdiff --numstat | awk '{ if ($1 != "-") n += $1; if ($2 != "-") n += $2 } END { print n + 0 }')

untracked_json='[]'
if [ "$wip" = 1 ]; then
  untracked_json=$(untracked --full-name -z | nul_list)
  # An untracked file counts as all-new lines, the way the diff would show it once added.
  while IFS= read -r -d '' f; do
    n=$(git --no-pager diff --no-ext-diff --no-index --numstat -- /dev/null "$f" 2>/dev/null |
      awk '{ if ($1 != "-") n += $1 } END { print n + 0 }' || true)
    lines=$((lines + ${n:-0}))
  done < <(untracked -z)
fi

commits_json=$(git --no-pager log "${fp_sha}..${head_sha}" --format='%H%x09%s' -- "${paths[@]}" |
  jq -Rn '[inputs | split("\t") | {sha: .[0], subject: (.[1:] | join("\t"))}]')

files_json=$(jq -n --argjson t "$tracked_json" --argjson u "$untracked_json" '$t + $u | unique')
files=$(jq -n --argjson f "$files_json" '$f | length')

if [ "$files" -le 3 ] && [ "$lines" -le 150 ]; then
  size="inline"
elif [ "$files" -gt 25 ]; then
  size="split"
else
  size="fanout"
fi

jq -n --arg fixed_point "$fp" --arg fixed_point_sha "$fp_sha" --arg head_sha "$head_sha" \
  --arg merge_base "$merge_base" --arg diff_cmd "$diff_cmd" --arg log_cmd "$log_cmd" \
  --argjson commits "$commits_json" --argjson files "$files_json" \
  --argjson untracked "$untracked_json" --argjson lines "$lines" --arg size "$size" '{
    fixed_point: $fixed_point, fixed_point_sha: $fixed_point_sha, head_sha: $head_sha,
    merge_base: $merge_base, diff_cmd: $diff_cmd, log_cmd: $log_cmd,
    commits: $commits, files: $files, untracked: $untracked,
    files_changed: ($files | length), lines_changed: $lines,
    empty: (($files | length) == 0), size: $size
  }'

if [ "$files" -eq 0 ]; then
  echo "review-scope.sh: empty: true (no changes since '$fp')" >&2
  exit 1
fi
echo "review-scope.sh: $files files, $lines changed lines, size $size" >&2
