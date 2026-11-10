#!/bin/bash
# PR delivery's branch setup (implement's references/spec-run.md, "PR delivery: before
# step 1 claims anything", steps 2-6), in that order. Mechanics only: the skill decides the
# flags (worktree or not, whether the user agreed to the reset, Stacked PRs).
#
# Usage:
#   start-branch.sh <slug> --branch <name> [--default <branch>] [--worktree]
#                   [--reset-default] [--stack --title <text>]
#   start-branch.sh <slug> --branch <name> [--default <branch>] --stack --title <text>
#                   --existing [--base-sha <sha>]
#   <slug> is the work's directory name under .scratch/ (it also goes in the stack's commit
#   subject, PR title and body); <name> is the branch to create. Run inside the repository.
#   Needs jq, and gh with --stack.
#
# What it does:
#   2. git fetch origin, then <name> from origin/<default>: with --worktree in
#      <main checkout>/.claude/worktrees/<name>, otherwise `git switch -c` in this checkout,
#      which must be clean (any `git status --porcelain` line refuses: pass --worktree).
#   3. Carries .scratch/<slug> from the newest commit that added or changed it among local
#      <default>, docs/<slug>-spec and the main checkout's branch, and commits it as
#      "docs(scratch): <slug>". Nothing is carried when the new branch already holds that
#      content or a newer copy, or the repo ignores .scratch.
#      An untracked copy in the main checkout is deleted when `diff -r` shows it equals the
#      new branch's copy; otherwise it stays ("differs").
#      --reset-default (the user said yes): when local <default> is ahead of origin/<default>
#      only by commits touching .scratch/<slug>, and the new branch holds the same
#      .scratch/<slug>, moves <default> back to origin/<default> (`git reset --keep` in the
#      checkout that has it, else `git branch -f`). Otherwise it stays, with the reason on
#      stderr.
#   4. --stack: an empty commit "chore(<slug>): open integration branch" when the branch has
#      no commit of its own.
#   5. base_sha = the new branch's tip.
#   6. --stack: git push origin <base_sha>:refs/heads/<name>, then a draft PR
#      "[<slug>] <title>" into <default>.
#   --existing runs only steps 4-6 on a branch that already exists (a commit was added
#   between steps 3 and 5, or a resumed run has no integration PR). With --base-sha, step 4
#   is skipped and that sha is pushed; a remote <name> that already exists is not pushed again.
#
# Output: one JSON line
#   {"branch", "worktree": path or "", "base_sha", "default", "scratch_source": ref or "",
#    "scratch_commit": sha or "", "untracked_copy": "deleted"|"differs"|"none",
#    "default_ahead_scratch_only": true|false, "default_reset": true|false,
#    "integration_pr": number or null, "todo": [what stays with the agent]}
#   default_ahead_scratch_only is the state before any reset (spec-run-state.sh's
#   local_default_scratch_only: the rule lives in that script, called with --default-only).
#
# Exit: 0 done; 1 refused or failed (dirty tree, the branch or worktree path exists, a step
# failed); 2 usage error or origin/<default> missing. After a failure that follows the
# branch's creation, stderr lists what exists. Nothing is removed, and nothing is forced.

set -e

usage() {
  echo "Usage: start-branch.sh <slug> --branch <name> [--default <branch>] [--worktree] [--reset-default] [--stack --title <text>] [--existing [--base-sha <sha>]]" >&2
  exit 2
}

