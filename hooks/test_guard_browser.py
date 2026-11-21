import json
import shlex
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HOOKS_DIR = Path(__file__).resolve().parent
if str(HOOKS_DIR) not in sys.path:
    sys.path.insert(0, str(HOOKS_DIR))

from browser_guard import PROBE  # noqa: E402

DISPATCHER = HOOKS_DIR / "pre_tool_guard.py"
RUN = "20260927-120000"
S = f"agent-browser --session bt-{RUN}-1"


class GuardBrowserTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.cwd = Path(self.tmp.name)
        self.run_dir = self.cwd / ".scratch" / "browser-test" / RUN
        self.run_dir.mkdir(parents=True)
        self.state = str(self.cwd / "auth.json")
        (self.run_dir / "scope.json").write_text(
            json.dumps({"origin": "https://app.test", "state": self.state}))

    def tearDown(self):
        self.tmp.cleanup()

    def guard(self, command, agent="leek-skills:browser-tester"):
        payload = {"tool_name": "Bash", "tool_input": {"command": command}, "cwd": str(self.cwd)}
        if agent:
            payload["agent_type"] = agent
        return subprocess.run([sys.executable, str(DISPATCHER)], input=json.dumps(payload),
                              text=True, capture_output=True)

    def assertAllowed(self, command, **kw):
        result = self.guard(command, **kw)
        self.assertEqual(result.returncode, 0, result.stderr)

    def assertBlocked(self, command, reason, **kw):
        result = self.guard(command, **kw)
        self.assertEqual(result.returncode, 2, f"not blocked: {command}")
        self.assertIn(reason, result.stderr)

    def test_ignores_other_agents_and_the_main_session(self):
        self.assertAllowed("rm -rf /", agent=None)
        self.assertAllowed("rm -rf /", agent="leek-skills:browser-writer")

    def test_guards_the_planner_and_project_local_copies(self):
        self.assertBlocked("rm -rf x", "not allowed", agent="leek-skills:browser-test-planner")
        self.assertBlocked("rm -rf x", "not allowed", agent="browser-tester")

    def test_allows_the_read_only_loop(self):
        for cmd in [
            f"{S} --state {self.state} open https://app.test/dashboard",
            f"{S} snapshot -i",
            f"{S} console --clear && {S} errors --clear && {S} network requests --clear && {S} click @e3 && {S} wait --load networkidle",
            f"{S} errors; {S} console; {S} network requests --type xhr,fetch,document",
            f"{S} eval {shlex.quote(PROBE)}",
            f"{S} wait '#spinner' --state hidden",
            f"{S} press Escape",
            f"{S} find role searchbox fill 'acme'",
            f"{S} find placeholder 'Search users' type acme",
            f"{S} find text Settings click",
            f"{S} screenshot {self.run_dir}/1-dashboard.png",
            f"{S} get url | head -1 2>/dev/null",
            f"{S} close",
        ]:
            with self.subTest(cmd=cmd):
                self.assertAllowed(cmd)

    def test_blocks_writes_and_escape_hatches(self):
        for cmd, reason in [
            (f"{S} fill @e4 hello", "not an allowed verb"),
            (f"{S} type @e4 hello", "not an allowed verb"),
            (f"{S} find label Email fill x@y.z", "only allowed into a search box"),
            (f"{S} find text Delete dblclick", "not a read-only action"),
            (f"{S} press Enter", "only navigation keys"),
            (f"{S} select @e2 admin", "not an allowed verb"),
            (f"{S} check @e2", "not an allowed verb"),
            (f"{S} upload @e2 /etc/passwd", "not an allowed verb"),
            (f"{S} eval 'document.forms[0].submit()'", "exact probe"),
            (f"{S} wait --fn 'fetch(\"/delete\")'", "flag `--fn`"),
            (f"{S} wait --download /tmp/x", "flag `--download`"),
            (f"{S} open https://evil.test/", "only allowed on https://app.test"),
            (f"{S} open http://app.test/", "only allowed on https://app.test"),
            (f"{S} --state /tmp/other.json open https://app.test/", "exact auth file"),
            (f"{S} --profile Default open https://app.test/", "`--profile` is not an allowed verb"),
            (f"{S} open https://app.test/ --auto-connect", "flag `--auto-connect`"),
            (f"{S} network route '*'", "only `network requests`"),
            (f"{S} tab new https://evil.test", "`tab` allows only"),
            (f"{S} state save /tmp/x.json", "not an allowed verb"),
            (f"{S} cookies set a b", "not an allowed verb"),
            (f"{S} screenshot /Users/leek/.zshrc", "must be saved under"),
            (f"{S} screenshot {self.run_dir}/../../../x.png", "must be saved under"),
            (f"{S} close --all", "flag `--all`"),
            ("agent-browser --session dsc-x snapshot", "must start with `--session bt-"),
            ("agent-browser --session bt-20260101-000000-1 snapshot", "no scope.json"),
            (f"{S} snapshot > out.txt", "redirects are not allowed"),
            (f"{S} snapshot $(rm x)", "command substitution"),
            (f"{S} snapshot =(rm x)", "command substitution"),
            (f"{S} snapshot\nrm x", "multi-line"),
            (f"{S} snapshot\rrm x", "multi-line"),
            (f"{S} snapshot *(e:'rm x':)", "subshells and glob qualifiers"),
            (f"{S} snapshot | tee out.txt", "`tee` is not allowed"),
            (f"{S} snapshot | sort -o out.txt", "write files"),
            (f"{S} snapshot | uniq - out.txt", "writes a file"),
        ]:
            with self.subTest(cmd=cmd):
                self.assertBlocked(cmd, reason)

    def test_a_crashing_browser_guard_blocks(self):
        payload = {"tool_name": "Bash", "tool_input": {"command": 5},
                   "agent_type": "leek-skills:browser-tester"}
        result = subprocess.run([sys.executable, str(DISPATCHER)], input=json.dumps(payload),
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("guard failed", result.stderr)

    def test_find_flag_stripping_and_nth_form(self):
        for cmd in [
            f"{S} find --json text Settings click",
            f"{S} find text Settings click --json",
            f"{S} find nth 0 '.item' click",
            f"{S} find nth 0 text text",
            f"{S} find role button click --name Submit",
            f"{S} find --exact text Settings click",
            f"{S} find role searchbox fill acme --name Search",
        ]:
            with self.subTest(cmd=cmd):
                self.assertAllowed(cmd)
        for cmd, reason in [
            (f"{S} find --json text text fill pwned", "only allowed into a search box"),
            (f"{S} find --json text click fill pwned", "only allowed into a search box"),
            (f"{S} find --timeout 5000 role searchbox fill acme", "flag `--timeout`"),
            (f"{S} find --timeout 5000 label Email fill pwned", "flag `--timeout`"),
            # find has no --timeout: read as a value flag this looked like a hover but ran a fill.
            (f"{S} find --timeout label Password fill hover", "flag `--timeout`"),
            (f"{S} find -s x text Settings click", "flag `-s`"),
            (f"{S} find --name", "needs a value"),
            (f"{S} find nth 0 text fill pwned", "only allowed into a search box"),
            (f"{S} find nth 0 focus dblclick", "not a read-only action"),
            (f"{S} find nth abc '.item' click", "`find nth` needs"),
            (f"{S} find text Settings click extra", "takes no extra arguments"),
            (f"{S} find role searchbox fill acme extra", "needs exactly one text argument"),
            (f"{S} find role searchbox fill", "needs exactly one text argument"),
            (f"{S} find --unknown text Settings click", "flag `--unknown`"),
        ]:
            with self.subTest(cmd=cmd):
                self.assertBlocked(cmd, reason)

    def test_screenshot_relative_paths_and_short_flags(self):
        # Relative paths resolve against payload cwd, not the hook process's os.getcwd().
        self.assertAllowed(f"{S} screenshot .scratch/browser-test/{RUN}/1-rel.png")
        self.assertAllowed(f"{S} screenshot --full {self.run_dir}/1-full.png")
        self.assertAllowed(f"{S} screenshot '#main' {self.run_dir}/1-sel.png")
        self.assertBlocked(f"{S} screenshot -s '#main' {self.run_dir}/1-sel.png", "flag `-s`")
        self.assertBlocked(f"{S} screenshot --selector='#main' {self.run_dir}/1-sel2.png", "flag `--selector")
        self.assertBlocked(f"{S} screenshot -i -c -d 2 {self.run_dir}/1-flags.png", "flag `-i`")
        self.assertBlocked(f"{S} screenshot 1-outside.png", "must be saved under")
        self.assertBlocked(f"{S} screenshot ~/1-home.png", "must be saved under")
        self.assertBlocked(f"{S} screenshot '#main' /tmp/evil.png", "must be saved under")
        self.assertBlocked(f"{S} screenshot -x {self.run_dir}/1.png", "flag `-x`")
        self.assertBlocked(f"{S} screenshot --bad {self.run_dir}/1.png", "flag `--bad`")
        self.assertBlocked(f"{S} screenshot --threshold", "needs a value")

    def test_screenshot_path_cannot_hide_behind_a_value_flag(self):
        # `screenshot` takes only its own flags; any other (--timeout, -s) is refused outright.
        for cmd in [
            f"{S} screenshot --timeout /tmp/evil.png",
            f"{S} screenshot -s /tmp/evil.png",
            f"{S} screenshot /tmp/evil.png --timeout {self.run_dir}/x.png",
        ]:
            with self.subTest(cmd=cmd):
                self.assertBlocked(cmd, "is not allowed")
        for cmd in [
            f"{S} screenshot --screenshot-dir /tmp",
            f"{S} screenshot --screenshot-dir=/tmp {self.run_dir}/1.png",
            f"{S} screenshot --annotate '#main'",
        ]:
            with self.subTest(cmd=cmd):
                self.assertBlocked(cmd, "must be saved under")
        for cmd in [
            f"{S} screenshot -f --if-changed --threshold 0.01 {self.run_dir}/1.png",
            f"{S} screenshot --annotate --json '#main' {self.run_dir}/1.png",
            f"{S} screenshot --screenshot-format jpeg --screenshot-quality 80 {self.run_dir}/1.jpg",
            f"{S} screenshot --screenshot-dir {self.run_dir}",
            f"{S} screenshot --screenshot-dir={self.run_dir}/shots",
            f"{S} screenshot",
        ]:
            with self.subTest(cmd=cmd):
                self.assertAllowed(cmd)
        # Usage is `screenshot [selector] [path]`: the path slot is held to the run dir whatever
        # it looks like, and a third positional is refused.
        self.assertBlocked(f"{S} screenshot '#el' /tmp/x.png", "must be saved under")
        self.assertBlocked(f"{S} screenshot '#el' /tmp/notes", "must be saved under")
        self.assertAllowed(f"{S} screenshot '#el' {self.run_dir}/x.png")
        self.assertAllowed(f"{S} screenshot {self.run_dir}/x.png")
        for cmd in [f"{S} screenshot a b {self.run_dir}/x.png",
                    f"{S} screenshot '#el' {self.run_dir}/x.png extra"]:
            with self.subTest(cmd=cmd):
                self.assertBlocked(cmd, "at most a selector and a path")
        # Screenshot's own flags are not legal on other verbs.
        self.assertBlocked(f"{S} snapshot -f", "flag `-f`")
        self.assertBlocked(f"{S} snapshot --screenshot-dir /tmp", "flag `--screenshot-dir`")

    def test_scope_is_validated_per_segment(self):
        run2 = "20260927-130000"
        run_dir2 = self.cwd / ".scratch" / "browser-test" / run2
        run_dir2.mkdir(parents=True)
        state2 = str(self.cwd / "auth2.json")
        (run_dir2 / "scope.json").write_text(
            json.dumps({"origin": "https://other.test", "state": state2}))
        s2 = f"agent-browser --session bt-{run2}-1"
        s_missing = "agent-browser --session bt-20260101-000000-1"

        self.assertAllowed(f"{S} snapshot -i && {s2} open https://other.test/page")
        self.assertBlocked(f"{S} snapshot -i && {s_missing} open https://app.test/", "no scope.json")
        self.assertBlocked(f"{S} snapshot -i && {s2} open https://app.test/",
                           "only allowed on https://other.test")
        self.assertBlocked(f"{S} snapshot -i && {s2} screenshot {self.run_dir}/1.png",
                           "must be saved under")
        self.assertBlocked(f"{S} snapshot -i && {s2} --state {self.state} open https://other.test/",
                           "exact auth file")

    def test_agent_files_carry_the_exact_probe(self):
        agents = HOOKS_DIR.parent / "agents"
        for name in ["browser-tester.md", "browser-writer.md"]:
            with self.subTest(agent=name):
                self.assertIn(f'eval "{PROBE}"', (agents / name).read_text())


if __name__ == "__main__":
    unittest.main()
