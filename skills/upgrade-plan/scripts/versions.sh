#!/bin/bash
# Resolve one package's installed, constraint, and latest versions, the stable releases
# in between, and what the target release requires. Run from the project root.
# Usage: versions.sh <package> [target-version]
# Stdout: one JSON object. Stderr: status. Supports Composer and npm-style projects.
set -e

pkg="${1:?usage: versions.sh <package> [target-version]}"
target="${2:-}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Strip a leading v and any composer 4th segment, so sort -V and comparisons agree.
norm() { sed -E 's/^v//; s/^([0-9]+\.[0-9]+\.[0-9]+)\.0$/\1/'; }
stable() { grep -E '^v?[0-9]+(\.[0-9]+)*$' || true; }
# Versions strictly above $1 and at most $2, ascending.
between() {
  local lo hi
  lo=$(printf '%s' "$1" | norm); hi=$(printf '%s' "$2" | norm)
  norm | sort -uV | awk -v lo="$lo" -v hi="$hi" '
    function cmp(a, b,   x, y, i, n) {
      n = split(a, x, "."); split(b, y, ".")
      for (i = 1; i <= (n > length(y) ? n : length(y)); i++) {
        if (x[i] + 0 < y[i] + 0) return -1
        if (x[i] + 0 > y[i] + 0) return 1
      }
      return 0
    }
    cmp($0, lo) > 0 && cmp($0, hi) <= 0'
}

