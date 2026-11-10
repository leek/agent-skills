#!/bin/bash
# Detect the package managers of the project in the current directory, run each one's
# outdated and security-audit commands, and print the results as one JSON object.
# Read-only: it never installs, updates, or requires anything.
#
# Usage: audit.sh [composer|npm]
#   (none)     audit every manager whose manifest is in the current directory:
#              composer.json -> composer, package.json -> npm, both -> both
#   composer   only Composer; exit 1 when composer.json is missing
#   npm        only npm; exit 1 when package.json is missing
#
# Stdout: one JSON object
#   {"managers": [{
#      "manager": "composer" | "npm",
#      "manifest": "composer.json" | "package.json",
#      "lockfile": "composer.lock" | "npm-shrinkwrap.json" | "package-lock.json" | null,
#      "outdated": {"patch": [E], "minor": [E], "major": [E]},
#          E = {"package", "current", "latest", "direct": bool}
#      "advisories": [{"package", "severity", "id", "title", "url"}],   most severe first
#      "errors": ["..."]
#   }]}
# Stderr: status. Exit: 0 at least one manager was audited (read its "errors"); 1 no
# manifest for the requested manager, or neither manifest (prints {"managers": []});
# 2 usage, or a manager other than composer or npm; 3 jq is missing.
#
# What it runs (flags confirmed with --help on Composer 2.10.3 and npm 11.20.0):
#   Composer runs with --no-plugins --no-scripts: the project under audit is not trusted, and a
#   plugin or a script in its composer.json would otherwise run on these read-only commands.
#   npm outdated and npm audit run no lifecycle scripts, so npm needs no such flag.
#   composer outdated --direct --format=json --no-interaction --no-plugins --no-scripts
#   composer audit --format=json --locked --no-interaction --no-plugins --no-scripts     only with composer.lock
#   npm outdated --json
#   npm audit --json                  only with package-lock.json or npm-shrinkwrap.json
# No lockfile: "lockfile" is null, the security audit is not run, "advisories" is [].
# The tools exit non-zero when they find something (composer audit, npm outdated,
# npm audit all exit 1): that is data. A run counts as failed only when its stdout is not
# the JSON the tool prints on success; the reason then goes in "errors".
#
# Grouping is numeric on the first two version segments (a leading "v" and any
# pre-release or build suffix dropped): first segment differs -> major, second -> minor,
# otherwise patch. A version that is not numeric (dev-main) goes in "major", with a line
# in "errors". An npm package that is not installed has "current": null and is grouped
# from its wanted version, with a line in "errors". Whether a 0.x minor bump is breaking
# is the agent's call.
#
# JSON fields read, each seen in a real run of the tool:
#   composer outdated  .installed[] | .name .version .latest ."direct-dependency"
#   composer audit     .advisories{"<package>": [ .advisoryId .packageName .title .link
#                      .severity ]}   (.advisories is [] when there are none)
#   npm outdated       {"<package>": {.current .wanted .latest}}; "direct" is membership
#                      in package.json's dependency sections
#   npm audit          .auditReportVersion, .vulnerabilities{"<package>": {.via[]}}; each
#                      object in .via is one advisory: .source .name .title .url .severity
#                      (a string in .via names another vulnerable package, not an advisory)
#   npm failure        {"error": {.code .summary .detail}} on stdout

set -e

usage() {
  echo "Usage: audit.sh [composer|npm]" >&2
  exit 2
}

[ $# -le 1 ] || usage
want=${1:-}
case "$want" in
  "" | composer | npm) ;;
  -h | --help) usage ;;
  *) echo "audit.sh: only Composer and npm are supported (got '$want')" >&2; exit 2 ;;
