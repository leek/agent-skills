#!/bin/bash
# Print the work a sweep cycle must not repeat, as one JSON object on stdout:
#   default_branch   the PR base
#   prs              every open PR, every PR merged in the last --days days
#                    (default 30), and every PR closed unmerged in the last year:
#                    number, state, title, branch, url, files, and sweep (true
#                    when the branch starts sweep/ or sweep-)
#   taken_branches   local and remote branch names starting with sweep
#   findings         .scratch/sweep/findings/*.md files in the main checkout
#
# Usage: known-work.sh [--days N]
# Run from anywhere inside the target repository. Read-only.
set -e

days=30
limit=300   # per request; merged PRs are fetched in 5-day windows to keep each one small
while [ $# -gt 0 ]; do
  case "$1" in
    --days) days="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v gh >/dev/null || { echo "gh is required" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

main=$(git worktree list --porcelain | sed -n '1s/^worktree //p')
default=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)
day() { date -u -v-"$1"d +%Y-%m-%d 2>/dev/null || date -u -d "$1 days ago" +%Y-%m-%d; }
since=$(day "$days")

echo "Fetching open PRs, PRs merged since $since, and PRs closed unmerged since $(day 365)..." >&2
fields=number,state,title,headRefName,url,files
gh pr list --state open --limit "$limit" --json "$fields" > "$tmp/open.json"
end=0
while [ "$end" -lt "$days" ]; do
  start=$((end + 5)); [ "$start" -le "$days" ] || start=$days
  gh pr list --state merged --limit "$limit" --search "merged:$(day "$start")..$(day "$end")" \
    --json "$fields" > "$tmp/closed-$end.json"
  end=$start
done
gh pr list --state closed --limit "$limit" --search "is:unmerged closed:>=$(day 365)" \
  --json "$fields" > "$tmp/closed-unmerged.json"
jq -s add "$tmp"/closed-*.json > "$tmp/closed.json"
for f in "$tmp"/open.json "$tmp"/closed-*.json; do
  [ "$(jq length "$f")" -lt "$limit" ] || echo "warning: a PR window hit $limit results; some PRs are missing" >&2
done

git -C "$main" for-each-ref --format='%(refname:short)' 'refs/heads/sweep*' 'refs/remotes/*/sweep*' \
  | sed 's#^[^/]*/\(sweep\)#\1#' | sort -u | jq -R . | jq -s . > "$tmp/branches.json"

find "$main/.scratch/sweep/findings" -name '*.md' 2>/dev/null | sort | jq -R . | jq -s . > "$tmp/findings.json"

jq -n \
  --arg default "$default" \
  --slurpfile open "$tmp/open.json" \
  --slurpfile closed "$tmp/closed.json" \
  --slurpfile branches "$tmp/branches.json" \
  --slurpfile findings "$tmp/findings.json" '
  {
    default_branch: $default,
    prs: ($open[0] + $closed[0] | unique_by(.number) | sort_by(-.number) | map({
      number, state, title, branch: .headRefName, url,
      files: [.files[].path],
      sweep: (.headRefName | test("^sweep[-/]"))
    })),
    taken_branches: $branches[0],
    findings: $findings[0]
  }'
