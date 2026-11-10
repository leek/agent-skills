#!/bin/bash
# Offline test for audit.sh. `composer` and `npm` are stubs first on PATH: they print the
# JSON in fixtures/ (captured from real runs of Composer 2.10.3 and npm 11.20.0 in a
# throwaway project; composer-audit.json is cut to 4 of its 18 advisories and the
# machine paths in npm-outdated.json are replaced) and exit with the real tools' codes.
# Prints one "ok <case>" line per case and exits non-zero on the first failed assertion.

set -e
set -o pipefail

here=$(cd "$(dirname "$0")" && pwd)
script="$here/audit.sh"
fixtures="$here/fixtures"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL $1" >&2; exit 1; }
eq() { [ "$2" = "$3" ] || fail "$1: got '$2', want '$3'"; }

# The stub prints $STUB_DIR/<tool>-<subcommand>.out and .err, exits with the number in
# .rc, and logs its arguments. Any other subcommand (install, update, ...) fails loudly.
mkdir -p "$tmp/bin"
for tool in composer npm; do
  {
    echo '#!/bin/bash'
    echo "tool=$tool"
    echo 'echo "$tool $*" >> "$STUB_LOG"'
    echo 'case "$1" in outdated | audit) ;; *) echo "stub: $tool $1 is not read-only" >&2; exit 99 ;; esac'
    echo 'base="$STUB_DIR/$tool-$1"'
    echo '[ -f "$base.err" ] && cat "$base.err" >&2'
    echo '[ -f "$base.out" ] && cat "$base.out"'
    echo 'exit "$(cat "$base.rc" 2>/dev/null || echo 0)"'
  } > "$tmp/bin/$tool"
  chmod +x "$tmp/bin/$tool"
done
export PATH="$tmp/bin:$PATH"
export STUB_LOG="$tmp/calls.log"

# stubs <name>: a fresh stub-output directory holding the real findings and exit codes.
stubs() {
  export STUB_DIR="$tmp/stub-$1"
  mkdir -p "$STUB_DIR"
  cp "$fixtures/composer-outdated.json" "$STUB_DIR/composer-outdated.out"
  echo "Composer could not detect the root package version" > "$STUB_DIR/composer-outdated.err"
  echo 0 > "$STUB_DIR/composer-outdated.rc"
  cp "$fixtures/composer-audit.json" "$STUB_DIR/composer-audit.out"
  echo 1 > "$STUB_DIR/composer-audit.rc"
  cp "$fixtures/npm-outdated.json" "$STUB_DIR/npm-outdated.out"
  echo 1 > "$STUB_DIR/npm-outdated.rc"
  cp "$fixtures/npm-audit.json" "$STUB_DIR/npm-audit.out"
  echo 1 > "$STUB_DIR/npm-audit.rc"
}
# project <name> <files...>: a project directory holding those (empty-ish) files.
project() {
  local dir="$tmp/$1" f
  shift
  mkdir -p "$dir"
  cd "$dir"
  for f in "$@"; do
    case "$f" in
      package.json) echo '{"dependencies":{"lodash":"4.17.20","minimist":"1.2.0","chalk":"4.0.0"},"devDependencies":{"semver":"7.5.0"}}' > "$f" ;;
      *) echo '{}' > "$f" ;;
    esac
  done
}
# run [args]: sets $rc and writes $tmp/out.json
run() {
  : > "$STUB_LOG"
  rc=0
  bash "$script" "$@" > "$tmp/out.json" 2> "$tmp/stderr" || rc=$?
  cat "$STUB_LOG" >> "$tmp/all-calls.log"
}
names() { jq -c "[.managers[$1].outdated.$2[].package]" "$tmp/out.json"; }

