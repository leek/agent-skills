#!/bin/bash
# Durable state for context-doctor, outside every repo and the session scratchpad:
#   ${CONTEXT_DOCTOR_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/context-doctor}
#     backups/<UTC stamp>/manifest.tsv + files/<absolute path>   one snapshot per apply
#     declined.jsonl                                             proposals the user said no to
#     audited.jsonl                                              files a run audited, with their hash
#
# Usage:
#   state.sh dir                       print the state dir (inventory.sh --declined <dir>/declined.jsonl)
#   state.sh snapshot <file>... [--new <file>]...
#                                      copy each file before it is edited or deleted (a symlink is
#                                      kept as a symlink), and record each --new file, one about to be
#                                      created, as absent; prints {"backup": dir, "files": n}. Fails,
#                                      writing nothing, on a missing file or an existing --new one.
#   state.sh restore <backup dir>      return every path to its snapshot state: files and symlinks
#                                      put back (never written through a symlink now in their place),
#                                      --new files removed. Checks every backup copy against its hash
#                                      first. Prints {"restored": [paths], "removed": [paths]}
#   state.sh decline [proposals.jsonl] append declined proposals (the file, or stdin), one JSON object
#                                      per line with at least "fingerprint"; repeats are skipped.
#                                      Prints {"added","total"}
#   state.sh audited <file>...         record each file as audited today, with its sha256
#                                      (inventory.sh --audited <dir>/audited.jsonl). Prints {"added"}

set -e
umask 077  # backups hold memory and instruction text: readable by this user only

state="${CONTEXT_DOCTOR_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/context-doctor}"
json_list() { if [ $# -gt 0 ]; then printf '%s\n' "$@" | jq -R . | jq -sc .; else echo '[]'; fi; }
absolute() {  # absolute path, the directory resolved, the last component kept (a symlink stays one)
  local d; d=$(cd "$(dirname "$1")" 2>/dev/null && pwd -P) || { echo "No such directory: $(dirname "$1")" >&2; return 1; }
  printf '%s/%s\n' "$d" "$(basename "$1")"
}
cmd=${1:-}; [ $# -gt 0 ] && shift

case "$cmd" in
  dir)
    mkdir -p "$state"; echo "$state" ;;
  snapshot)
    [ $# -gt 0 ] || { echo "snapshot needs at least one file" >&2; exit 2; }
    # Check everything before writing anything: one bad path leaves no half snapshot.
    rows=()
    while [ $# -gt 0 ]; do
      if [ "$1" = "--new" ]; then
        [ -n "${2:-}" ] || { echo "--new needs a file" >&2; exit 2; }
        { [ -e "$2" ] || [ -L "$2" ]; } && { echo "Already exists (snapshot it without --new): $2" >&2; exit 1; }
        rows+=("$(absolute "$2")"$'\t'"absent"); shift 2; continue
      fi
      if [ -L "$1" ]; then
        rows+=("$(absolute "$1")"$'\t'"link")
      elif [ -f "$1" ]; then
        rows+=("$(absolute "$1")"$'\t'"file")
      else
        echo "Not a file: $1" >&2; exit 1
      fi
      shift
    done
    dest="$state/backups/$(date -u +%Y%m%dT%H%M%SZ)-$$"
    mkdir -p "$dest/files"
    for row in "${rows[@]}"; do
      abs=${row%%$'\t'*}; kind=${row#*$'\t'}; hash="-"
      if [ "$kind" != "absent" ]; then
        mkdir -p "$dest/files$(dirname "$abs")"
        cp -pP "$abs" "$dest/files$abs"
        [ "$kind" = "file" ] && hash=$(shasum -a 256 "$abs" | cut -d' ' -f1)
      fi
      printf '%s\t%s\t%s\n' "$abs" "$kind" "$hash" >> "$dest/manifest.tsv"
    done
    echo "snapshot: ${#rows[@]} path(s) in $dest" >&2
    jq -nc --arg b "$dest" --argjson n ${#rows[@]} '{backup:$b, files:$n}' ;;
  restore)
    dest=${1:-}
    [ -f "$dest/manifest.tsv" ] || { echo "No manifest in: $dest" >&2; exit 1; }
    # A two-column manifest (older snapshots) is <path> <sha256> of a regular file.
    while IFS=$'\t' read -r abs kind hash; do
      [ -n "$hash" ] || { hash=$kind; kind=file; }
      if [ "$kind" = "file" ] && [ "$(shasum -a 256 "$dest/files$abs" 2>/dev/null | cut -d' ' -f1)" != "$hash" ]; then
        echo "Backup copy of $abs is missing or changed; nothing restored" >&2; exit 1
      fi
    done < "$dest/manifest.tsv"
    restored=(); removed=()
    while IFS=$'\t' read -r abs kind hash; do
      [ -n "$hash" ] || kind=file
      rm -f "$abs"  # never write through whatever now sits at this path
      if [ "$kind" = "absent" ]; then
        removed+=("$abs")
      else
        mkdir -p "$(dirname "$abs")"
        cp -pP "$dest/files$abs" "$abs"
        restored+=("$abs")
      fi
    done < "$dest/manifest.tsv"
    jq -nc --argjson r "$(json_list ${restored[@]+"${restored[@]}"})" --argjson d "$(json_list ${removed[@]+"${removed[@]}"})" \
      '{restored: $r, removed: $d}' ;;
  decline)
    mkdir -p "$state"
    ledger="$state/declined.jsonl"; touch "$ledger"
    before=$(wc -l < "$ledger" | tr -d ' ')
    tmp=$(mktemp); trap 'rm -f "$tmp" "$ledger.new"' EXIT
    if [ $# -eq 0 ]; then
      jq -c --arg d "$(date -u +%Y-%m-%d)" 'select(.fingerprint) | . + {declined_on: (.declined_on // $d)}' > "$tmp"
    else
      [ -r "$1" ] || { echo "Unreadable: $1" >&2; exit 1; }
      jq -c --arg d "$(date -u +%Y-%m-%d)" 'select(.fingerprint) | . + {declined_on: (.declined_on // $d)}' "$1" > "$tmp"
    fi
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
    echo "Usage: state.sh dir | snapshot <file>... [--new <file>]... | restore <backup dir> | decline [proposals.jsonl] | audited <file>..." >&2
    exit 2 ;;
esac