slug=${1:-}
case "$slug" in
  "" | -* | */* | *..*) usage ;;
esac
shift
name=""; default=""; worktree=0; reset=0; stack=0; title=""; existing=0; given_base=""
while [ $# -gt 0 ]; do
  case "$1" in
    --branch) [ -n "${2:-}" ] || usage; name=$2; shift ;;
    --default) [ -n "${2:-}" ] || usage; default=$2; shift ;;
    --title) [ -n "${2:-}" ] || usage; title=$2; shift ;;
    --base-sha) [ -n "${2:-}" ] || usage; given_base=$2; shift ;;
    --worktree) worktree=1 ;;
    --reset-default) reset=1 ;;
    --stack) stack=1 ;;
    --existing) existing=1 ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
  shift
done
[ -n "$name" ] || { echo "--branch <name> is required" >&2; usage; }
if [ "$stack" = 1 ]; then
  [ -n "$title" ] || { echo "--stack needs --title <text>" >&2; usage; }
else
  [ -z "$title" ] || { echo "--title only goes with --stack" >&2; usage; }
  [ "$existing" = 0 ] || { echo "--existing only goes with --stack" >&2; usage; }
fi
if [ "$existing" = 1 ]; then
  [ "$worktree" = 0 ] && [ "$reset" = 0 ] || { echo "--existing takes neither --worktree nor --reset-default" >&2; usage; }
else
  [ -z "$given_base" ] || { echo "--base-sha only goes with --existing" >&2; usage; }
fi

command -v jq >/dev/null 2>&1 || { echo "start-branch.sh needs jq on PATH" >&2; exit 1; }
if [ "$stack" = 1 ]; then
  command -v gh >/dev/null 2>&1 || { echo "--stack needs gh on PATH" >&2; exit 1; }
fi
git rev-parse --git-dir >/dev/null 2>&1 || { echo "Not a git repository: $(pwd)" >&2; exit 2; }
git check-ref-format --branch "$name" >/dev/null 2>&1 || { echo "Not a branch name: $name" >&2; exit 2; }
state="$(cd "$(dirname "$0")" && pwd)/../../implement-spec/scripts/spec-run-state.sh"
[ -f "$state" ] || { echo "Missing $state (implement-spec ships with this skill collection)" >&2; exit 1; }

dir=".scratch/$slug"
listing=$(git worktree list --porcelain)
main=$(printf '%s\n' "$listing" | awk '/^worktree / && !n++ { print substr($0, 10) }')
holder_of() {  # holder_of <branch>: the checkout that has it checked out, or nothing
  git worktree list --porcelain | awk -v b="refs/heads/$1" '/^worktree /{ p = substr($0, 10) } $0 == "branch " b && !n++ { print p }'
}
has_branch() { git rev-parse --verify -q "refs/heads/$1" >/dev/null; }

# What exists, for the failure report and the JSON.
created=0; co=""; wt=""; base=""; pushed=0; emptied=0
src=""; scratch_commit=""; untracked=none; default_reset=false; pr=null; todo='[]'
add_todo() { todo=$(jq -cn --argjson t "$todo" --arg s "$1" '$t + [$s]'); }

on_exit() {
  code=$?
  [ "$code" != 0 ] || return 0
  if [ "$created" = 1 ]; then
    {
      echo "start-branch.sh stopped after it created or changed the following. Nothing was removed:"
      if [ "$existing" = 1 ]; then
        [ "$emptied" != 1 ] || echo "  an empty commit on $name: chore($slug): open integration branch"
      elif [ -n "$wt" ]; then
        echo "  branch $name, in the worktree $wt"
      else
        echo "  branch $name, checked out in $co"
      fi
      [ -z "$scratch_commit" ] || echo "  commit $scratch_commit on it: docs(scratch): $slug, from $src"
      [ "$untracked" != deleted ] || echo "  the untracked $dir in $main was deleted (the branch holds the same files)"
      [ "$default_reset" != true ] || echo "  local $default was moved back to origin/$default"
      [ -z "$base" ] || echo "  base_sha $base"
      [ "$pushed" != 1 ] || echo "  origin/$name, pushed at $base"
      if [ "$existing" = 0 ] && [ -z "$base" ]; then
        echo "Go on by hand from the step that failed, or remove it: git worktree remove <path> (when it is a worktree), then git branch -d $name."
      elif [ "$stack" = 1 ]; then
        echo "Go on with: start-branch.sh $slug --branch $name --stack --title <text> --existing --base-sha ${base:-<sha>}"
      fi
    } >&2
  fi
  [ "$code" = 2 ] || exit 1
}
trap on_exit EXIT

open_integration_pr() {  # step 6
  if [ "$existing" = 1 ] && git ls-remote --exit-code origin "refs/heads/$name" >/dev/null 2>&1; then
    echo ">> origin/$name already exists; not pushed again" >&2
  else
    git push -q origin "$base:refs/heads/$name" >&2
    pushed=1; created=1
  fi
  url=$(gh pr create --draft --base "$default" --head "$name" --title "[$slug] $title" \
    --body "Integration: lands the $slug stack, then merges into $default.")
  pr=$(printf '%s\n' "$url" | sed -n 's|.*/pull/\([0-9][0-9]*\).*|\1|p' | tail -n 1)
  [ -n "$pr" ] || { pr=null; echo "gh pr create printed no pull request URL: $url" >&2; return 1; }
}