esac
command -v jq >/dev/null || { echo "audit.sh: jq is required" >&2; exit 3; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
: > "$tmp/managers.jsonl"

# Shared jq: version grouping and advisory order.
JQ_LIB='
def nums: tostring | ltrimstr("v") | split("+")[0] | split("-")[0] | split(".") | map(tonumber? // null);
def bump($from; $to):
  ($from | nums) as $c | ($to | nums) as $l
  | if ($c | length) == 0 or ($l | length) == 0 or ($c | any(. == null)) or ($l | any(. == null)) then "unknown"
    elif $c[0] != $l[0] then "major"
    elif ($c[1] // 0) != ($l[1] // 0) then "minor"
    else "patch" end;
# Input: [{package, current, latest, direct, base}], base being the version to group from.
def grouped:
  map(. + {bump: bump(.base; .latest)}) as $all
  | def pick($b): $all | map(select(.bump == $b) | del(.bump, .base));
    {outdated: {patch: pick("patch"), minor: pick("minor"), major: (pick("major") + pick("unknown"))},
     errors: ($all | map(select(.bump == "unknown")
       | "cannot compare \(.package) \(.base) with \(.latest): not numeric versions, listed under major"))};
def rank: {"critical": 0, "high": 1, "medium": 2, "moderate": 2, "low": 3, "info": 4}[. // ""] // 5;
def by_severity: unique_by([.package, .id]) | sort_by([(.severity | rank), .package, .id]);
'
EMPTY_OUTDATED='{"patch":[],"minor":[],"major":[]}'

# One line of a tool's stderr, for an error string.
squash() { tr '\n' ' ' < "$1" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' | cut -c1-600; }
note() { echo "audit.sh: $1" >&2; }

# emit <manager> <manifest> <lockfile or ""> <outdated json> <advisories json> <errors file>
emit() {
  jq -n --arg manager "$1" --arg manifest "$2" --arg lockfile "$3" \
    --argjson outdated "$4" --argjson advisories "$5" --rawfile errors "$6" '{
      manager: $manager, manifest: $manifest,
      lockfile: (if $lockfile == "" then null else $lockfile end),
      outdated: $outdated, advisories: $advisories,
      errors: ($errors | split("\n") | map(select(. != "")))
    }' >> "$tmp/managers.jsonl"
}

audit_composer() {
  local lock="" out="$tmp/composer.out" err="$tmp/composer.err" errs="$tmp/composer.errors"
  local outdated="$EMPTY_OUTDATED" advisories='[]' res rc
  : > "$errs"
  if [ -f composer.lock ]; then lock=composer.lock; fi

  if ! command -v composer >/dev/null; then
    echo "composer is not on PATH" >> "$errs"
    emit composer composer.json "$lock" "$outdated" "$advisories" "$errs"
    return 0
  fi

  local abandoned="$tmp/composer-abandoned"
  : > "$abandoned"
  note "composer outdated"
  rc=0
  composer outdated --direct --format=json --no-interaction --no-plugins --no-scripts > "$out" 2> "$err" || rc=$?
  if jq -e 'type == "object" and (.installed | type == "array")' "$out" >/dev/null 2>&1; then
    res=$(jq "$JQ_LIB"'[.installed[] | select(.latest != null and .latest != .version)
      | {package: .name, current: .version, latest: .latest,
         direct: (."direct-dependency" == true), base: .version}] | grouped' "$out")
    outdated=$(jq -n --argjson r "$res" '$r.outdated')
    jq -n -r --argjson r "$res" '$r.errors[]' >> "$errs"
    # Abandoned packages carry no version to compare, so they go out as notes in "errors".
    # (Shape not seen in a real run: any value other than false or null counts, and a
    # string is taken as the replacement.)
    jq -r '.installed[] | select(.abandoned != null and .abandoned != false)
      | "abandoned package: \(.name)" + (if (.abandoned | type) == "string" then " (replacement: \(.abandoned))" else "" end)' "$out" > "$abandoned" 2>/dev/null || true
  else
    echo "composer outdated printed no package list (exit $rc): $(squash "$err")" >> "$errs"
  fi

  if [ -n "$lock" ]; then
    note "composer audit"
    rc=0
    composer audit --format=json --locked --no-interaction --no-plugins --no-scripts > "$out" 2> "$err" || rc=$?
    if jq -e 'type == "object" and has("advisories")' "$out" >/dev/null 2>&1; then
      advisories=$(jq "$JQ_LIB"'[.advisories | .. | objects | select(has("advisoryId"))
        | {package: .packageName, severity: (.severity // null), id: .advisoryId,
           title: .title, url: (.link // null)}] | by_severity' "$out")
      jq -r '.abandoned | objects | to_entries[]
        | "abandoned package: \(.key)" + (if (.value | type) == "string" then " (replacement: \(.value))" else "" end)' "$out" >> "$abandoned" 2>/dev/null || true
    else
      echo "composer audit printed no report (exit $rc): $(squash "$err")" >> "$errs"
    fi
  else
    note "no composer.lock: security audit not run"
  fi

  sort -u "$abandoned" >> "$errs"
  emit composer composer.json "$lock" "$outdated" "$advisories" "$errs"
}

# npm prints {"error": {"code", "summary", "detail"}} on stdout when a command fails.
NPM_FAILED='(.error? | type) == "object" and (.error | has("summary")) and (.error | has("latest") | not)'

npm_reason() {
  # <stdout file> <stderr file>
  jq -e -r "if $NPM_FAILED then \"\(.error.code // \"\") \(.error.summary // \"\")\" else empty end" "$1" 2>/dev/null ||
    squash "$2"
}

audit_npm() {
  local lock="" out="$tmp/npm.out" err="$tmp/npm.err" errs="$tmp/npm.errors"
  local outdated="$EMPTY_OUTDATED" advisories='[]' res rc missing
  : > "$errs"
  if [ -f npm-shrinkwrap.json ]; then
    lock=npm-shrinkwrap.json
  elif [ -f package-lock.json ]; then
    lock=package-lock.json
  fi

  if ! command -v npm >/dev/null; then
    echo "npm is not on PATH" >> "$errs"
    emit npm package.json "$lock" "$outdated" "$advisories" "$errs"
    return 0
  fi
  if ! jq -e 'type == "object"' package.json >/dev/null 2>&1; then
    echo "package.json is not a JSON object" >> "$errs"
    emit npm package.json "$lock" "$outdated" "$advisories" "$errs"
    return 0
  fi

  note "npm outdated"
  rc=0
  npm outdated --json > "$out" 2> "$err" || rc=$?
  if jq -e "type == \"object\" and ($NPM_FAILED | not)" "$out" >/dev/null 2>&1; then
    res=$(jq --slurpfile manifest package.json "$JQ_LIB"'
      ($manifest[0] | [.dependencies, .devDependencies, .optionalDependencies, .peerDependencies]
        | map(. // {} | keys) | add) as $direct
      | [to_entries[] | .key as $name | (.value | if type == "array" then .[] else . end)
          | select(type == "object" and .latest != null and .latest != .current)
          | {package: $name, current: (.current // null), latest: .latest,
             direct: ($direct | index($name) != null), base: (.current // .wanted)}]
      | unique_by([.package, .current]) | grouped' "$out")
    outdated=$(jq -n --argjson r "$res" '$r.outdated')
    jq -n -r --argjson r "$res" '$r.errors[]' >> "$errs"
    missing=$(jq -n --argjson r "$res" '[$r.outdated[][] | select(.current == null)] | length')
    if [ "$missing" -gt 0 ]; then
      echo "$missing npm packages are not installed (no node_modules?): current is null, grouped from the wanted version" >> "$errs"
    fi
  else
    echo "npm outdated printed no package list (exit $rc): $(npm_reason "$out" "$err")" >> "$errs"
  fi

  if [ -n "$lock" ]; then
    note "npm audit"
    rc=0
    npm audit --json > "$out" 2> "$err" || rc=$?
    if jq -e 'type == "object" and has("auditReportVersion") and (.vulnerabilities | type == "object")' "$out" >/dev/null 2>&1; then
      advisories=$(jq "$JQ_LIB"'[.vulnerabilities[] | .via[]? | objects
        | {package: (.name // .dependency), severity: (.severity // null),
           id: (.source | tostring), title: .title, url: (.url // null)}] | by_severity' "$out")
    else
      echo "npm audit printed no report (exit $rc): $(npm_reason "$out" "$err")" >> "$errs"
    fi
  else
    note "no package-lock.json or npm-shrinkwrap.json: security audit not run"
  fi

  emit npm package.json "$lock" "$outdated" "$advisories" "$errs"
}

ran=0
if [ "$want" = composer ] || [ -z "$want" ]; then
  if [ -f composer.json ]; then
    audit_composer
    ran=1
  elif [ "$want" = composer ]; then
    note "composer.json is missing in $(pwd)"
  fi
fi
if [ "$want" = npm ] || [ -z "$want" ]; then
  if [ -f package.json ]; then
    audit_npm
    ran=1
  elif [ "$want" = npm ]; then
    note "package.json is missing in $(pwd)"
  fi
fi

jq -s '{managers: .}' "$tmp/managers.jsonl"
if [ "$ran" = 0 ]; then
  [ -n "$want" ] || note "no composer.json or package.json in $(pwd): not a Composer or npm project"
  exit 1
fi