ecosystem=""
if [[ "$pkg" != @* && "$pkg" == */* && -f composer.lock ]] &&
   jq -e --arg p "$pkg" '[.packages[], (."packages-dev" // [])[]] | any(.name == $p)' composer.lock >/dev/null; then
  ecosystem=composer
elif [[ -f package.json ]] && { [[ -f "node_modules/$pkg/package.json" ]] ||
   jq -e --arg p "$pkg" '[.dependencies, .devDependencies, .peerDependencies] | map(. // {} | has($p)) | any' package.json >/dev/null; }; then
  ecosystem=npm
fi
if [[ -z "$ecosystem" ]]; then
  echo "versions.sh: $pkg is not in composer.lock, package.json, or node_modules" >&2
  jq -n --arg p "$pkg" '{package: $p, error: "not installed in this project"}'
  exit 0
fi
echo "versions.sh: $pkg ($ecosystem)" >&2

if [[ "$ecosystem" == composer ]]; then
  installed=$(jq -r --arg p "$pkg" '[.packages[], (."packages-dev" // [])[]] | map(select(.name == $p))[0].version' composer.lock)
  constraint=$(jq -r --arg p "$pkg" '(.require[$p] // ."require-dev"[$p]) // empty' composer.json)
  # p2 metadata is minified: each entry lists only what changed from the one before.
  if curl -sfL "https://repo.packagist.org/p2/$pkg.json" -o "$tmp/meta.json"; then
    jq --arg p "$pkg" '.packages[$p] | reduce .[] as $e ([];
        . + [((.[-1] // {}) + $e) | with_entries(select(.value != "__unset"))])' "$tmp/meta.json" > "$tmp/all.json"
    latest=$(jq -r '.[].version' "$tmp/all.json" | stable | norm | sort -V | tail -1)
    [[ -n "$target" ]] || target="$latest"
    jq -r '.[].version' "$tmp/all.json" | stable | between "$installed" "$target" > "$tmp/between"
    jq --arg t "$target" 'map(select((.version | ltrimstr("v")) == ($t | ltrimstr("v"))))[0] // {}' "$tmp/all.json" > "$tmp/target.json"
    repo=$(jq -r '.source.url // .support.source // empty' "$tmp/target.json")
    requires=$(jq '.require // {}' "$tmp/target.json")
  else
    echo "versions.sh: not on packagist; latest and requires unknown" >&2
    latest=""; repo=""; requires='{}'; : > "$tmp/between"
  fi
  # What this project has installed for each package the target requires.
  have=$(jq --argjson r "$requires" '[.packages[], (."packages-dev" // [])[]]
    | map(select(.name as $n | $r | has($n))) | map({(.name): .version}) | add // {}' composer.lock)
  have=$(jq -n --argjson h "$have" --arg php "$(php -r 'echo PHP_VERSION;' 2>/dev/null)" \
    --arg cphp "$(jq -r '.require.php // empty' composer.json)" \
    '$h + {php: ("runtime " + $php + ", composer.json " + $cphp)}')
  peers='{}'
  dependents=$(jq --arg p "$pkg" '[.packages[], (."packages-dev" // [])[]]
    | map(select(.require[$p]) | {(.name): ("requires " + .require[$p] + " (at " + .version + ")")}) | add // {}' composer.lock)
else
  installed=$(jq -r '.version // empty' "node_modules/$pkg/package.json" 2>/dev/null || true)
  [[ -n "$installed" || ! -f package-lock.json ]] ||
    installed=$(jq -r --arg p "node_modules/$pkg" '.packages[$p].version // empty' package-lock.json 2>/dev/null || true)
  [[ -n "$installed" ]] || echo "versions.sh: no installed version found (node_modules missing, lockfile unreadable?)" >&2
  constraint=$(jq -r --arg p "$pkg" '(.dependencies[$p] // .devDependencies[$p] // .peerDependencies[$p]) // empty' package.json)
  enc="${pkg/\//%2F}"
  curl -sfL -H 'Accept: application/vnd.npm.install-v1+json' "https://registry.npmjs.org/$enc" -o "$tmp/meta.json"
  latest=$(jq -r '."dist-tags".latest' "$tmp/meta.json")
  [[ -n "$target" ]] || target="$latest"
  jq -r '.versions | keys[]' "$tmp/meta.json" | stable | between "$installed" "$target" > "$tmp/between"
  repo=$(curl -sfL "https://registry.npmjs.org/$pkg/$target" | jq -r '.repository.url // .repository // empty' || true)
  requires=$(jq --arg t "$target" '.versions[$t] | (.dependencies // {}) + {engines: (.engines // {})}' "$tmp/meta.json")
  peers=$(jq --arg t "$target" '.versions[$t].peerDependencies // {}' "$tmp/meta.json")
  have='{}'
  for dep in $(jq -n -r --argjson a "$requires" --argjson b "$peers" '($a + $b) | del(.engines) | keys[]'); do
    v=$(jq -r '.version // empty' "node_modules/$dep/package.json" 2>/dev/null || true)
    have=$(jq -n --argjson h "$have" --arg d "$dep" --arg v "${v:-not installed}" '$h + {($d): $v}')
  done
  # Top-level installed packages that depend on or peer this one.
  dependents=$(cat node_modules/*/package.json node_modules/@*/*/package.json 2>/dev/null | jq -s --arg p "$pkg" '
    map(select(.name != $p) | . as $m | (.peerDependencies[$p] // .dependencies[$p]) as $c | select($c)
        | {($m.name): ((if $m.peerDependencies[$p] then "peers " else "requires " end) + $c + " (at " + $m.version + ")")})
    | add // {}')
  have=$(jq -n --argjson h "$have" --arg node "$(node -v 2>/dev/null)" \
    --arg cnode "$(jq -r '.engines.node // empty' package.json)" \
    '$h + {node: ("runtime " + $node + ", package.json engines " + $cnode)}')
fi

jq -n --arg eco "$ecosystem" --arg p "$pkg" --arg c "$constraint" --arg i "$installed" \
  --arg l "$latest" --arg t "$target" --arg repo "$repo" \
  --argjson req "$requires" --argjson peer "$peers" --argjson have "$have" --argjson dep "$dependents" \
  --rawfile btw "$tmp/between" '{
    ecosystem: $eco, package: $p, direct: ($c != ""), constraint: $c,
    installed: $i, latest: $l, target: $t, repository: $repo,
    releases_crossed: ($btw | split("\n") | map(select(. != ""))),
    target_requires: $req, target_peer_requires: $peer, installed_for_requires: $have,
    dependents: $dep
  }'
