#!/bin/bash
# Select the N most recent parent sessions across Claude Code, Codex, Grok and agy logs,
# keep each one's child logs with it, and split them into round-robin batches.
# Read-only over every log: never writes beside them, never decompresses in place.
#
# Usage: select-sessions.sh --out <dir> [--count N] [--batches B] [--exclude <id>]...
#                           [--keep-automated] [--harness claude|codex|grok|agy]...
#   --count N         parent sessions to select (default 50)
#   --batches B       round-robin batch files to write (default 7)
#   --exclude <id>    a session id to leave out (the current retro, a known worker)
#   --keep-automated  do not exclude sessions with an automation hint
#   --harness H       only these harnesses (default all four)
#
# Writes into <dir>: parents.jsonl (one root per line: harness, id, path, timestamp,
#   children[], first_prompt, hint, clue), batch_<k>.jsonl, exclusions.jsonl.
# Prints JSON: {"selected":{harness:n},"children":n,"excluded":{reason:n},
#   "unreadable":[paths],"missing":[harnesses],"batches":[paths],"out":dir}
#
# A "hint" (headless entrypoint, panelist brief, orphan child) excludes a root; a "clue"
# (a /private/tmp cwd) only marks it. Neither is proof: the caller reads first_prompt for
# every selected root and reruns with --exclude for any that is not a human session.

set -e

count=50; batches=7; out=""; keep_auto=0
excludes=(); harnesses=()
while [ $# -gt 0 ]; do
  case "$1" in
    --count) count=$2; shift ;;
    --batches) batches=$2; shift ;;
    --out) out=$2; shift ;;
    --exclude) excludes+=("$2"); shift ;;
    --keep-automated) keep_auto=1 ;;
    --harness) harnesses+=("$2"); shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done
[ -n "$out" ] || { echo "--out <dir> is required" >&2; exit 2; }
[ ${#harnesses[@]} -gt 0 ] || harnesses=(claude codex grok agy)
mkdir -p "$out"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
cands="$work/cands.jsonl"; : > "$cands"
unreadable="$work/unreadable"; : > "$unreadable"
missing=()
# Pre-filter: only the newest files by mtime are opened, so old archives are never streamed.
limit=$(( count * 4 < 200 ? 200 : count * 4 ))

# Sort by mtime after stat, so xargs splitting a long list into chunks cannot misorder it.
if stat -c %Y / >/dev/null 2>&1; then stat_fmt=(-c $'%Y\t%n'); else stat_fmt=(-f $'%m\t%N'); fi
newest() { xargs -0 stat "${stat_fmt[@]}" 2>/dev/null | sort -rn | head -n "$limit" | cut -f2-; }
want() { local h; for h in "${harnesses[@]}"; do [ "$h" = "$1" ] && return 0; done; return 1; }
read_log() { case "$1" in *.zst) zstd -dc -- "$1" ;; *) cat -- "$1" ;; esac; }
mtime_iso() { date -u -r "$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1")" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$(stat -c %Y "$1")" +%Y-%m-%dT%H:%M:%SZ; }

