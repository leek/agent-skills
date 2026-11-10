#!/bin/bash
# Offline test for the root canonicalisation in autopilot.sh (lib/state.sh): every spelling
# of one tracker root must give one ROOT_REF, one STATE_KEY, and one LOCK_DIR. Runs
# autopilot.sh in a throwaway repository under mktemp -d with a stub provider binary
# (AUTOPILOT_CLAUDE_BIN) that records any call; the fixture trackers hold no tickets, so
# every run stops at "blocked" before a worker starts. No tmux, no network.
# Prints one `ok <case>` line per case; exits non-zero on the first failed assertion.
# shellcheck disable=SC2034 # globals the sourced libraries read
set -e
set -o pipefail

here="$(cd "$(dirname "$0")" && pwd)"
autopilot_sh="$here/autopilot.sh"
command -v jq >/dev/null 2>&1 || { echo "test-root-key.sh: jq is required" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "test-root-key.sh: git is required" >&2; exit 2; }

t="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$t"' EXIT

fail() {
  echo "FAIL $1" >&2
  exit 1
}

eq() {
  [ "$2" = "$3" ] || fail "$1: got '$2', want '$3'"
}

mkdir -p "$t/bin" "$t/home/.claude"
printf '#!/bin/bash\necho called >>"%s/provider-called"\nexit 1\n' "$t" >"$t/bin/claude-stub"
chmod +x "$t/bin/claude-stub"

r="$t/repo"
mkdir -p "$r/.scratch/foo/tickets" "$r/sub/deep"
git init -q "$r"
printf -- '---\nstatus: ready-for-agent\n---\n\n# Spec\n' >"$r/.scratch/foo/spec.md"
ln -s "$r/.scratch/foo" "$t/abs-dir-link"
ln -s .scratch/foo "$r/dir-link"
ln -s .scratch/foo/spec.md "$r/spec-link.md"
ln -s "$r/spec-link.md" "$t/spec-chain-link.md"
ln -s "$r" "$t/repo-link"

# ap <cwd> <autopilot arguments>: stdout is the script's JSON; stderr is dropped.
ap() {
  local cwd="$1"
  shift
  (
    cd "$cwd"
    env -u AUTOPILOT_MODEL -u AUTOPILOT_EFFORT -u AUTOPILOT_TMUX_CHILD -u AUTOPILOT_TMUX_ENV_FILE \
      HOME="$t/home" CLAUDE_CONFIG_DIR="$t/home/.claude" AUTOPILOT_CLAUDE_BIN="$t/bin/claude-stub" \
      bash "$autopilot_sh" "$@" 2>/dev/null
  )
}

# run_id <cwd> <status arguments>: the run a spelling resolves to, "none" when it finds no run.
run_id() {
  local out
  out="$(ap "$@" --status)" || true
  printf '%s' "$out" | jq -r 'if .status == "none" then "none" else .run_id end'
}

root_ref() {
  local out
  out="$(ap "$@" --status)" || true
  printf '%s' "$out" | jq -r '.root_ref // .root'
}

dir_root="$r/.scratch/foo"
file_root="$r/.scratch/foo/spec.md"

status=0
out="$(ap "$r" --provider claude --root .scratch/foo)" || status=$?
eq "directory run exit" "$status" 3
eq "directory run status" "$(printf '%s' "$out" | jq -r '.status')" "blocked"
dir_run="$(run_id "$r" --root .scratch/foo)"
[ "$dir_run" != "none" ] || fail "the directory run left no state"

status=0
out="$(ap "$r" --provider claude --root .scratch/foo/spec.md)" || status=$?
eq "file run exit" "$status" 3
file_run="$(run_id "$r" --root .scratch/foo/spec.md)"
[ "$file_run" != "none" ] || fail "the file run left no state"
[ "$file_run" != "$dir_run" ] || fail "the spec file and its directory share one run"
echo "ok a directory root and a file root are separate trackers"

# check <case> <want run> <want root> <cwd> <arguments>
check() {
  local label="$1" want_run="$2" want_root="$3"
  shift 3
  eq "$label root_ref" "$(root_ref "$@")" "$want_root"
  eq "$label run" "$(run_id "$@")" "$want_run"
}

check "trailing slash" "$dir_run" "$dir_root" "$r" --root .scratch/foo/
check "trailing slashes" "$dir_run" "$dir_root" "$r" --root .scratch/foo///
check "absolute" "$dir_run" "$dir_root" "$r" --root "$dir_root"
check "absolute, trailing slash" "$dir_run" "$dir_root" "$t" --repo "$r" --root "$dir_root/"
echo "ok trailing slash and absolute spellings give one key"

check "./ prefix" "$dir_run" "$dir_root" "$r" --root ./.scratch/foo
check "inner ./ and //" "$dir_run" "$dir_root" "$r" --root .scratch/.//foo/.
check ".. inside" "$dir_run" "$dir_root" "$r" --root sub/../.scratch/foo/tickets/..
check "file ./ prefix" "$file_run" "$file_root" "$r" --root ./.scratch/foo/spec.md
check "file inner ./" "$file_run" "$file_root" "$r" --root .scratch/./foo//spec.md
echo "ok ./ prefixes give one key"

