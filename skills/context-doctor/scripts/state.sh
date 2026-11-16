#!/bin/bash
# Durable state for context-doctor, outside every repo and the session scratchpad:
#   ${CONTEXT_DOCTOR_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/context-doctor}
#     backups/<UTC stamp>/manifest.tsv + files/<absolute path>   one snapshot per apply
#     declined.jsonl                                             proposals the user said no to
#     audited.jsonl                                              files a run audited, with their hash
#
# Usage:
#   state.sh dir                       print the state dir (inventory.sh --declined <dir>/declined.jsonl)
#   state.sh snapshot <file>...        copy each file before it is edited or deleted; prints
#                                      {"backup": dir, "files": n}. Fails on a missing file.
#   state.sh restore <backup dir>      put every file of that snapshot back (recreating deleted
#                                      ones); prints {"restored": [paths]}
#   state.sh decline < proposals.jsonl append declined proposals, one JSON object per line with at
#                                      least "fingerprint"; repeats are skipped. Prints {"added","total"}
#   state.sh audited <file>...         record each file as audited today, with its sha256
#                                      (inventory.sh --audited <dir>/audited.jsonl). Prints {"added"}

set -e

state="${CONTEXT_DOCTOR_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/context-doctor}"
cmd=${1:-}; [ $# -gt 0 ] && shift

case "$cmd" in
  dir)
    mkdir -p "$state"; echo "$state" ;;
  snapshot)
    [ $# -gt 0 ] || { echo "snapshot needs at least one file" >&2; exit 2; }
    for f in "$@"; do [ -f "$f" ] || { echo "Not a file: $f" >&2; exit 1; }; done
    dest="$state/backups/$(date -u +%Y%m%dT%H%M%SZ)-$$"
    mkdir -p "$dest/files"
    for f in "$@"; do
      abs=$(cd "$(dirname "$f")" && pwd -P)/$(basename "$f")
      mkdir -p "$dest/files$(dirname "$abs")"
      cp -p "$abs" "$dest/files$abs"
      printf '%s\t%s\n' "$abs" "$(shasum -a 256 "$abs" | cut -d' ' -f1)" >> "$dest/manifest.tsv"
    done
    echo "snapshot: $# file(s) in $dest" >&2
    jq -nc --arg b "$dest" --argjson n $# '{backup:$b, files:$n}' ;;
  restore)
    dest=${1:-}
    [ -f "$dest/manifest.tsv" ] || { echo "No manifest in: $dest" >&2; exit 1; }
    restored=()
    while IFS=$'\t' read -r abs _; do
      mkdir -p "$(dirname "$abs")"
      cp -p "$dest/files$abs" "$abs"
      restored+=("$abs")
    done < "$dest/manifest.tsv"
    printf '%s\n' "${restored[@]}" | jq -R . | jq -sc '{restored: .}' ;;
  decline)
    mkdir -p "$state"
    ledger="$state/declined.jsonl"; touch "$ledger"
    before=$(wc -l < "$ledger" | tr -d ' ')
    tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
    jq -c --arg d "$(date -u +%Y-%m-%d)" 'select(.fingerprint) | . + {declined_on: (.declined_on // $d)}' > "$tmp"
    { cat "$ledger"; cat "$tmp"; } | jq -sc 'unique_by(.fingerprint)[]' > "$ledger.new"
    mv "$ledger.new" "$ledger"
    after=$(wc -l < "$ledger" | tr -d ' ')
    jq -nc --argjson a $((after - before)) --argjson t "$after" '{added:$a, total:$t}' ;;
  audited)
    [ $# -gt 0 ] || { echo "audited needs at least one file" >&2; exit 2; }
    for f in "$@"; do [ -f "$f" ] || { echo "Not a file: $f" >&2; exit 1; }; done
    mkdir -p "$state"
    for f in "$@"; do
      abs=$(cd "$(dirname "$f")" && pwd -P)/$(basename "$f")
      jq -nc --arg p "$abs" --arg h "$(shasum -a 256 "$abs" | cut -d' ' -f1)" --arg d "$(date -u +%Y-%m-%d)" \
        '{path:$p, sha256:$h, audited_on:$d}' >> "$state/audited.jsonl"
    done
    jq -nc --argjson n $# '{added:$n}' ;;
  *)
    echo "Usage: state.sh dir | snapshot <file>... | restore <backup dir> | decline < proposals.jsonl | audited <file>..." >&2
    exit 2 ;;
esac