# --- composer: grouping, advisories, exit 1 from the audit is data -------------------
stubs findings
project composer-only composer.json composer.lock
run
eq "composer: exit" "$rc" 0
eq "composer: managers" "$(jq -c '[.managers[].manager]' "$tmp/out.json")" '["composer"]'
eq "composer: manifest" "$(jq -r '.managers[0].manifest' "$tmp/out.json")" composer.json
eq "composer: lockfile" "$(jq -r '.managers[0].lockfile' "$tmp/out.json")" composer.lock
eq "composer: patch" "$(names 0 patch)" '["psr/container"]'
eq "composer: minor" "$(names 0 minor)" '["symfony/polyfill-ctype"]'
eq "composer: major" "$(names 0 major)" '["psr/log","twig/twig"]'
eq "composer: entry" "$(jq -c '.managers[0].outdated.minor[0]' "$tmp/out.json")" \
  '{"package":"symfony/polyfill-ctype","current":"v1.30.0","latest":"v1.37.0","direct":true}'
eq "composer: advisories, most severe first" "$(jq -c '[.managers[0].advisories[].severity]' "$tmp/out.json")" \
  '["critical","high","medium",null]'
eq "composer: advisory" "$(jq -c '.managers[0].advisories[0]' "$tmp/out.json")" \
  '{"package":"twig/twig","severity":"critical","id":"PKSA-h8hf-ytnd-5t9q","title":"PHP code injection via `{% use %}` template name","url":"https://symfony.com/cve-2026-46633"}'
eq "composer: errors" "$(jq -c '.managers[0].errors' "$tmp/out.json")" '[]'
eq "composer: calls" "$(cat "$STUB_LOG")" "composer outdated --direct --format=json --no-interaction --no-plugins --no-scripts
composer audit --format=json --locked --no-interaction --no-plugins --no-scripts"
echo "ok composer patch/minor/major grouping and advisories"

# --- npm: exit 1 from outdated and audit is data ---------------------------------------
project npm-only package.json package-lock.json
run
eq "npm: exit" "$rc" 0
eq "npm: managers" "$(jq -c '[.managers[].manager]' "$tmp/out.json")" '["npm"]'
eq "npm: lockfile" "$(jq -r '.managers[0].lockfile' "$tmp/out.json")" package-lock.json
eq "npm: patch" "$(names 0 patch)" '["minimist"]'
eq "npm: minor" "$(names 0 minor)" '["lodash","semver"]'
eq "npm: major" "$(names 0 major)" '["chalk"]'
eq "npm: entry" "$(jq -c '.managers[0].outdated.major[0]' "$tmp/out.json")" \
  '{"package":"chalk","current":"4.0.0","latest":"6.0.1","direct":true}'
eq "npm: advisories" "$(jq -r '.managers[0].advisories | length' "$tmp/out.json")" 7
eq "npm: advisory" "$(jq -c '.managers[0].advisories[0]' "$tmp/out.json")" \
  '{"package":"minimist","severity":"critical","id":"1097678","title":"Prototype Pollution in minimist","url":"https://github.com/advisories/GHSA-xvch-5gv4-984h"}'
eq "npm: errors" "$(jq -c '.managers[0].errors' "$tmp/out.json")" '[]'
eq "npm: calls" "$(cat "$STUB_LOG")" "npm outdated --json
npm audit --json"
echo "ok npm patch/minor/major grouping and advisories"

# --- npm-shrinkwrap.json is a lockfile, and wins -----------------------------------------
project npm-shrinkwrap package.json package-lock.json npm-shrinkwrap.json
run
eq "shrinkwrap: lockfile" "$(jq -r '.managers[0].lockfile' "$tmp/out.json")" npm-shrinkwrap.json
echo "ok npm-shrinkwrap.json lockfile"

# --- both managers, and the argument that picks one ----------------------------------------
project both composer.json composer.lock package.json package-lock.json
run
eq "both: exit" "$rc" 0
eq "both: managers" "$(jq -c '[.managers[].manager]' "$tmp/out.json")" '["composer","npm"]'
eq "both: composer major" "$(names 0 major)" '["psr/log","twig/twig"]'
eq "both: npm major" "$(names 1 major)" '["chalk"]'
run npm
eq "both, npm asked: managers" "$(jq -c '[.managers[].manager]' "$tmp/out.json")" '["npm"]'
grep -q '^composer' "$STUB_LOG" && fail "both, npm asked: composer ran"
run composer
eq "both, composer asked: managers" "$(jq -c '[.managers[].manager]' "$tmp/out.json")" '["composer"]'
echo "ok a repo with both managers"