check "subdirectory, ../" "$dir_run" "$dir_root" "$r/sub" --root ../.scratch/foo
check "subdirectory, repository-relative" "$dir_run" "$dir_root" "$r/sub/deep" --root .scratch/foo
check "--repo subdirectory" "$dir_run" "$dir_root" "$t" --repo "$r/sub" --root .scratch/foo
check "--repo through a symlink" "$dir_run" "$dir_root" "$t" --repo "$t/repo-link" --root .scratch/foo
check "file from a subdirectory" "$file_run" "$file_root" "$r/sub" --root ../.scratch/foo/spec.md
check "file, repository-relative from a subdirectory" "$file_run" "$file_root" "$r/sub" --root .scratch/foo/spec.md
echo "ok a relative root from a subdirectory gives one key"

check "symlinked directory, absolute" "$dir_run" "$dir_root" "$r" --root "$t/abs-dir-link"
check "symlinked directory, relative" "$dir_run" "$dir_root" "$r" --root dir-link/
check "file under a symlinked directory" "$file_run" "$file_root" "$r" --root dir-link/spec.md
echo "ok a symlinked directory gives one key"

check "symlink to the file" "$file_run" "$file_root" "$r" --root spec-link.md
check "symlink chain to the file" "$file_run" "$file_root" "$t" --repo "$r" --root "$t/spec-chain-link.md"
echo "ok a symlink to the spec file gives the file's key"

# One LOCK_DIR: a lock taken under the canonical key refuses every spelling.
state_file="$(grep -l "\"run_id\":\"$dir_run\"" "$r"/.git/autopilot/*.json)"
lock_dir="${state_file%.json}.lock"
mkdir "$lock_dir"
printf '%s\n' "$$" >"$lock_dir/pid"
refused() {
  local label="$1" status=0 out
  shift
  out="$(ap "$@")" || status=$?
  eq "$label exit" "$status" 5
  case "$(printf '%s' "$out" | jq -r '.reason')" in
    *"another Autopilot process is active"*) ;;
    *) fail "$label: not refused by the lock: $out" ;;
  esac
}
refused "lock, plain" "$r" --provider claude --root .scratch/foo
refused "lock, trailing slash" "$r" --provider claude --root ./.scratch/foo/
refused "lock, subdirectory" "$r/sub" --provider claude --root .scratch/foo
refused "lock, symlinked directory" "$r" --provider claude --root "$t/abs-dir-link"
rm -f "$lock_dir/pid"
rmdir "$lock_dir"

file_state="$(grep -l "\"run_id\":\"$file_run\"" "$r"/.git/autopilot/*.json)"
file_lock="${file_state%.json}.lock"
[ "$file_lock" != "$lock_dir" ] || fail "the file root and the directory root share one lock"
mkdir "$file_lock"
printf '%s\n' "$$" >"$file_lock/pid"
refused "lock, symlink to the file" "$r" --provider claude --root spec-link.md
refused "lock, file from a subdirectory" "$r/sub" --provider claude --root ../.scratch/foo/spec.md
rm -f "$file_lock/pid"
rmdir "$file_lock"
echo "ok every spelling meets the same lock"

# The key itself, from the functions autopilot.sh calls.
keys="$(
  # shellcheck source=lib/state.sh
  source "$here/lib/state.sh"
  REPO_ROOT="$r"
  GIT_DIR="$r/.git"
  key_for() {
    ORIGINAL_DIR="$1"
    ROOT_REF="$(canonical_root_ref "$2")"
    resolve_state_paths
    printf '%s %s\n' "$STATE_KEY" "$LOCK_DIR"
  }
  key_for "$r" .scratch/foo
  key_for "$r" ./.scratch/foo/
  key_for "$r/sub" ../.scratch/foo
  key_for "$r/sub/deep" .scratch/foo
  key_for "$r" dir-link
  key_for "$r" "$t/abs-dir-link/"
)"
eq "distinct STATE_KEY and LOCK_DIR pairs" "$(printf '%s\n' "$keys" | sort -u | wc -l | tr -d ' ')" 1
eq "LOCK_DIR" "$(printf '%s\n' "$keys" | sed -n '1p' | cut -d' ' -f2)" "$lock_dir"
echo "ok one STATE_KEY and one LOCK_DIR per tracker"

# A root that does not exist still has one spelling, and reports as missing.
missing="$r/.scratch/gone"
eq "missing root" "$(root_ref "$r" --root .scratch/gone)" "$missing"
eq "missing root, ./ and slash" "$(root_ref "$r" --root ./.scratch/gone/)" "$missing"
eq "missing root, absolute" "$(root_ref "$t" --repo "$r" --root "$missing")" "$missing"
status=0
out="$(ap "$r" --provider claude --root .scratch/gone)" || status=$?
eq "missing root exit" "$status" 3
case "$(printf '%s' "$out" | jq -r '.reason')" in
  "root reference does not exist: $missing") ;;
  *) fail "missing root reason: $out" ;;
esac
echo "ok a missing root has one spelling and blocks the run"

[ ! -e "$t/provider-called" ] || fail "the provider stub was called"
echo "ok no worker was started"
