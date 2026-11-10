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
# Writing is all or nothing too: every new content is first written to a temporary file beside
# its target (same mode; a symlink is followed to the file it names), and only when all of
# them are written is each renamed over its target. A target that cannot be written (read-only
# file or directory, full disk) removes the temporary files, changes nothing, and prints
#   {"changed": [], "refused": [{"path": "...", "matches": 1, "error": "not writable"}]}
# with exit 1. A rename that fails after that point is reported the same way, with `changed`
# listing the files already renamed.
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
: > "$tmp/beside"
# shellcheck disable=SC2317  # reached through the trap
cleanup() {
  while IFS= read -r b; do rm -f "$b"; done < "$tmp/beside"
  rm -rf "$tmp"
}
trap cleanup EXIT
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

# Every file passed. Stage each new content beside its target; nothing is replaced yet.
: > "$tmp/unwritable.tsv"
i=0
for f in "$@"; do
  i=$((i + 1))
  real="$(perl -MCwd=abs_path -e 'print abs_path($ARGV[0]) // ""' "$f")"
  beside="$(dirname "$real")/.bump-version.$$.$i.tmp"
  # cp -p gives the temporary file the target's mode; the content then goes into it.
  if [ -n "$real" ] && [ -w "$real" ] && printf '%s\n' "$beside" >> "$tmp/beside" \
     && cp -p "$real" "$beside" 2>> "$tmp/write-errors" && cat "$tmp/$i" 2>> "$tmp/write-errors" > "$beside"; then
    printf '%s\n' "$real" > "$tmp/$i.real"
    printf '%s\n' "$beside" > "$tmp/$i.beside"
  else
    echo "bump-version: $f: not writable" >&2
    printf '%s\n' "$f" >> "$tmp/unwritable.tsv"
  fi
done

refuse_unwritable() { # $@: the paths already renamed
  jq -n --rawfile bad "$tmp/unwritable.tsv" \
    '{changed: $ARGS.positional,
      refused: ($bad | split("\n") | map(select(. != "") | {path: ., matches: 1, error: "not writable"}))}' --args "$@"
}

if [ -s "$tmp/unwritable.tsv" ]; then
  [ ! -s "$tmp/write-errors" ] || cat "$tmp/write-errors" >&2
  echo "bump-version: nothing written" >&2
  refuse_unwritable
  exit 1
fi

# Every temporary file is in place: rename each over its target.
done_paths=()
i=0
for f in "$@"; do
  i=$((i + 1))
  if mv -f "$(cat "$tmp/$i.beside")" "$(cat "$tmp/$i.real")"; then
    done_paths+=("$f")
  else
    echo "bump-version: $f: rename failed" >&2
    printf '%s\n' "$f" >> "$tmp/unwritable.tsv"
  fi
done
if [ -s "$tmp/unwritable.tsv" ]; then
  refuse_unwritable ${done_paths[@]+"${done_paths[@]}"}
  exit 1
fi
echo "bump-version: $old -> $new in $# file(s)" >&2
jq -n '{changed: $ARGS.positional}' --args "$@"
