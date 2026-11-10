#!/bin/bash
# Plan a release: preflight facts, the commits since the last tag, the next version and the
# rule that chose it, and the version files to bump. Read-only except for `git fetch`.
#
# Usage: release-plan.sh [major|minor|patch]      (run inside the repository to release)
#
# Stdout (one JSON object):
#   {"last_tag": "v1.2.3" | null,          null: no tag exists, this is a first release
#    "tag_style": "v" | "",                prefix of the newest tag; "v" on a first release
#    "branch": "main",                     "" on a detached HEAD
#    "behind": 0,                          commits the upstream has that HEAD lacks; 0 with no upstream
#    "authenticated": true,                false when `gh auth status` fails or gh is missing
#    "commits": [{"sha": "abc1234", "subject": "fix: ..."}],   last_tag..HEAD, newest first
#    "bump": "major" | "minor" | "patch" | null,
#    "rule": "<the sentence that chose the bump>",
#    "next": "v1.2.4" | null,
#    "tag_free": true | null,              false when the tag `next` already exists locally
#    "version_files": [{"path": ".claude-plugin/plugin.json", "matches": 1}],
#    "dirty": ["path", ...]}               paths from `git status --porcelain`
#
# bump, next and tag_free are null when there are no commits since last_tag (nothing to
# release). On a first release bump is null and next is the version file's version, else v0.1.0.
#
# Bump rule: the argument wins. Otherwise a breaking commit (`type!:` or `type(scope)!:` in a
# subject, BREAKING CHANGE in a subject, or a `BREAKING CHANGE:` line in a body) is major, minor
# while the last tag is 0.x; any `feat` subject is minor; anything else is patch.
#
# version_files: each tracked file among .claude-plugin/marketplace.json,
# .claude-plugin/plugin.json, package.json, pyproject.toml, Cargo.toml and VERSION that contains
# the last tag's version (the tag without its "v"), with how many times. A count other than 1
# is reported as it is; bump-version.sh refuses such a file.
#
# Exit 0 with the JSON; 1 when the plan cannot be made (not a repository, fetch failed, a last
# tag that is not MAJOR.MINOR.PATCH, tags that HEAD cannot reach); 2 on a usage error.
set -e
set -o pipefail

usage() { echo "usage: release-plan.sh [major|minor|patch]" >&2; }

explicit="${1:-}"
case "$explicit" in
  ""|major|minor|patch) ;;
  -h|--help) sed -n '2,31p' "$0" >&2; exit 0 ;;
  *) usage; exit 2 ;;
esac
if [ $# -gt 1 ]; then usage; exit 2; fi

command -v jq >/dev/null || { echo "release-plan: jq is required" >&2; exit 1; }
command -v perl >/dev/null || { echo "release-plan: perl is required" >&2; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "release-plan: not inside a git repository" >&2; exit 1; }
cd "$(git rev-parse --show-toplevel)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

git fetch --quiet >&2 || { echo "release-plan: git fetch failed, so 'behind' cannot be trusted" >&2; exit 1; }

authenticated=false
if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then authenticated=true; fi

branch="$(git symbolic-ref --short -q HEAD || true)"
behind="$(git rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)"

# How many times the version stands alone in the file: not inside a longer number, so 1.2.3
# does not match 11.2.3 or 1.2.30. Keep in step with bump-version.sh.
count_matches() { # $1 version, $2 file
  OLD="$1" perl -0777 -ne '$n += () = /(?<![0-9])(?<![0-9]\.)\Q$ENV{OLD}\E(?!\.?[0-9])/g; END { print $n + 0 }' "$2"
}

VERSION_FILES='.claude-plugin/marketplace.json
.claude-plugin/plugin.json
package.json
pyproject.toml
Cargo.toml
VERSION'

tracked() { [ -f "$1" ] && git ls-files --error-unmatch -- "$1" >/dev/null 2>&1; }

file_version() { # $1 file -> the version it declares, or nothing
  case "$1" in
    *.json) jq -r '(.version // .metadata.version // empty) | strings' "$1" 2>/dev/null || true ;;
    *.toml) sed -n 's/^version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$1" | sed -n 1p ;;
    *) tr -d '[:space:]' < "$1" ;;
  esac
}

newest_tag="$(git tag --sort=-v:refname | sed -n 1p)"
last_tag="$(git describe --tags --abbrev=0 2>/dev/null || true)"
have_head=false
if git rev-parse -q --verify HEAD >/dev/null; then have_head=true; fi

bump=""
next=""
rule=""
old_version=""

if [ -z "$newest_tag" ]; then
  # First release: the version file's version, else v0.1.0.
  tag_style="v"
  range="HEAD"
  source_file=""
  while read -r f; do
    tracked "$f" || continue
    v="$(file_version "$f")"
    if [ -n "$v" ]; then old_version="${v#v}"; source_file="$f"; break; fi
  done <<EOF