emit() {
  local w=""
  [ "$co" = "$main" ] || w=$co
  jq -cn --arg branch "$name" --arg worktree "$w" --arg base "$base" --arg default "$default" \
    --arg src "$src" --arg commit "$scratch_commit" --arg untracked "$untracked" \
    --argjson only "$scratch_only" --argjson reset "$default_reset" --argjson pr "$pr" --argjson todo "$todo" \
    '{branch: $branch, worktree: $worktree, base_sha: $base, default: $default, scratch_source: $src,
      scratch_commit: $commit, untracked_copy: $untracked, default_ahead_scratch_only: $only,
      default_reset: $reset, integration_pr: $pr, todo: $todo}'
}

# Step 2, first half: fresh origin, then the default branch and the scratch-only rule.
[ "$existing" = 1 ] || git fetch -q origin
if [ -n "$default" ]; then
  facts=$(cd "$main" && bash "$state" "$slug" --default-only --default "$default")
else
  facts=$(cd "$main" && bash "$state" "$slug" --default-only)
fi
default=$(printf '%s' "$facts" | jq -r .default)
scratch_only=$(printf '%s' "$facts" | jq -r .local_default_scratch_only)
git rev-parse --verify -q "refs/remotes/origin/$default" >/dev/null \
  || { echo "origin/$default does not exist; pass --default <branch>" >&2; exit 2; }

if [ "$existing" = 1 ]; then
  has_branch "$name" || { echo "--existing: no local branch $name" >&2; exit 1; }
  co=$(holder_of "$name")
  if [ -n "$given_base" ]; then
    base=$(git rev-parse --verify -q "$given_base^{commit}") || { echo "--base-sha $given_base is not a commit" >&2; exit 2; }
    git merge-base --is-ancestor "$base" "refs/heads/$name" || { echo "--base-sha $base is not on $name" >&2; exit 1; }
  else
    if [ "$(git rev-list --count "origin/$default..refs/heads/$name")" = 0 ]; then
      [ -n "$co" ] || { echo "$name has no commit of its own and no checkout holds it; check it out first" >&2; exit 1; }
      git -C "$co" commit -q --allow-empty -m "chore($slug): open integration branch" >&2
      emptied=1; created=1
    fi
    base=$(git rev-parse "refs/heads/$name")
  fi
  open_integration_pr
  [ -n "$co" ] || co=$main
  emit
  exit 0
fi

has_branch "$name" && { echo "Branch $name already exists; nothing was created (a resumed run uses the existing branch)" >&2; exit 1; }
# Read before any switch: afterwards the main checkout may be on the new branch.
if cur=$(git -C "$main" symbolic-ref --short -q HEAD); then cur_ref="refs/heads/$cur"; else cur=$(git -C "$main" rev-parse HEAD); cur_ref=$cur; fi

if [ "$worktree" = 1 ]; then
  wt="$main/.claude/worktrees/$name"
  [ ! -e "$wt" ] || { echo "$wt already exists; nothing was created" >&2; exit 1; }
  git -C "$main" worktree add -q -b "$name" "$wt" "origin/$default" >&2
  co=$wt
else
  co=$(git rev-parse --show-toplevel)
  [ -z "$(git -C "$co" status --porcelain)" ] \
    || { echo "The tree in $co is dirty; nothing was created. A dirty tree means a worktree: pass --worktree." >&2; exit 1; }
  git -C "$co" switch -q -c "$name" "origin/$default" >&2
fi
created=1

# Step 3: carry .scratch/<slug>.
commit_time() { git -C "$main" log -1 --format=%ct "$1"; }
newer() {  # newer <sha> <than sha>: a descendant wins, then the later commit date
  [ -n "$2" ] || return 0
  [ "$1" != "$2" ] || return 1
  if git -C "$main" merge-base --is-ancestor "$2" "$1"; then return 0; fi
  if git -C "$main" merge-base --is-ancestor "$1" "$2"; then return 1; fi
  [ "$(commit_time "$1")" -gt "$(commit_time "$2")" ]
}
best=""; src_ref=""
consider() {  # consider <label> <ref>
  local c
  git -C "$main" rev-parse --verify -q "$2^{commit}" >/dev/null || return 0
  git -C "$main" rev-parse --verify -q "$2:$dir" >/dev/null || return 0
  c=$(git -C "$main" log -1 --format=%H --diff-filter=AM "$2" -- "$dir")
  [ -n "$c" ] || return 0
  newer "$c" "$best" || return 0
  best=$c; src=$1; src_ref=$2
}
if git -C "$co" check-ignore -q .scratch; then
  echo ">> .scratch is ignored here; nothing carried" >&2
