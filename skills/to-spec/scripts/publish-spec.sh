#!/bin/bash
# Commit .scratch/<slug> where to-spec and to-tickets publish it, without moving the
# checkout or carrying another session's commits.
#
# Usage: publish-spec.sh <slug> -m <message> [--own <sha>]... [--default <branch>]
#   --own: a commit this session made on the current branch (repeat per sha). A fresh
#          session passes none.
#
# Where it commits:
#   - "ignored": `git check-ignore -q .scratch` holds; nothing is committed.
#   - "docs-branch": the branch docs/<slug>-spec exists, or origin/<default>..HEAD holds a
#     commit not passed as --own. The commit goes on docs/<slug>-spec (created from
#     origin/<default> when missing) through the temporary worktree
#     .claude/worktrees/docs-<slug>-spec, removed again without --force; the checkout
#     stays where it is.
#   - "current": otherwise, on the current branch, staging only .scratch/<slug>.
#
# Output: JSON {"where","branch","sha"} (sha "" when nothing changed or ignored)

set -e

slug=${1:-}
[ -n "$slug" ] || { echo "Usage: publish-spec.sh <slug> -m <message> [--own <sha>]... [--default <branch>]" >&2; exit 2; }
shift
msg=""; own=(); default=""
while [ $# -gt 0 ]; do
  case "$1" in
    -m) msg=${2:-}; shift ;;
    --own) [ -n "${2:-}" ] || { echo "--own needs a sha" >&2; exit 2; }; own+=("$(git rev-parse "$2")"); shift ;;
    --default) default=${2:-}; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done
[ -n "$msg" ] || { echo "-m <message> is required" >&2; exit 2; }

dir=".scratch/$slug"
[ -d "$dir" ] || { echo "No $dir in $(pwd)" >&2; exit 2; }

json_str() { printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"; }
out() { echo "{\"where\":\"$1\",\"branch\":$(json_str "$2"),\"sha\":$(json_str "$3")}"; }

if git check-ignore -q .scratch; then
  echo ">> .scratch is ignored here; nothing committed" >&2
  out ignored "" ""; exit 0
fi

if [ -z "$default" ]; then
  default=$(git symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||') || true
  [ -n "$default" ] || default=main
fi
git fetch -q origin
git rev-parse --verify -q "refs/remotes/origin/$default" >/dev/null \
  || { echo "origin/$default does not exist; pass --default <branch>" >&2; exit 2; }

docs="docs/$slug-spec"
foreign=""
# Assigned first: a failing rev-list inside `for … in $(…)` would not stop the script.
revs=$(git rev-list "origin/$default..HEAD")
for s in $revs; do
  mine=0
  for o in ${own[@]+"${own[@]}"}; do [ "$s" = "$o" ] && mine=1; done
  [ "$mine" = 1 ] || { foreign=$s; break; }
done

if [ -z "$foreign" ] && ! git rev-parse --verify -q "refs/heads/$docs" >/dev/null; then
  git add -- "$dir"
  if git diff --cached --quiet -- "$dir"; then
    echo ">> $dir unchanged; nothing committed" >&2
    out current "$(git branch --show-current)" ""; exit 0
  fi
  git commit -q --only -m "$msg" -- "$dir"
  out current "$(git branch --show-current)" "$(git rev-parse HEAD)"; exit 0
fi

[ -z "$foreign" ] || echo ">> HEAD carries $foreign, not this session's; committing on $docs" >&2
main=$(git worktree list --porcelain | awk '/^worktree /{ print substr($0, 10); exit }')
wt="$main/.claude/worktrees/docs-$slug-spec"
src=$(pwd -P)/$dir
# A step that fails (a pre-commit hook, a full disk) must not leave the temporary worktree
# behind: the next run would stop at "already exists". The worktree is this run's own, so
# its uncommitted copy is discarded and it is removed without --force. The branch stays.
added=0
cleanup() {
  [ "$added" = 1 ] && [ -d "$wt" ] || return 0
  git -C "$wt" reset -q --hard HEAD 2>/dev/null || true
  git -C "$wt" clean -fdq -- .scratch 2>/dev/null || true
  git worktree remove "$wt" >&2 || echo ">> could not remove $wt; remove it before the next run" >&2
}
trap cleanup EXIT
[ ! -e "$wt" ] || { echo "$wt already exists; remove that worktree first (git worktree remove)" >&2; exit 1; }
added=1
if git rev-parse --verify -q "refs/heads/$docs" >/dev/null; then
  git worktree add -q "$wt" "$docs" >&2
else
  git worktree add -q -b "$docs" "$wt" "origin/$default" >&2
fi
rm -rf "${wt:?}/$dir"
mkdir -p "$wt/.scratch"
cp -R "$src" "$wt/.scratch/"
git -C "$wt" add -- "$dir"
sha=""
if git -C "$wt" diff --cached --quiet -- "$dir"; then
  echo ">> $dir unchanged on $docs; nothing committed" >&2
else
  git -C "$wt" commit -q -m "$msg" -- "$dir"
  sha=$(git -C "$wt" rev-parse HEAD)
fi
git worktree remove "$wt" >&2 || echo ">> git worktree remove refused $wt; it stays" >&2
added=0
out docs-branch "$docs" "$sha"