# --- neither manager -------------------------------------------------------------------------
project neither
run
eq "neither: exit" "$rc" 1
eq "neither: managers" "$(jq -c . "$tmp/out.json")" '{"managers":[]}'
grep -q "not a Composer or npm project" "$tmp/stderr" || fail "neither: no clear message"
[ ! -s "$STUB_LOG" ] || fail "neither: a tool ran"
echo "ok a repo with neither manager exits 1"

# --- the requested manager's manifest is missing, and an unsupported manager ----------------
cd "$tmp/npm-only"
run composer
eq "missing manifest: exit" "$rc" 1
eq "missing manifest: managers" "$(jq -c . "$tmp/out.json")" '{"managers":[]}'
grep -q "composer.json is missing" "$tmp/stderr" || fail "missing manifest: no clear message"
run yarn
eq "unsupported manager: exit" "$rc" 2
grep -q "only Composer and npm are supported" "$tmp/stderr" || fail "unsupported manager: no clear message"
run composer npm
eq "two arguments: exit" "$rc" 2
echo "ok missing manifest exits 1, unsupported manager exits 2"

# --- missing lockfile: outdated still runs, the security audit does not --------------------
project no-lock composer.json package.json
run
eq "no lockfile: exit" "$rc" 0
eq "no lockfile: lockfiles" "$(jq -c '[.managers[].lockfile]' "$tmp/out.json")" '[null,null]'
eq "no lockfile: advisories" "$(jq -c '[.managers[].advisories]' "$tmp/out.json")" '[[],[]]'
eq "no lockfile: composer major" "$(names 0 major)" '["psr/log","twig/twig"]'
eq "no lockfile: npm major" "$(names 1 major)" '["chalk"]'
eq "no lockfile: calls" "$(cat "$STUB_LOG")" "composer outdated --direct --format=json --no-interaction --no-plugins --no-scripts
npm outdated --json"
echo "ok a missing lockfile skips the security audit"

# --- nothing outdated, no advisories ----------------------------------------------------------
stubs clean
echo '{"installed": []}' > "$STUB_DIR/composer-outdated.out"
echo '{"advisories": [], "abandoned": [], "filter": []}' > "$STUB_DIR/composer-audit.out"
echo 0 > "$STUB_DIR/composer-audit.rc"
echo '{}' > "$STUB_DIR/npm-outdated.out"
echo 0 > "$STUB_DIR/npm-outdated.rc"
echo '{"auditReportVersion": 2, "vulnerabilities": {}, "metadata": {}}' > "$STUB_DIR/npm-audit.out"
echo 0 > "$STUB_DIR/npm-audit.rc"
cd "$tmp/both"
run
eq "clean: exit" "$rc" 0
eq "clean: composer" "$(jq -c '.managers[0] | [.outdated, .advisories, .errors]' "$tmp/out.json")" \
  '[{"patch":[],"minor":[],"major":[]},[],[]]'
eq "clean: npm" "$(jq -c '.managers[1] | [.outdated, .advisories, .errors]' "$tmp/out.json")" \
  '[{"patch":[],"minor":[],"major":[]},[],[]]'
echo "ok a clean project"

# --- abandoned packages are carried as notes (shape assumed, not captured from a real run) -----
stubs abandoned
echo '{"installed": [{"name": "old/pkg", "version": "1.0.0", "latest": "1.0.0", "direct-dependency": true, "abandoned": "new/pkg"}, {"name": "gone/pkg", "version": "2.0.0", "latest": "2.0.0", "direct-dependency": true, "abandoned": true}]}' > "$STUB_DIR/composer-outdated.out"
echo '{"advisories": [], "abandoned": {"old/pkg": "new/pkg", "deep/pkg": null}, "filter": []}' > "$STUB_DIR/composer-audit.out"
echo 0 > "$STUB_DIR/composer-audit.rc"
cd "$tmp/both"
run composer
eq "abandoned: exit" "$rc" 0
eq "abandoned: notes" "$(jq -c '.managers[0].errors' "$tmp/out.json")" \
  '["abandoned package: deep/pkg","abandoned package: gone/pkg","abandoned package: old/pkg (replacement: new/pkg)"]'
