#!/bin/bash
# Run a focused command, reusing successful evidence only for identical inputs.
# Usage: run-with-receipt.sh <receipt.json> <context.json> -- <command> [args...]
# Command output goes to stderr; the result is JSON on stdout. Needs Python 3/git.
set -e

if [ "$#" -lt 4 ] || [ "$3" != -- ]; then
  echo 'Usage: run-with-receipt.sh <receipt.json> <context.json> -- <command> [args...]' >&2
  exit 2
fi

python3 - "$@" <<'PY'
import hashlib
import json
import os
import subprocess
import sys
import tempfile

receipt_file, context_file = map(os.path.abspath, sys.argv[1:3])
command = sys.argv[4:]
if os.path.realpath(receipt_file) == os.path.realpath(context_file):
    print('Receipt and context must be different files', file=sys.stderr)
    sys.exit(2)


def read_json(filename):
    try:
        with open(filename) as stream:
            return json.load(stream)
    except (OSError, ValueError):
        return None


def git(*args):
    return subprocess.check_output(['git', *args], stderr=subprocess.DEVNULL).strip()


def snapshot():
    context = read_json(context_file)
    fields = ('runtime', 'dependencies', 'configuration', 'environment', 'fixtures')
    if not isinstance(context, dict) or context.get('reproducible') is not True:
        return None
    if any(not isinstance(context.get(key), str) or not context[key].strip() for key in fields):
        return None
    try:
        # Run only at the root: relative command paths must mean the same thing.
        root = os.fsdecode(git('rev-parse', '--show-toplevel'))
        if os.path.realpath(root) != os.path.realpath(os.getcwd()):
            return None
        # Claims intentionally stay uncommitted. Only exclude planning metadata
        # when the caller has verified the command never consumes it.
        scope = ['--', '.', ':(exclude).scratch'] if context.get('planning_metadata_unused') is True else []
        git('diff-files', '--quiet', '--ignore-submodules=none', *scope)
        if git('ls-files', '--others', '--exclude-standard', *scope):
            return None
        # Submodule working state is not represented by the superproject tree.
        index = git('ls-files', '--stage')
        if index.startswith(b'160000 ') or b'\n160000 ' in index:
            return None
        tree = git('write-tree').decode()
        if scope:
            entries = git('ls-tree', '-z', tree).split(b'\0')
            entries = [entry for entry in entries if entry and entry.split(b'\t', 1)[1] != b'.scratch']
            tree = subprocess.check_output(
                ['git', 'mktree', '-z'], input=b''.join(entry + b'\0' for entry in entries),
                stderr=subprocess.DEVNULL).strip().decode()
        common = os.path.realpath(os.fsdecode(git('rev-parse', '--git-common-dir')))
    except (OSError, subprocess.CalledProcessError):
        return None
    encoded = json.dumps(context, sort_keys=True, separators=(',', ':')).encode()
    return {'repository': common, 'tree': tree, 'command': command,
            'context': hashlib.sha256(encoded).hexdigest()}


before = snapshot()
previous = read_json(receipt_file)
if before is not None and isinstance(previous, dict) and previous == {
    'version': 1, 'status': 'passed', 'inputs': before
}:
    print(json.dumps({'status': 'reused', 'receipt': receipt_file, 'tree': before['tree']}))
    sys.exit(0)

# A miss invalidates earlier evidence even if the next execution fails or is killed.
try:
    os.unlink(receipt_file)
except FileNotFoundError:
    pass

try:
    result = subprocess.run(command, stdout=sys.stderr, stderr=sys.stderr)
    code = result.returncode if result.returncode >= 0 else 128 - result.returncode
except OSError as error:
    print(str(error), file=sys.stderr)
    code = 127

after = snapshot() if code == 0 else None
cached = before is not None and before == after
if code == 0 and cached:
    os.makedirs(os.path.dirname(receipt_file), exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(dir=os.path.dirname(receipt_file))
    try:
        with os.fdopen(descriptor, 'w') as stream:
            json.dump({'version': 1, 'status': 'passed', 'inputs': after}, stream)
            stream.write('\n')
        os.replace(temporary, receipt_file)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)

print(json.dumps({'status': 'passed' if code == 0 else 'failed', 'exit_code': code,
                  'cached': code == 0 and cached,
                  'tree': before['tree'] if before else None, 'receipt': receipt_file}))
sys.exit(code)
PY
