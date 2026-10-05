#!/bin/bash
# Upload screenshots for a PR body to the repo's orphan `pr-assets` branch, without
# touching the working tree, index, or current branch.
# Usage: upload-screenshots.sh <pr-branch> <image>...   (run inside the repo)
# Stdout: one Markdown image line per file, pinned to the pr-assets commit.
set -e

branch="${1:?usage: upload-screenshots.sh <pr-branch> <image>...}"
shift
[ "$#" -gt 0 ] || { echo "no images given" >&2; exit 1; }
for f in "$@"; do [ -f "$f" ] || { echo "not a file: $f" >&2; exit 1; }; done

repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
dir="$(printf '%s' "$branch" | tr -c 'A-Za-z0-9._-' '-')"
index="$(mktemp)"
trap 'rm -f "$index"' EXIT

for attempt in 1 2 3; do
  rm -f "$index"
  if git fetch -q origin pr-assets 2>/dev/null; then
    parent="$(git rev-parse FETCH_HEAD)"
    GIT_INDEX_FILE="$index" git read-tree "$parent"
  else
    parent=""
    GIT_INDEX_FILE="$index" git read-tree --empty
  fi

  for f in "$@"; do
    blob="$(git hash-object -w -- "$f")"
    GIT_INDEX_FILE="$index" git update-index --add --cacheinfo "100644,$blob,$dir/$(basename "$f")"
  done
  tree="$(GIT_INDEX_FILE="$index" git write-tree)"
  commit="$(git commit-tree "$tree" ${parent:+-p "$parent"} -m "screenshots: $branch")"

  if git push -q origin "$commit:refs/heads/pr-assets" 2>/dev/null; then
    echo "pushed $# screenshot(s) to pr-assets/$dir" >&2
    for f in "$@"; do
      name="$(basename "$f")"
      echo "![${name%.*}](https://github.com/$repo/blob/$commit/$dir/$name?raw=true)"
    done
    exit 0
  fi
  echo "pr-assets moved; retrying ($attempt)" >&2
done
echo "could not push pr-assets after 3 attempts" >&2
exit 1
