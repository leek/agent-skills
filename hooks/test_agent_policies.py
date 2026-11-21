import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HOOKS_DIR = Path(__file__).resolve().parent
DISPATCHER = HOOKS_DIR / "pre_tool_guard.py"
ROOT = HOOKS_DIR.parent
EXTRACT = ROOT / "skills" / "retro" / "scripts" / "extract-signal.sh"
AUDIT = ROOT / "skills" / "dependency-audit" / "scripts" / "audit.sh"
TMP = os.path.realpath(tempfile.gettempdir())


class AgentPoliciesTest(unittest.TestCase):
    # A project outside the temp directory, as a real one is; the guard only resolves paths.
    cwd = "/nonexistent-project"

    def guard(self, command, agent):
        payload = {"tool_name": "Bash", "tool_input": {"command": command},
                   "agent_type": f"leek-skills:{agent}", "cwd": self.cwd}
        return subprocess.run([sys.executable, str(DISPATCHER)], input=json.dumps(payload),
                              text=True, capture_output=True)

    def assertAllowed(self, command, agent):
        result = self.guard(command, agent)
        self.assertEqual(result.returncode, 0, f"{command}: {result.stderr}")

    def assertBlocked(self, command, reason, agent):
        result = self.guard(command, agent)
        self.assertEqual(result.returncode, 2, f"not blocked: {command}")
        self.assertIn(reason, result.stderr)

    def test_session_miner_runs_only_the_plugin_extract_script(self):
        a = "session-miner"
        self.assertAllowed(f"bash {EXTRACT} /logs/s.jsonl", a)
        self.assertAllowed(f"bash {EXTRACT} /logs/s.jsonl | head -50", a)
        self.assertAllowed("jq -rc .type /logs/s.jsonl | sort | uniq -c", a)
        self.assertAllowed("rg -n 'no, ' /logs/s.jsonl", a)
        # A look-alike in the memory directory it may write is not the plugin's script.
        fake = os.path.join(self.cwd, "skills", "retro", "scripts", "extract-signal.sh")
        self.assertBlocked(f"bash {fake} x.jsonl", "runs only this plugin's", a)
        self.assertBlocked("bash extract-signal.sh x.jsonl", "runs only this plugin's", a)
        self.assertBlocked(f"bash -c 'echo x > f' {EXTRACT}", "runs only this plugin's", a)
        self.assertBlocked(f"bash {EXTRACT} a.jsonl b.jsonl", "one log path", a)
        self.assertBlocked("echo x > notes.md", "redirect", a)
        self.assertBlocked("cp /logs/s.jsonl /tmp/s", "`cp` is not allowed", a)

    def test_dependency_auditor_runs_audit_and_read_only_package_commands(self):
        a = "dependency-auditor"
        for arg in ("", " composer", " npm"):
            self.assertAllowed(f"bash {AUDIT}{arg}", a)
        self.assertBlocked(f"bash {AUDIT} yarn", "composer, npm, or nothing", a)
        self.assertAllowed("composer outdated --direct --format=json --no-plugins --no-scripts", a)
        self.assertAllowed("composer audit --format=json --locked --no-plugins --no-scripts", a)
        self.assertBlocked("composer audit --format=json", "--no-plugins and --no-scripts", a)
        self.assertBlocked("composer update --no-plugins --no-scripts", "not read-only", a)
        self.assertBlocked("composer require x/y --no-plugins --no-scripts", "not read-only", a)
        self.assertAllowed("npm outdated --json", a)
        self.assertAllowed("npm audit --json", a)
        self.assertAllowed("npm view laravel-mix versions --json", a)
        self.assertBlocked("npm audit fix", "takes no subcommand", a)
        self.assertBlocked("npm install", "not read-only", a)
        self.assertBlocked("npx something", "`npx` is not allowed", a)
        # A flag that takes a separate value must not hide the real subcommand behind it.
        self.assertBlocked("npm --cache outdated install", "as the first word", a)
        self.assertBlocked("npm outdated --prefix /x", "not an allowed flag", a)
        self.assertBlocked("npm outdated --depth 0 install", "not an allowed flag", a)
        self.assertAllowed("npm ls --depth=0 --json", a)
        self.assertBlocked("composer -d outdated update --no-plugins --no-scripts", "as the first word", a)
        self.assertBlocked("composer outdated --working-dir /x --no-plugins --no-scripts", "not an allowed flag", a)
        self.assertBlocked("composer outdated -d update --no-plugins --no-scripts", "not an allowed flag", a)

    def test_ui_reviewer_browses_and_crops_its_own_screenshots(self):
        a = "ui-reviewer"
        shot = f"{TMP}/ui-1.png"
        for cmd in ("agent-browser open https://app.test/orders",
                    "agent-browser --session ui snapshot -i",
                    "agent-browser hover @e3",
                    "agent-browser set viewport 375 812",
                    "agent-browser set media dark",
                    "agent-browser get text @e1",
                    f"agent-browser screenshot {shot}",
                    f"agent-browser screenshot --full '#main' {shot}",
                    f"agent-browser screenshot {self.cwd}/.scratch/ui/1.png",
                    f"magick png:{shot} -crop 400x300+10+20 +repage {TMP}/ui-1-crop.png",
                    "git diff main...HEAD -- resources/views"):
            self.assertAllowed(cmd, a)
        self.assertBlocked("agent-browser screenshot /Users/x/.zshrc", "must be saved under", a)
        self.assertBlocked("agent-browser screenshot", "must be saved under", a)
        self.assertBlocked("agent-browser open file:///etc/passwd", "one http(s) URL", a)
        self.assertBlocked("agent-browser eval 'document.cookie'", "probe", a)
        self.assertBlocked("agent-browser fill @e2 hello", "not an allowed verb", a)
        self.assertBlocked("agent-browser press Enter", "navigation keys", a)
        self.assertBlocked("agent-browser get cdp-url", "`get` allows only", a)
        self.assertBlocked("agent-browser set credentials u p", "`set` allows only", a)
        self.assertBlocked("agent-browser --cdp 9222 snapshot", "before the verb", a)
        self.assertBlocked("agent-browser download @e1 /tmp/x.zip", "not an allowed verb", a)
        self.assertBlocked(f"magick png:{shot} {self.cwd}/app/logo.png", "under", a)
        self.assertBlocked(f"magick {shot} {TMP}/y.png", "names its format", a)
        self.assertBlocked(f"magick msl:{TMP}/x.png {TMP}/y.png", "names its format", a)
        self.assertBlocked(f"magick jpeg:{shot} {TMP}/y.png", "names its format", a)
        self.assertBlocked(f"magick png:{shot} -write {TMP}/z.png {TMP}/y.png", "`magick -write`", a)
        self.assertBlocked(f"magick png:{shot} {TMP}/a.png {TMP}/b.png", "one input screenshot", a)
        self.assertBlocked("agent-browser open http://169.254.169.254/latest/meta-data/", "metadata", a)
        self.assertBlocked("agent-browser open http://metadata.google.internal/", "metadata", a)
        self.assertAllowed("agent-browser open http://localhost:8000/", a)
        # The browser reads these numeric forms as 169.254.169.254 too.
        for host in ("2852039166", "0xA9FEA9FE", "0251.0376.0251.0376", "169.254.43518",
                     "[::ffff:169.254.169.254]", "[::ffff:a9fe:a9fe]", "[fe80::1]"):
            self.assertBlocked(f"agent-browser open 'http://{host}/'", "metadata", a)
        self.assertBlocked("agent-browser open http://1.2.3.4.5/", "more than four parts", a)
        self.assertBlocked("agent-browser open http://09.1.1.1/", "not an address", a)
        self.assertAllowed("agent-browser open http://127.0.0.1:8000/", a)
        self.assertAllowed("agent-browser open http://2130706433/", a)
        self.assertAllowed("agent-browser open https://app.test/1.2", a)
        # Hosts the browser rewrites before it connects are refused outright.
        for url in ("http://169%2E254%2E169%2E254/", "http://169\u3002254\u3002169\u3002254/",
                    "http://\uff11\uff16\uff19.254.169.254/", "http://169.254.169.254\\@app.test/"):
            self.assertBlocked(f"agent-browser open '{url}'", "plain ASCII URL", a)
        self.assertAllowed("agent-browser open 'https://app.test/search?q=a%20b'", a)
        self.assertBlocked("rm -rf app", "`rm` is not allowed", a)


if __name__ == "__main__":
    unittest.main()