$VERSION_FILES
EOF
  if [ -n "$old_version" ]; then
    next="v$old_version"
    rule="First release: no tag exists, so the version is the one in $source_file."
  else
    next="v0.1.0"
    rule="First release: no tag exists and no version file declares a version, so v0.1.0."
  fi
  if [ -n "$explicit" ]; then rule="$rule The argument '$explicit' is not applied."; fi
else
  if [ -z "$last_tag" ]; then
    echo "release-plan: tags exist but HEAD reaches none of them" >&2
    exit 1
  fi
  case "$newest_tag" in v*) tag_style="v" ;; *) tag_style="" ;; esac
  range="$last_tag..HEAD"
  old_version="${last_tag#v}"
  if [[ ! "$old_version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "release-plan: last tag '$last_tag' is not MAJOR.MINOR.PATCH" >&2
    exit 1
  fi
  major=$((10#${BASH_REMATCH[1]}))
  minor=$((10#${BASH_REMATCH[2]}))
  patch=$((10#${BASH_REMATCH[3]}))
fi

if $have_head; then
  git log --format='%h%x09%s' "$range" > "$tmp/commits.tsv"
  git log --format='%B' "$range" > "$tmp/bodies"
else
  : > "$tmp/commits.tsv"
  : > "$tmp/bodies"
fi
cut -f2- "$tmp/commits.tsv" > "$tmp/subjects"

if [ -n "$last_tag" ]; then
  if [ ! -s "$tmp/commits.tsv" ]; then
    rule="No commits since $last_tag: nothing to release."
  else
    breaking="$(grep -E -m1 '^[A-Za-z]+(\([^)]*\))?!:|BREAKING[ -]CHANGE' "$tmp/subjects" || true)"
    if [ -z "$breaking" ]; then
      breaking="$(grep -E -m1 '^BREAKING[ -]CHANGE:' "$tmp/bodies" || true)"
    fi
    feat="$(grep -E -m1 '^feat(\([^)]*\))?!?:' "$tmp/subjects" || true)"
    if [ -n "$explicit" ]; then
      bump="$explicit"
      rule="The argument '$explicit' wins over the commit subjects."
    elif [ -n "$breaking" ] && [ "$major" -eq 0 ]; then
      bump="minor"
      rule="A breaking change ('$breaking') is major, but minor while still 0.x."
    elif [ -n "$breaking" ]; then
      bump="major"
      rule="A breaking change ('$breaking') is major."
    elif [ -n "$feat" ]; then
      bump="minor"
      rule="A feat commit ('$feat') and no breaking change is minor."
    else
      bump="patch"
      rule="No breaking change and no feat commit is patch."
    fi
    case "$bump" in
      major) next="$tag_style$((major + 1)).0.0" ;;
      minor) next="$tag_style$major.$((minor + 1)).0" ;;
      patch) next="$tag_style$major.$minor.$((patch + 1))" ;;
    esac
  fi
fi

tag_free=null
if [ -n "$next" ]; then
  if [ -z "$(git tag -l "$next")" ]; then tag_free=true; else tag_free=false; fi
fi

: > "$tmp/version-files.tsv"
if [ -n "$old_version" ]; then
  while read -r f; do
    tracked "$f" || continue
    n="$(count_matches "$old_version" "$f")"
    if [ "$n" -gt 0 ]; then printf '%s\t%s\n' "$n" "$f" >> "$tmp/version-files.tsv"; fi
  done <<EOF
$VERSION_FILES
EOF
fi

# -z keeps odd paths unquoted; a rename or copy entry is followed by its source path, dropped here.
git status --porcelain -z | tr '\0' '\n' \
  | awk 'skip { skip = 0; next } { s = substr($0, 1, 2); if (s ~ /[RC]/) skip = 1; print substr($0, 4) }' \
  > "$tmp/dirty"

jq -n \
  --arg last_tag "$last_tag" --arg tag_style "$tag_style" --arg branch "$branch" \
  --argjson behind "$behind" --argjson authenticated "$authenticated" \
  --arg bump "$bump" --arg rule "$rule" --arg next "$next" --argjson tag_free "$tag_free" \
  --rawfile commits "$tmp/commits.tsv" --rawfile files "$tmp/version-files.tsv" --rawfile dirty "$tmp/dirty" \
  'def lines: split("\n") | map(select(. != ""));
   def nullable: if . == "" then null else . end;
   {last_tag: ($last_tag | nullable),
    tag_style: $tag_style,
    branch: $branch,
    behind: $behind,
    authenticated: $authenticated,
    commits: ($commits | lines | map(split("\t") | {sha: .[0], subject: (.[1:] | join("\t"))})),
    bump: ($bump | nullable),
    rule: $rule,
    next: ($next | nullable),
    tag_free: $tag_free,
    version_files: ($files | lines | map(split("\t") | {path: (.[1:] | join("\t")), matches: (.[0] | tonumber)})),
    dirty: ($dirty | lines)}'
