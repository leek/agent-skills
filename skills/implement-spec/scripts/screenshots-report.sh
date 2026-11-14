#!/bin/bash
# Which of an implement-spec run's screenshots reached a pull request, so the run cannot
# close as delivered while one did not. No network: "uploaded" is what the run recorded
# here after a successful upload-screenshots.sh call, not a lookup.
#
# Usage: screenshots-report.sh <notes dir> [--uploaded <image>... | --left-out <image>...]
#   <notes dir> is the run's notes directory (spec-run-state.sh's "notes"); the images are
#   the .png, .jpg, .jpeg, .gif and .webp files directly in <notes dir>/screenshots/.
#   --uploaded <image>...  record each image (a path or a file name) as uploaded, in
#                          screenshots/uploaded.txt, one file name per line; then report.
#   --left-out <image>...  record each as left out of every pull request on purpose (a
#                          failure fixed later, other work, PII), in screenshots/left-out.txt.
#   An image named with a flag must exist in the folder (exit 1, nothing recorded).
#   Without a flag it changes nothing. Needs jq.
#
# Output: JSON
#   {"dir", "images": [{"file", "path", "ticket", "uploaded", "left_out"}],
#    "counts": {"images", "uploaded", "left_out", "not_uploaded"}}
#   "ticket" is the digits the file name starts with ("03" for 03-login.png), else "".
#   "not_uploaded" counts the images neither uploaded nor left out. A missing screenshots/
#   folder reports no images.
#
# Exit: 0 reported, 1 an image named with a flag is not in the folder or jq is missing,
# 2 usage error.

set -e

usage() { echo "Usage: screenshots-report.sh <notes dir> [--uploaded <image>... | --left-out <image>...]" >&2; exit 2; }

notes=${1:-}
[ -n "$notes" ] && [ -d "$notes" ] || { [ -z "$notes" ] || echo "Not a directory: $notes" >&2; usage; }
shift
command -v jq >/dev/null 2>&1 || { echo "screenshots-report.sh needs jq on PATH" >&2; exit 1; }

dir="$(cd "$notes" && pwd -P)/screenshots"

if [ $# -gt 0 ]; then
  case "$1" in
    --uploaded) list="$dir/uploaded.txt" ;;
    --left-out) list="$dir/left-out.txt" ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
  shift
  [ $# -gt 0 ] || usage
  for f in "$@"; do
    [ -f "$dir/$(basename "$f")" ] || { echo "Not in $dir: $(basename "$f")" >&2; exit 1; }
  done
  for f in "$@"; do
    name=$(basename "$f")
    grep -qxF -- "$name" "$list" 2>/dev/null || printf '%s\n' "$name" >> "$list"
  done
fi

listed() { [ -f "$2" ] && grep -qxF -- "$1" "$2"; }  # listed <name> <list file>
bool() { "$@" && echo true || echo false; }

images='[]'
if [ -d "$dir" ]; then
  for f in "$dir"/*; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    case "$name" in
      *.png | *.jpg | *.jpeg | *.gif | *.webp | *.PNG | *.JPG | *.JPEG | *.GIF | *.WEBP) ;;
      *) continue ;;
    esac
    ticket=$(printf '%s' "$name" | sed -n 's/^\([0-9][0-9]*\).*/\1/p')
    images=$(jq -cn --argjson all "$images" --arg file "$name" --arg path "$f" --arg ticket "$ticket" \
      --argjson uploaded "$(bool listed "$name" "$dir/uploaded.txt")" \
      --argjson left_out "$(bool listed "$name" "$dir/left-out.txt")" \
      '$all + [{file: $file, path: $path, ticket: $ticket, uploaded: $uploaded, left_out: $left_out}]')
  done
fi

jq -cn --arg dir "$dir" --argjson images "$images" \
  '{dir: $dir, images: $images,
    counts: {images: ($images | length),
             uploaded: ($images | map(select(.uploaded)) | length),
             left_out: ($images | map(select(.left_out and (.uploaded | not))) | length),
             not_uploaded: ($images | map(select((.uploaded or .left_out) | not)) | length)}}'