echo "ok abandoned composer packages are named in errors, once each"

# --- a tool that fails goes in errors, not in the findings -------------------------------------
stubs broken
# What Composer 2.10.3 prints with no vendor directory: "[]" on stdout, exit 0.
echo '[]' > "$STUB_DIR/composer-outdated.out"
echo 'No dependencies installed. Try running composer install or update.' > "$STUB_DIR/composer-outdated.err"
: > "$STUB_DIR/composer-audit.out"
echo 'Valid composer.json and composer.lock files are required to run this command with --locked' > "$STUB_DIR/composer-audit.err"
# What npm 11.20.0 prints on stdout when a command fails.
echo '{"error": {"code": "E401", "summary": "Unable to authenticate", "detail": ""}}' > "$STUB_DIR/npm-outdated.out"
echo '{"error": {"code": "ENOLOCK", "summary": "This command requires an existing lockfile.", "detail": ""}}' > "$STUB_DIR/npm-audit.out"
run
eq "broken: exit" "$rc" 0
eq "broken: composer findings" "$(jq -c '.managers[0] | [.outdated, .advisories]' "$tmp/out.json")" \
  '[{"patch":[],"minor":[],"major":[]},[]]'
eq "broken: composer errors" "$(jq -c '.managers[0].errors' "$tmp/out.json")" \
  '["composer outdated printed no package list (exit 0): No dependencies installed. Try running composer install or update.","composer audit printed no report (exit 1): Valid composer.json and composer.lock files are required to run this command with --locked"]'
eq "broken: npm errors" "$(jq -c '.managers[1].errors' "$tmp/out.json")" \
  '["npm outdated printed no package list (exit 1): E401 Unable to authenticate","npm audit printed no report (exit 1): ENOLOCK This command requires an existing lockfile."]'
echo "ok tool failures are reported in errors"

# --- npm without node_modules, and a version that is not numeric ----------------------------------
stubs odd
# What npm 11.20.0 prints with no node_modules: no "current" key.
echo '{"chalk": {"wanted": "4.0.0", "latest": "6.0.1", "dependent": "x"}, "left-pad": {"current": "1.0.0", "wanted": "1.0.0", "latest": "1.3.0", "dependent": "x"}}' > "$STUB_DIR/npm-outdated.out"
jq '.installed += [{"name": "acme/dev", "direct-dependency": true, "version": "dev-main", "latest": "2.0.0"}]' \
  "$fixtures/composer-outdated.json" > "$STUB_DIR/composer-outdated.out"
run
eq "odd: npm null current" "$(jq -c '.managers[1].outdated.major' "$tmp/out.json")" \
  '[{"package":"chalk","current":null,"latest":"6.0.1","direct":true}]'
eq "odd: npm transitive" "$(jq -c '.managers[1].outdated.minor' "$tmp/out.json")" \
  '[{"package":"left-pad","current":"1.0.0","latest":"1.3.0","direct":false}]'
jq -e '.managers[1].errors | any(test("not installed"))' "$tmp/out.json" >/dev/null || fail "odd: no not-installed error"
eq "odd: composer non-numeric under major" "$(names 0 major)" '["psr/log","twig/twig","acme/dev"]'
jq -e '.managers[0].errors | any(test("cannot compare acme/dev"))' "$tmp/out.json" >/dev/null || fail "odd: no compare error"
echo "ok missing current and non-numeric versions"

# --- nothing but read-only subcommands ever ran ----------------------------------------------------
[ -s "$tmp/all-calls.log" ] || fail "no calls were logged"
grep -Ev '^(composer|npm) (outdated|audit) ' "$tmp/all-calls.log" && fail "a subcommand other than outdated or audit ran"
echo "ok only outdated and audit were called"
