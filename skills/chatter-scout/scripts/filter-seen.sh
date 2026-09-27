#!/bin/bash
# Seen-ledger for chatter-scout. The ledger is a JSON array of URL strings.
#
# Usage:
#   filter-seen.sh filter <ledger.json> < candidates.json
#       candidates: JSON array of objects with a "url" field.
#       stdout: the candidates whose normalized URL is not in the ledger,
#               deduped within the batch, each "url" rewritten to its normalized form.
#   filter-seen.sh add <ledger.json> < urls.json
#       urls: JSON array of URL strings. Adds their normalized forms to the ledger.
#       Never removes an entry. stdout: {"added": N, "total": M}
#
# A missing ledger counts as []. Normalizing lowercases the host, drops "www.",
# the fragment, tracking params (utm_*, fbclid, gclid, mc_*), and a trailing slash.
set -euo pipefail

MODE="${1:-}"
LEDGER="${2:-}"
if [[ -z "$MODE" || -z "$LEDGER" ]]; then
  echo "Usage: $0 filter|add <ledger.json> < input.json" >&2
  exit 2
fi
command -v jq >/dev/null || { echo "ERROR: jq is required" >&2; exit 1; }

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

SEEN='[]'
if [[ -s "$LEDGER" ]]; then
  SEEN=$(jq -c 'if type == "array" then . else error("ledger is not a JSON array") end' "$LEDGER")
fi

NORM='
def norm:
  sub("#.*$"; "")
  | sub("^(?<s>[A-Za-z]+)://(www\\.)?(?<h>[^/?]+)"; "\(.s | ascii_downcase)://\(.h | ascii_downcase)"; "i")
  | sub("^http://"; "https://")
  | if test("\\?") then
      (split("?")) as $p
      | ($p[1:] | join("?") | split("&")
         | map(select(test("^(utm_[^=]*|fbclid|gclid|mc_[^=]*)(=|$)") | not))
         | join("&")) as $q
      | $p[0] + (if $q == "" then "" else "?" + $q end)
    else . end
  | sub("/+$"; "");
'

case "$MODE" in
  filter)
    jq -c --argjson seen "$SEEN" "$NORM"'
      ($seen | map(norm)) as $s
      | map(.url |= norm)
      | map(select(.url as $u | $s | index([$u]) | not))
      | unique_by(.url)
    '
    ;;
  add)
    jq -c --argjson seen "$SEEN" "$NORM"'
      ($seen | map(norm)) as $s
      | (map(norm) | unique | map(select(. as $u | $s | index([$u]) | not))) as $new
      | {added: ($new | length), all: ($seen + $new)}
    ' > "$TMP"
    mkdir -p "$(dirname "$LEDGER")"
    jq '.all' "$TMP" > "$LEDGER.tmp" && mv "$LEDGER.tmp" "$LEDGER"
    jq -c '{added, total: (.all | length)}' "$TMP"
    echo "ledger updated: $LEDGER" >&2
    ;;
  *)
    echo "Unknown mode: $MODE (want filter or add)" >&2
    exit 2
    ;;
esac
