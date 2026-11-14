#!/bin/bash
# Offline test for screenshots-report.sh.
# Usage: test-screenshots-report.sh    (prints one "ok <case>" line per case; exits 1 on the first failure)

set -e

here=$(cd "$(dirname "$0")" && pwd)
script="$here/screenshots-report.sh"
T=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$T"' EXIT

fail() { echo "FAIL $1" >&2; [ ! -f "$T/err" ] || sed 's/^/  stderr: /' "$T/err" >&2; exit 1; }
eq() { [ "$2" = "$3" ] || fail "$1: got '$2', want '$3'"; }
q() { printf '%s' "$out" | jq -r "$1"; }

# no screenshots folder yet: nothing to upload
mkdir "$T/notes"
out=$(bash "$script" "$T/notes" 2>"$T/err") || fail "empty: exit $?"
eq "empty images" "$(q '.counts.images')" 0
eq "empty not_uploaded" "$(q '.counts.not_uploaded')" 0
eq "empty dir" "$(q '.dir')" "$T/notes/screenshots"
echo "ok a run with no screenshots reports none"

# three images and a note: every image is listed with its ticket, none uploaded
mkdir "$T/notes/screenshots"
touch "$T/notes/screenshots/03-login page.png" "$T/notes/screenshots/12-export.jpg" \
  "$T/notes/screenshots/overview.png" "$T/notes/screenshots/readme.md"
out=$(bash "$script" "$T/notes" 2>"$T/err") || fail "fresh: exit $?"
eq "fresh images" "$(q '.counts.images')" 3
eq "fresh not_uploaded" "$(q '.counts.not_uploaded')" 3
eq "fresh ticket" "$(q '.images[] | select(.file == "03-login page.png") | .ticket')" 03
eq "fresh no ticket" "$(q '.images[] | select(.file == "overview.png") | .ticket')" ""
eq "fresh path" "$(q '.images[] | select(.file == "12-export.jpg") | .path')" "$T/notes/screenshots/12-export.jpg"
[ ! -e "$T/notes/screenshots/uploaded.txt" ] || fail "fresh: a read wrote uploaded.txt"
echo "ok every image is listed with its ticket number, not uploaded"

# --uploaded records by path or by name, once
out=$(bash "$script" "$T/notes" --uploaded "$T/notes/screenshots/03-login page.png" 12-export.jpg 2>"$T/err") || fail "uploaded: exit $?"
out=$(bash "$script" "$T/notes" --uploaded 12-export.jpg 2>"$T/err") || fail "uploaded twice: exit $?"
eq "uploaded count" "$(q '.counts.uploaded')" 2
eq "uploaded left" "$(q '.counts.not_uploaded')" 1
eq "uploaded flag" "$(q '.images[] | select(.file == "03-login page.png") | .uploaded')" true
eq "uploaded lines" "$(wc -l < "$T/notes/screenshots/uploaded.txt" | tr -d ' ')" 2
echo "ok --uploaded records each image once"

# --left-out clears the last one without calling it uploaded
out=$(bash "$script" "$T/notes" --left-out overview.png 2>"$T/err") || fail "left out: exit $?"
eq "left out count" "$(q '.counts.left_out')" 1
eq "left out not_uploaded" "$(q '.counts.not_uploaded')" 0
eq "left out uploaded" "$(q '.images[] | select(.file == "overview.png") | .uploaded')" false
echo "ok --left-out clears an image without marking it uploaded"

# a new image after the uploads is not uploaded
touch "$T/notes/screenshots/03-login-fixed.png"
out=$(bash "$script" "$T/notes" 2>"$T/err") || fail "late: exit $?"
eq "late not_uploaded" "$(q '.counts.not_uploaded')" 1
echo "ok an image saved after the upload is not uploaded"

# bad input
if bash "$script" "$T/notes" --uploaded missing.png 2>"$T/err"; then fail "unknown image recorded"; fi
if grep -qx 'missing.png' "$T/notes/screenshots/uploaded.txt"; then fail "unknown image written"; fi
set +e
bash "$script" "$T/nowhere" 2>"$T/err"; code=$?
set -e
eq "missing notes dir" "$code" 2
set +e
bash "$script" "$T/notes" --uploaded 2>"$T/err"; code=$?
set -e
eq "flag without images" "$code" 2
echo "ok bad input is refused and records nothing"
