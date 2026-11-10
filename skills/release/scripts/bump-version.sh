#!/bin/bash
# Replace one version string with another in every named file, or change nothing at all.
#
# Usage: bump-version.sh <old> <new> <file>...
#   <old>, <new>: bare versions as the files hold them (0.89.10, not v0.89.10).
#
# Each file must hold <old> exactly once, standing alone (1.2.3 does not match 11.2.3 or
# 1.2.30). When every file does, each is rewritten and stdout is:
#   {"changed": ["path", ...]}
# When any file is missing or holds <old> zero or several times, no file is written, stdout is:
#   {"changed": [], "refused": [{"path": "...", "matches": 0}]}
# and the exit code is 1. It never commits: the caller does.
#
# Exit 0 changed; 1 refused; 2 usage error.
set -e
set -o pipefail

if [ $# -lt 3 ] || [ -z "$1" ] || [ -z "$2" ] || [ "$1" = "$2" ]; then
  echo "usage: bump-version.sh <old> <new> <file>...   (old and new must differ)" >&2
  exit 2
fi
old="$1"
new="$2"
shift 2

command -v jq >/dev/null || { echo "bump-version: jq is required" >&2; exit 1; }
command -v perl >/dev/null || { echo "bump-version: perl is required" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
: > "$tmp/refused.tsv"

# The match stands alone, not inside a longer number. Keep in step with release-plan.sh.
i=0
for f in "$@"; do
  i=$((i + 1))
  if [ ! -f "$f" ]; then
    n=0
    echo "bump-version: $f: no such file" >&2
  else
    n="$(OLD="$old" perl -0777 -ne '$n += () = /(?<![0-9])(?<![0-9]\.)\Q$ENV{OLD}\E(?!\.?[0-9])/g; END { print $n + 0 }' "$f")"
  fi
  if [ "$n" -ne 1 ]; then
    echo "bump-version: $f: '$old' matches $n times, want exactly 1" >&2
    printf '%s\t%s\n' "$n" "$f" >> "$tmp/refused.tsv"
    continue
  fi
  OLD="$old" NEW="$new" perl -0777 -pe 's/(?<![0-9])(?<![0-9]\.)\Q$ENV{OLD}\E(?!\.?[0-9])/$ENV{NEW}/' "$f" > "$tmp/$i"
done

if [ -s "$tmp/refused.tsv" ]; then
  echo "bump-version: nothing written" >&2
  jq -n --rawfile refused "$tmp/refused.tsv" \
    '{changed: [], refused: ($refused | split("\n") | map(select(. != "") | split("\t") | {path: (.[1:] | join("\t")), matches: (.[0] | tonumber)}))}'
  exit 1
fi

# Every file passed: write them. `cat >` keeps each file's mode and any symlink.
i=0
for f in "$@"; do
  i=$((i + 1))
  cat "$tmp/$i" > "$f"
done
echo "bump-version: $old -> $new in $# file(s)" >&2
jq -n '{changed: $ARGS.positional}' --args "$@"
