#!/bin/bash
# Start a browser-test run: create the run directory, write the guard's scope.json,
# and report whether a saved auth state exists for the URL's host.
# Usage: start-run.sh <start-url>   (run from the project root)
# Stdout: {"run_id", "run_dir", "origin", "state", "state_exists"}
set -e

url="${1:?usage: start-run.sh <start-url>}"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

run_id="$(date -u +%Y%m%d-%H%M%S)"
run_dir="$(pwd)/.scratch/browser-test/$run_id"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/browser-test"
mkdir -p "$state_dir"

python3 - "$url" "$run_id" "$run_dir" "$state_dir" >"$tmp" <<'PY'
import json, os, re, sys
from urllib.parse import urlsplit
url, run_id, run_dir, state_dir = sys.argv[1:]
u = urlsplit(url)
if u.scheme not in ("http", "https") or not u.netloc:
    sys.exit(f"not an http(s) URL: {url}")
state = os.path.join(state_dir, re.sub(r"[^A-Za-z0-9.-]", "_", u.netloc) + ".json")
os.makedirs(run_dir)
scope = {"origin": f"{u.scheme}://{u.netloc}", "state": state}
json.dump(scope, open(os.path.join(run_dir, "scope.json"), "w"))
print(json.dumps({"run_id": run_id, "run_dir": run_dir, **scope,
                  "state_exists": os.path.isfile(state)}))
PY

echo "browser-test run $run_id started in $run_dir" >&2
cat "$tmp"
