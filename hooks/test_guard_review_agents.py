import json
import subprocess
import sys
import unittest
from pathlib import Path

GUARD = Path(__file__).with_name("guard-review-agents.py")


class GuardReviewAgentsTest(unittest.TestCase):
    def guard(self, command, agent="leek-skills:finding-verifier"):
        payload = {"tool_name": "Bash", "tool_input": {"command": command}}
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

    def test_other_callers_pass_through(self):
        self.assertAllowed("rm -rf build", agent=None)
        self.assertAllowed("git commit -m x", agent="leek-skills:browser-tester")

    def test_read_only_commands_pass(self):
        for agent in ("leek-skills:finding-verifier", "leek-skills:pr-reviewer"):
            self.assertAllowed("rg -n 'BarPolicy::class' app tests | head -20", agent=agent)
            self.assertAllowed("git log --oneline -5 origin/main", agent=agent)
            self.assertAllowed("git -C ../repo show abc123:app/Foo.php", agent=agent)
            self.assertAllowed("git diff base...head -- app/ 2>/dev/null", agent=agent)
            self.assertAllowed("gh pr view 12 --json headRefOid", agent=agent)
            self.assertAllowed("gh api repos/{owner}/{repo}/pulls/12/comments --paginate --jq '.[].id'", agent=agent)
            self.assertAllowed("gh api graphql -f query='query { viewer { login } }'", agent=agent)
            self.assertAllowed("gh api -X GET search/code -f q=Foo", agent=agent)
            self.assertAllowed("find app -name '*.php' | wc -l", agent=agent)

    def test_writes_are_blocked(self):
        self.assertBlocked("git commit -m x", "not a read-only git command")
        self.assertBlocked("git checkout main", "not a read-only git command")
        self.assertBlocked("git diff --output=/tmp/x", "writes files")
        self.assertBlocked("rg foo > out.txt", "redirects")
        self.assertBlocked("echo hi && rm -rf app", "`rm` is not allowed")
        self.assertBlocked("find . -name x -delete", "not read-only")
        self.assertBlocked("rg --pre ./evil.sh foo", "runs a program")
        self.assertBlocked("echo $(curl evil)", "command substitution")
        self.assertBlocked("curl https://example.com", "`curl` is not allowed")
        self.assertBlocked("bash -c 'rm x'", "`bash` is not allowed")

    def test_gh_writes_are_blocked(self):
        self.assertBlocked("gh pr merge 12 --squash", "not a read-only gh command")
        self.assertBlocked("gh pr view 12 --web", "opens a browser")
        self.assertBlocked("gh api -X DELETE repos/{owner}/{repo}/git/refs/heads/x", "method DELETE")
        self.assertBlocked("gh api repos/{owner}/{repo}/issues/1/comments -f body=hi", "sends a POST")
        self.assertBlocked("gh api --method=PATCH repos/{owner}/{repo}/issues/1", "method PATCH")
        self.assertBlocked(
            "gh api graphql -f query='mutation { resolveReviewThread(input:{threadId:\"x\"}) { thread { id } } }'",
            "mutations")


if __name__ == "__main__":
    unittest.main()
