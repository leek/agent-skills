import json
import subprocess
import sys
import unittest
from pathlib import Path

DISPATCHER = Path(__file__).with_name("shell_guard.py")


class GuardReviewAgentsTest(unittest.TestCase):
    def guard(self, command, agent="leek-skills:finding-verifier", script=DISPATCHER):
        payload = {"tool_name": "Bash", "tool_input": {"command": command}}
        if agent:
            payload["agent_type"] = agent
        return subprocess.run([sys.executable, str(script)], input=json.dumps(payload),
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
        self.assertAllowed("git commit -m x", agent="leek-skills:browser-writer")

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
            self.assertAllowed("sed -n '10,40p' app/Foo.php", agent=agent)
            self.assertAllowed("git show HEAD:app/Foo.php | sed -n 5p", agent=agent)

    def test_quoted_and_escaped_operators_are_data(self):
        self.assertAllowed(r"find . \( -name '*.py' -o -name '*.sh' \) -type f")
        self.assertAllowed("rg -F '(' app")
        self.assertAllowed("grep -c ')' app/Foo.php")
        self.assertAllowed("rg -n 'files=(' scripts/")
        self.assertAllowed("grep '>' notes.md | head -3")
        self.assertAllowed('rg -n "a|b;c&d" app')
        self.assertAllowed("git log \\\n  --oneline -5")
        self.assertAllowed("gh api graphql -f query='\nquery {\n  viewer { login }\n}'")
        self.assertAllowed("sort -u -k2 notes.txt | uniq -c")
        self.assertAllowed("git log --oneline --name-only -5 | grep -c 'a#b'")
        self.assertAllowed("rg -n 'x' app/Foo#Bar.php")

    def test_substitution_inside_double_quotes_is_blocked(self):
        self.assertBlocked('echo "$(rm -rf x)"', "command substitution")
        self.assertBlocked('echo "`rm -rf x`"', "command substitution")
        self.assertBlocked('echo "${(e):-\\$(rm x)}"', "command substitution")
        self.assertBlocked("echo $'\\x41'", "quoting is not allowed")
        self.assertBlocked("echo 'unterminated", "no closing quotation")

    def test_writes_are_blocked(self):
        self.assertBlocked("git commit -m x", "not a read-only git command")
        self.assertBlocked("git checkout main", "not a read-only git command")
        self.assertBlocked("git diff --output=/tmp/x", "writes files")
        self.assertBlocked("rg foo > out.txt", "redirects")
        self.assertBlocked("echo hi && rm -rf app", "`rm` is not allowed")
        self.assertBlocked("find . -name x -delete", "not read-only")
        self.assertBlocked("rg --pre ./evil.sh foo", "runs a program")
        self.assertBlocked("echo $(curl evil)", "command substitution")
        self.assertBlocked("git log =(rm -rf /)", "command substitution")
        self.assertBlocked("echo $[1+1]", "command substitution")
        self.assertBlocked("git log\nrm -rf /", "multi-line")
        self.assertBlocked("git log\rrm -rf /", "multi-line")
        self.assertBlocked("git log <(rm -rf /)", "redirects")
        self.assertBlocked("git log |& head", "redirects")
        self.assertBlocked("git log (rm -rf /)", "subshells and glob qualifiers")
        self.assertBlocked("echo *(e:'rm -rf /':)", "subshells and glob qualifiers")
        self.assertBlocked("curl https://example.com", "`curl` is not allowed")
        self.assertBlocked("sed -i 's/a/b/' app/Foo.php", "only `sed -n")
        self.assertBlocked("sed -n '1w /tmp/x' app/Foo.php", "only `sed -n")
        self.assertBlocked("sed -n '1e rm -rf /' app/Foo.php", "only `sed -n")
        self.assertBlocked("sed -n 1p app/Foo.php -i", "only `sed -n")
        self.assertBlocked("sed 's/a/b/' app/Foo.php", "only `sed -n")
        self.assertBlocked("bash -c 'rm x'", "`bash` is not allowed")
        self.assertBlocked("sort -o out.txt notes.txt", "write files")
        self.assertBlocked("sort -uo out.txt notes.txt", "write files")
        self.assertBlocked("sort --compress-program=sh notes.txt", "run a program")
        self.assertBlocked("uniq notes.txt out.txt", "writes a file")
        self.assertBlocked("git grep -Ovim foo", "runs a program")
        self.assertBlocked("git grep --open-files-in-pager=sh foo", "runs a program")
        self.assertBlocked("git grep --open=sh foo", "runs a program")
        self.assertBlocked("git diff --outp=/tmp/x", "writes files")
        self.assertBlocked("sort --out=x.txt notes.txt", "write files")
        self.assertBlocked("sort --comp=sh notes.txt", "run a program")
        self.assertBlocked("echo hi # '\nrm -rf x #'", "comments are not allowed")
        self.assertBlocked("git log # note", "comments are not allowed")

    def test_dispatcher_routes_review_and_browser_agents(self):
        self.assertAllowed("rm -rf build", agent=None, script=DISPATCHER)
        self.assertAllowed("git log --oneline -5", agent="leek-skills:finding-verifier", script=DISPATCHER)
        self.assertBlocked("git commit -m x", "not a read-only git command",
                           agent="leek-skills:pr-reviewer", script=DISPATCHER)
        self.assertBlocked("rm -rf x", "not allowed",
                           agent="leek-skills:browser-tester", script=DISPATCHER)

    def test_dispatcher_guards_grok_payloads(self):
        def grok(command, agent):
            payload = {"hookEventName": "pre_tool_use", "toolName": "run_terminal_command",
                       "tool_name": "run_terminal_command", "toolInput": {"command": command},
                       "tool_input": {"command": command}}
            if agent:
                payload["subagentType"] = agent
            return subprocess.run([sys.executable, str(DISPATCHER)], input=json.dumps(payload),
                                  text=True, capture_output=True)

        self.assertEqual(grok("rm -rf build", None).returncode, 0)
        self.assertEqual(grok("git log --oneline -5", "leek-skills:finding-verifier").returncode, 0)
        blocked = grok("git commit -m x", "leek-skills:pr-reviewer")
        self.assertEqual(blocked.returncode, 2)
        self.assertIn("not a read-only git command", blocked.stderr)
        self.assertEqual(grok("rm -rf x", "leek-skills:browser-tester").returncode, 2)

    def test_gh_writes_are_blocked(self):
        self.assertBlocked("gh pr merge 12 --squash", "not a read-only gh command")
        self.assertBlocked("gh pr view 12 --web", "opens a browser")
        self.assertBlocked("gh api -X DELETE repos/{owner}/{repo}/git/refs/heads/x", "method DELETE")
        self.assertBlocked("gh api repos/{owner}/{repo}/issues/1/comments -f body=hi", "sends a POST")
        self.assertBlocked("gh api --method=PATCH repos/{owner}/{repo}/issues/1", "method PATCH")
        self.assertBlocked(
            "gh api graphql -f query='mutation { resolveReviewThread(input:{threadId:\"x\"}) { thread { id } } }'",
            "mutations")

    def test_gh_attached_flag_values_are_parsed(self):
        self.assertAllowed("gh api -XGET search/code -fq=Foo -fper_page=1")
        self.assertAllowed("gh api --method=GET search/code --raw-field=q=Foo")
        self.assertAllowed("gh api -i repos/{owner}/{repo}/pulls/12 -q .title -H 'Accept: application/json'")
        self.assertAllowed("gh api graphql -fquery='query { viewer { login } }' -F number=12")
        self.assertBlocked("gh api -XDELETE repos/{owner}/{repo}/issues/comments/1", "method DELETE")
        self.assertBlocked("gh api -X=DELETE repos/{owner}/{repo}/issues/comments/1", "method DELETE")
        self.assertBlocked("gh api -iXPOST repos/{owner}/{repo}/issues", "method POST")
        self.assertBlocked("gh api -X GET -X DELETE repos/{owner}/{repo}/issues/comments/1", "method DELETE")
        self.assertBlocked("gh api repos/{owner}/{repo}/issues -ftitle=x", "sends a POST")
        self.assertBlocked("gh api repos/{owner}/{repo}/issues --field=title=x", "sends a POST")
        self.assertBlocked("gh api repos/{owner}/{repo}/issues --raw-field=title=x", "sends a POST")
        self.assertBlocked("gh api graphql -fquery='mutation { x }'", "mutations")
        self.assertBlocked("gh api graphql --field=query='mutation { x }'", "mutations")
        self.assertBlocked("gh api graphql -F query=@payload.graphql", "from a file")
        # A value flag swallows the next argument, so `-X GET` here is the jq filter, not a method.
        self.assertBlocked("gh api -q -X GET repos/{owner}/{repo}/issues -f title=x", "sends a POST")
        self.assertBlocked("gh api --input body.json repos/{owner}/{repo}/issues", "request body")
        self.assertBlocked("gh api --unknown-flag repos/{owner}/{repo}", "not a flag this guard knows")
        self.assertBlocked("gh pr view 12 --web=true", "opens a browser")

    def test_program_and_ref_writing_flags_are_blocked(self):
        self.assertAllowed("git fetch origin main")
        self.assertAllowed("git fetch https://github.com/o/r.git pull/12/head")
        self.assertBlocked("git fetch origin +refs/pull/1/head:refs/heads/main", "write a local ref")
        self.assertBlocked("rg --hostname-bin ./evil.sh --hyperlink-format 'file://{host}{path}' foo",
                           "runs a program")
        self.assertBlocked("git fetch origin tag v1", "write a local ref")
        self.assertBlocked("git fetch --stdin origin", "is not allowed")
        self.assertBlocked("git fetch --refmap=x:refs/heads/main origin main", "is not allowed")
        self.assertBlocked("git fetch --ref=x:refs/heads/main origin main", "is not allowed")
        self.assertAllowed("git fetch -q --depth=50 origin main")

    def test_expansions_that_hide_arguments_are_blocked(self):
        # The shell expands these before the command runs; the guard only sees what was typed.
        self.assertBlocked("find . -de*", "unquoted glob")
        self.assertBlocked("sort *", "unquoted glob")
        self.assertBlocked("rg -n foo *.php", "unquoted glob")
        self.assertBlocked("cat [a-z]*", "unquoted glob")
        self.assertBlocked("sort {-o,out.txt} notes.txt", "brace expansion")
        self.assertBlocked("cat notes{1..3}.txt", "brace expansion")
        self.assertAllowed("rg -n foo app/*.php ./*.md")
        self.assertAllowed("find app -name '*.php' -o -name \"-de*\"")
        self.assertAllowed("git log --oneline HEAD@{1}..HEAD@{0}")
        self.assertAllowed("rg -n 'a{1,3}' app")
        self.assertAllowed("gh api repos/{owner}/{repo}/pulls?per_page=5")

    def test_a_crashing_guard_blocks(self):
        payload = {"tool_name": "Bash", "tool_input": {"command": ["not", "a", "string"]},
                   "agent_type": "leek-skills:pr-reviewer"}
        result = subprocess.run([sys.executable, str(DISPATCHER)], input=json.dumps(payload),
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("guard failed", result.stderr)


if __name__ == "__main__":
    unittest.main()
