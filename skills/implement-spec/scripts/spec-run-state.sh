#!/bin/bash
# Read-only start-of-run facts for implement-spec, so the run does not re-derive them
# from git by hand. Changes nothing.
#
# Usage: spec-run-state.sh <slug> [--default <branch>]
#   Run from the main checkout. <slug> is the spec's directory name under .scratch/.
#
# Output: JSON
#   {"slug", "branch", "mode": "fresh"|"resume", "finished": [branches already landed],
#    "integration_worktree": path or "", "notes": dir, "base_sha": sha or "",
#    "decision_sweep_done": true|false, "build_decisions": path or "",
#    "local_default_scratch_only": true|false, "default"}
#
# - branch: <slug> unless it is finished (origin/<default> contains it and it moved past
#   its recorded base_sha, or its PR merged or closed); then the next unfinished or free
#   <slug>-<n>. "resume" means that branch exists and is unfinished.
# - base_sha (resume only): $notes/base_sha, else the first parent of the branch's first
#   merge on the first-parent line.
# - decision_sweep_done: a committed "Build decisions" ticket in .scratch/<slug>/decisions/
#   and no later commit touching the spec or its tickets.
# - local_default_scratch_only: local <default> is ahead of origin/<default> only by
#   commits touching .scratch/<slug>.

set -e

slug=${1:-}
[ -n "$slug" ] || { echo "Usage: spec-run-state.sh <slug> [--default <branch>]" >&2; exit 2; }
shift
default=""
while [ $# -gt 0 ]; do
  case "$1" in
    --default) [ -n "${2:-}" ] || { echo "--default needs a branch" >&2; exit 2; }; default=$2; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done
if [ -z "$default" ]; then
  default=$(git symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||') || true
  [ -n "$default" ] || default=main
fi

json_str() { printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"; }
bool() { [ "$1" = 1 ] && echo true || echo false; }
has_branch() { git rev-parse --verify -q "refs/heads/$1" >/dev/null; }

common=$(git rev-parse --path-format=absolute --git-common-dir)

# A branch that still sits on its recorded base_sha has no ticket merged yet. It is an
# ancestor of origin/<default> too, but it is a run that stopped early, not one that landed.
not_started() {  # not_started <branch>
  local f="$common/implement-spec/$1/base_sha"
  [ -f "$f" ] && [ "$(tr -d '[:space:]' < "$f")" = "$(git rev-parse "$1")" ]
}

is_finished() {  # is_finished <branch>
  if git merge-base --is-ancestor "$1" "origin/$default" 2>/dev/null && ! not_started "$1"; then return 0; fi
  command -v gh >/dev/null 2>&1 || { echo ">> gh missing: PR state of $1 not checked" >&2; return 1; }
  gh pr list --head "$1" --state all --json state --jq '.[].state' 2>/dev/null | grep -qE '^(MERGED|CLOSED)$'
}

finished=()
branch=$slug
mode=fresh
n=1
while has_branch "$branch"; do
  if is_finished "$branch"; then
    finished+=("$(json_str "$branch")")
    n=$((n + 1)); branch="$slug-$n"
  else
    mode=resume; break
  fi
done

notes="$common/implement-spec/$branch"
wt=""
base=""
if [ "$mode" = resume ]; then
  wt=$(git worktree list --porcelain | awk -v b="refs/heads/$branch" '/^worktree /{ p = substr($0, 10) } $0 == "branch " b { print p; exit }')
  if [ -f "$notes/base_sha" ]; then
    base=$(tr -d '[:space:]' < "$notes/base_sha")
  else
    first=$(git rev-list --first-parent --merges --reverse "origin/$default..$branch" | head -n 1)
    [ -n "$first" ] && base=$(git rev-parse "$first^1")
  fi
fi

sweep=0
bd=""
for f in .scratch/"$slug"/decisions/*.md; do
  [ -f "$f" ] || continue
  head -n 8 "$f" | grep -q 'Build decisions' || continue
  bd=$f
  added=$(git log -1 --diff-filter=A --format=%H -- "$f")
  [ -n "$added" ] || break
  later=$(git log --format=%h "$added..HEAD" -- ".scratch/$slug/spec.md" ".scratch/$slug/tickets")
  [ -n "$later" ] || sweep=1
  break
done

scratch_only=0
if git rev-parse --verify -q "refs/heads/$default" >/dev/null && git rev-parse --verify -q "refs/remotes/origin/$default" >/dev/null; then
  ahead=$(git rev-list --count "origin/$default..$default")
  other=$(git log --format=%h "origin/$default..$default" -- . ":!.scratch/$slug")
  [ "$ahead" != 0 ] && [ -z "$other" ] && scratch_only=1
fi

(IFS=,; echo "{\"slug\":$(json_str "$slug"),\"branch\":$(json_str "$branch"),\"mode\":\"$mode\",\"finished\":[${finished[*]}],\"integration_worktree\":$(json_str "$wt"),\"notes\":$(json_str "$notes"),\"base_sha\":$(json_str "$base"),\"decision_sweep_done\":$(bool $sweep),\"build_decisions\":$(json_str "$bd"),\"local_default_scratch_only\":$(bool $scratch_only),\"default\":$(json_str "$default")}")