# --- Claude Code: <project>/<uuid>.jsonl owns <uuid>/subagents/agent-*.jsonl ----------
if want claude; then
  if [ -d ~/.claude/projects ]; then
    echo ">> claude: scanning" >&2
    find ~/.claude/projects -type f -name '*.jsonl' ! -path '*/subagents/*' ! -path '*--claude-worktrees-agent-*' -print0 | newest |
    while IFS= read -r f; do
      id=$(basename "$f" .jsonl)
      kids=$(find "${f%.jsonl}/subagents" -name 'agent-*.jsonl' 2>/dev/null | jq -R . | jq -sc . || echo '[]')
      jq -c --arg path "$f" --arg id "$id" --argjson kids "${kids:-[]}" -n '
        [inputs | select(.type=="user" or .type=="assistant")] as $ev
        | ($ev | map(select(.type=="user" and (.message.content|type=="string")
              and ((.message.content|startswith("<"))|not))) | first // null) as $p
        | if ($ev|length)==0 then empty else
          {harness:"claude", id:$id, path:$path, timestamp:($ev|map(.timestamp//empty)|last),
           children:$kids, first_prompt:(($p.message.content // "")[0:200]),
           hint:(if ($ev|map(.entrypoint//empty)|first) as $e | ($e=="sdk-cli" or $e=="sdk-py") then "headless (\($ev|map(.entrypoint//empty)|first))"
                 elif (($p.message.content // "")|test("^You are one panelist")) then "panelist brief"
                 else null end),
           clue:(if ($path|test("/-private-tmp-")) then "cwd under /private/tmp" else null end)} end' "$f" 2>/dev/null >> "$cands" || echo "$f" >> "$unreadable"
    done
  else missing+=(claude); fi
fi

# --- Codex: first session_meta gives identity and the parent of a child --------------
if want codex; then
  if [ -d ~/.codex/sessions ]; then
    echo ">> codex: scanning" >&2
    find ~/.codex/sessions -type f \( -name 'rollout-*.jsonl' -o -name 'rollout-*.jsonl.zst' \) -print0 | newest > "$work/codex.list"
    while IFS= read -r f; do
      if [[ "$f" == *.zst ]] && ! command -v zstd >/dev/null; then echo "$f (no zstd)" >> "$unreadable"; continue; fi
      read_log "$f" 2>/dev/null | jq -nc --arg path "$f" '
        first(inputs | select(.type=="session_meta") | .payload) as $m
        | {harness:"codex", id:($m.id // $m.session_id), path:$path, timestamp:$m.timestamp,
           parent:(($m.source|objects|.subagent.thread_spawn.parent_thread_id?) // null),
           child:(($m.thread_source=="subagent") or ([$m.source|objects|.subagent|values]|length > 0)),
           hint:(if $m.source=="exec" then "headless codex exec" else null end)}' 2>/dev/null \
        >> "$work/codex.meta" || echo "$f" >> "$unreadable"
    done < "$work/codex.list"
    if [ -s "$work/codex.meta" ]; then
      # First prompt of each root: the first user message after the AGENTS.md / environment preamble.
      jq -sc '
        (map({key:.id, value:.}) | from_entries) as $by
        | def root($id; $n): if $n > 20 or ($by[$id]|not) then null
            elif $by[$id].child then (if $by[$id].parent then root($by[$id].parent; $n+1) else null end)
            else $id end;
          group_by(.id) | map(.[0]) as $uniq
        | ($uniq | map(select(.child)) | map(. + {root: root(.id; 0)})) as $kids
        | ($uniq | map(select(.child|not)) | map(. as $r | {harness, id, path, timestamp, hint,
             children: ($kids | map(select(.root==$r.id) | .path))}))[],
          ($kids | map(select(.root==null)) | .[] | {exclude:"orphan child", harness, id, path})' \
        "$work/codex.meta" > "$work/codex.roots"
      while IFS= read -r row; do
        if printf '%s' "$row" | jq -e 'has("exclude")' >/dev/null; then printf '%s\n' "$row" >> "$work/pre-excl"; continue; fi
        f=$(printf '%s' "$row" | jq -r .path)
        p=$(read_log "$f" 2>/dev/null | jq -rn 'first(inputs | select(.type=="response_item" and .payload.type=="message" and .payload.role=="user")
              | .payload.content[]? | (.text // "") | select(test("^\\s*(<|# AGENTS\\.md)")|not) | select(test("\\S"))) // ""' 2>/dev/null | head -c 200) || true
        printf '%s' "$row" | jq -c --arg p "$p" '. + {first_prompt:$p} | if (.hint==null and ($p|test("^You are one panelist"))) then .hint="panelist brief" else . end' >> "$cands"
      done < "$work/codex.roots"
    fi
  else missing+=(codex); fi
fi

# --- Grok: summary.json gives kind and times; a parent's history names its children ---
if want grok; then
  if [ -d ~/.grok/sessions ]; then
    echo ">> grok: scanning" >&2
    find ~/.grok/sessions -type f -name chat_history.jsonl -print0 | newest > "$work/grok.list"
    while IFS= read -r f; do
      d=$(dirname "$f"); s="$d/summary.json"
      id=$(basename "$d")
      kind=$(jq -r '.session_kind // "interactive"' "$s" 2>/dev/null || echo unknown)
      ts=$(jq -r '.last_active_at // .updated_at // empty' "$s" 2>/dev/null || true)
      [ -n "$ts" ] || ts=$(mtime_iso "$f")
      printf '%s\t%s\t%s\t%s\n' "$kind" "$id" "$f" "$ts"
    done < "$work/grok.list" > "$work/grok.meta"
    awk -F'\t' '$1 ~ /^subagent/' "$work/grok.meta" > "$work/grok.kids" || true
    awk -F'\t' '$1 !~ /^subagent/' "$work/grok.meta" | while IFS=$'\t' read -r kind id f ts; do
      kids=$(awk -F'\t' '{ print $2 "\t" $3 }' "$work/grok.kids" | while IFS=$'\t' read -r kid kf; do
        grep -qF -- "$kid" "$f" && printf '%s\n' "$kf"; done | jq -R . | jq -sc .)
      # Human text is wrapped in <user_query>; other "<...>" parts are context preambles.
      p=$(jq -rn 'first(inputs | select(.type=="user") | .content
            | (if type=="array" then .[] | (.text // "") else tostring end)
            | if test("<user_query>") then capture("<user_query>\\s*(?<q>[\\s\\S]*?)\\s*</user_query>").q
              elif test("^\\s*<") then empty else . end
            | select(test("\\S"))) // ""' "$f" 2>/dev/null | head -c 200) || true
      jq -nc --arg id "$id" --arg path "$f" --arg ts "$ts" --arg kind "$kind" --arg p "$p" --argjson kids "${kids:-[]}" \
        '{harness:"grok", id:$id, path:$path, timestamp:$ts, children:$kids, first_prompt:$p,
          hint:(if $kind=="headless" then "headless grok" elif ($p|test("^You are one panelist")) then "panelist brief"
                else null end),
          clue:(if ($path|test("%2Fprivate%2Ftmp")) then "cwd under /private/tmp" else null end)}' >> "$cands"
    done
    # A child no parent names is an orphan exclusion, not a human session.
    awk -F'\t' '{ print $2 "\t" $3 }' "$work/grok.kids" | while IFS=$'\t' read -r kid kf; do
      jq -se --arg kf "$kf" 'map(select(.harness=="grok") | .children | index($kf)) | any(. != null)' "$cands" >/dev/null 2>&1 ||
        jq -nc --arg id "$kid" --arg path "$kf" '{exclude:"orphan child", harness:"grok", id:$id, path:$path}' >> "$work/pre-excl"
    done
  else missing+=(grok); fi
fi

# --- agy: history.jsonl holds every prompt; the conversation is <id>.db ---------------
if want agy; then
  agy=~/.gemini/antigravity-cli
  if [ -d "$agy/conversations" ]; then
    echo ">> agy: scanning" >&2
    find "$agy/conversations" -type f -name '*.db' -print0 | newest | while IFS= read -r f; do
      id=$(basename "$f" .db)
      p=""; ts=""
      if [ -f "$agy/history.jsonl" ]; then
        p=$(jq -rc --arg id "$id" 'select(.conversationId==$id) | .display' "$agy/history.jsonl" 2>/dev/null | head -n 1 | cut -c1-200) || true
        ts=$(jq -rc --arg id "$id" 'select(.conversationId==$id) | .timestamp' "$agy/history.jsonl" 2>/dev/null | tail -n 1) || true
      fi
      # Not in history: a human prompt still shows as a step 14 in the .db; only relayed
      # (step 101) or empty conversations are treated as automated.
      steps=""
      if [ -z "$p" ]; then
        steps=$(sqlite3 -readonly "$f" "select group_concat(distinct step_type) from steps where step_type in (14,101)" 2>/dev/null ||
                sqlite3 -readonly "file:$f?immutable=1" "select group_concat(distinct step_type) from steps where step_type in (14,101)" 2>/dev/null) || true
      fi
      if [ -n "$ts" ]; then ts=$(date -u -r $((ts / 1000)) +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$((ts / 1000))" +%Y-%m-%dT%H:%M:%SZ); else ts=$(mtime_iso "$f"); fi
      jq -nc --arg id "$id" --arg path "$f" --arg ts "$ts" --arg p "$p" --arg steps "$steps" \
        '{harness:"agy", id:$id, path:$path, timestamp:$ts, children:[], first_prompt:$p,
          hint:(if $p=="" and ($steps|split(",")|index("14")|not) then "not in history (relayed or headless)"
                elif ($p|test("^You are one panelist")) then "panelist brief" else null end),
          clue:(if $p=="" and ($steps|split(",")|index("14")) then "not in history; prompt is step 14 in the .db" else null end)}' >> "$cands"
    done
  else missing+=(agy); fi
fi

# --- rank roots by their latest activity, linked children included -------------------
jq -r '.children[]? // empty' "$cands" | sort -u | while IFS= read -r c; do
  [ -f "$c" ] && printf '%s\t%s\n' "$c" "$(mtime_iso "$c")"
done | jq -Rn '[inputs | split("\t") | {key:.[0], value:.[1]}] | from_entries' > "$work/child-ts.json"
jq -c --slurpfile m "$work/child-ts.json" '.timestamp = ([.timestamp] + ((.children // []) | map($m[0][.])) | map(select(. != null)) | max)' "$cands" > "$cands.tmp" && mv "$cands.tmp" "$cands"

# --- select, exclude, batch ------------------------------------------------------------
ex_json=$(printf '%s\n' ${excludes[@]+"${excludes[@]}"} | jq -R 'select(.!="")' | jq -sc .)
: > "$out/exclusions.jsonl"
[ -f "$work/pre-excl" ] && cat "$work/pre-excl" >> "$out/exclusions.jsonl"
jq -sc --argjson ex "$ex_json" --argjson keep "$keep_auto" --argjson n "$count" '
  map(select(.id != null))
  | (map(select(.id as $i | $ex | index($i))) | map({exclude:"excluded by caller", harness, id, path})) as $ce
  | map(select(.id as $i | ($ex | index($i)) | not))
  | (if $keep == 1 then [] else map(select(.hint != null)) | map({exclude:.hint, harness, id, path}) end) as $ae
  | (if $keep == 1 then . else map(select(.hint == null)) end)
  | sort_by(.timestamp // "") | reverse
  | {selected: .[0:$n], excluded: ($ce + $ae)}' "$cands" > "$work/result.json"
jq -c '.excluded[]' "$work/result.json" >> "$out/exclusions.jsonl"
jq -c '.selected[]' "$work/result.json" > "$out/parents.jsonl"

rm -f "$out"/batch_*.jsonl
awk -v b="$batches" -v d="$out" '{ k = ((NR - 1) % b) + 1; print > (d "/batch_" k ".jsonl") }' "$out/parents.jsonl"

jq -nc --slurpfile p "$out/parents.jsonl" --slurpfile e <(cat "$out/exclusions.jsonl") \
  --argjson unreadable "$(jq -R . < "$unreadable" | jq -sc .)" \
  --argjson missing "$(printf '%s\n' ${missing[@]+"${missing[@]}"} | jq -R 'select(.!="")' | jq -sc .)" \
  --argjson batches "$(ls "$out"/batch_*.jsonl 2>/dev/null | jq -R . | jq -sc .)" --arg out "$out" '
  {selected: ($p | group_by(.harness) | map({key:.[0].harness, value:length}) | from_entries),
   children: ($p | map(.children|length) | add // 0),
   excluded: ($e | group_by(.exclude) | map({key:.[0].exclude, value:length}) | from_entries),
   unreadable: $unreadable, missing: $missing, batches: $batches, out: $out}'
