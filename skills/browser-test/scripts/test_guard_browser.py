import json
import runpy
import shlex
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

GUARD = Path(__file__).with_name("guard-browser.py")
PROBE = runpy.run_path(str(GUARD))["PROBE"]
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
        return subprocess.run([sys.executable, str(GUARD)], input=json.dumps(payload),
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
            (f"agent-browser --session bt-20260101-000000-1 snapshot", "no scope.json"),
            (f"{S} snapshot > out.txt", "redirects are not allowed"),
            (f"{S} snapshot $(rm x)", "command substitution"),
            (f"{S} snapshot\nrm x", "multi-line"),
            (f"{S} snapshot | tee out.txt", "`tee` is not allowed"),
        ]:
            with self.subTest(cmd=cmd):
                self.assertBlocked(cmd, reason)

    def test_agent_files_carry_the_exact_probe(self):
        agents = Path(__file__).resolve().parents[3] / "agents"
        for name in ["browser-tester.md", "browser-writer.md"]:
            with self.subTest(agent=name):
                self.assertIn(f'eval "{PROBE}"', (agents / name).read_text())


if __name__ == "__main__":
    unittest.main()