else
  # The new branch's own copy competes too: a newer one there is never replaced.
  best=$(git -C "$main" log -1 --format=%H --diff-filter=AM "refs/heads/$name" -- "$dir")
  consider "$default" "refs/heads/$default"
  consider "docs/$slug-spec" "refs/heads/docs/$slug-spec"
  consider "$cur" "$cur_ref"
  if [ -n "$src" ]; then
    want=$(git -C "$main" rev-parse "$src_ref:$dir")
    have=$(git -C "$co" rev-parse --verify -q "HEAD:$dir" || true)
    if [ "$want" = "$have" ]; then
      echo ">> $name already holds $dir as $src has it; nothing carried" >&2
      src=""
    else
      git -C "$co" checkout "$src_ref" -- "$dir" >&2
      if git -C "$co" diff --cached --quiet -- "$dir"; then
        echo ">> $dir from $src changes nothing on $name; nothing carried" >&2
        src=""
      else
        git -C "$co" commit -q -m "docs(scratch): $slug" -- "$dir" >&2
        scratch_commit=$(git -C "$co" rev-parse HEAD)
      fi
    fi
  fi
fi

# Step 3: the untracked copy the main checkout keeps.
if [ "$co" != "$main" ]; then
  loose=$(git -C "$main" status --porcelain --untracked-files=all -- "$dir" | grep '^??' || true)
  if [ -n "$loose" ]; then
    if [ -z "$(git -C "$main" ls-files -- "$dir")" ] && [ -d "$co/$dir" ] && diff -r "$main/$dir" "$co/$dir" >/dev/null 2>&1; then
      rm -rf "${main:?}/$dir"
      untracked=deleted
    else
      untracked=differs
      echo ">> $main/$dir is untracked and differs from $name's copy; left as it is" >&2
    fi
  fi
fi

# Step 3: local <default> ahead of origin/<default>.
if [ "$reset" = 1 ]; then
  d_tree=$(git rev-parse --verify -q "refs/heads/$default:$dir" || true)
  b_tree=$(git -C "$co" rev-parse --verify -q "HEAD:$dir" || true)
  if [ "$scratch_only" != true ]; then
    echo ">> $default not moved: it is not ahead of origin/$default only by commits touching $dir" >&2
  elif [ -z "$d_tree" ] || [ "$d_tree" != "$b_tree" ]; then
    echo ">> $default not moved: $name does not hold the same $dir as $default" >&2
  else
    holder=$(holder_of "$default")
    if [ -n "$holder" ]; then
      if git -C "$holder" reset -q --keep "origin/$default" >&2; then default_reset=true; else echo ">> $default not moved: git reset --keep refused in $holder" >&2; fi
    else
      if git branch -q -f "$default" "origin/$default" >&2; then default_reset=true; else echo ">> $default not moved: git branch -f refused" >&2; fi
    fi
  fi
fi
if [ "$default_reset" = false ] && has_branch "$default" \
  && [ -n "$(git -C "$main" log --format=%h "origin/$default..refs/heads/$default" -- "$dir")" ]; then
  add_todo "Say in the report: local $default still holds $dir commits that origin/$default lacks, so pulling $default after the merge conflicts on $dir."
fi

# Steps 4 and 5.
if [ "$stack" = 1 ] && [ "$(git -C "$co" rev-list --count "origin/$default..HEAD")" = 0 ]; then
  git -C "$co" commit -q --allow-empty -m "chore($slug): open integration branch" >&2
fi
base=$(git -C "$co" rev-parse HEAD)

# Step 6.
[ "$stack" = 0 ] || open_integration_pr

if [ -n "$wt" ]; then
  add_todo "Make the worktree $wt runnable (install dependencies, copy local env config) the way the project's docs or the stack reference say."
  add_todo "Work in $wt: move the session into it, or run every command with absolute paths into it."
fi
emit
