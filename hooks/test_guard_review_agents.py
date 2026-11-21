import json
import subprocess
import sys
import unittest
from pathlib import Path

DISPATCHER = Path(__file__).with_name("pre_tool_guard.py")


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
        self.assertAllowed("rg -n 'x' 'app/Foo#Bar.php'")

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

    def test_dispatcher_guards_shell_tool_and_additional_review_agents(self):
        # Grok daemon routes shell calls under tool name "Shell".
        def shell_call(command, agent):
            payload = {"tool_name": "Shell", "tool_input": {"command": command}, "agent_type": agent}
            return subprocess.run([sys.executable, str(DISPATCHER)], input=json.dumps(payload),
                                  text=True, capture_output=True)

        self.assertEqual(shell_call("git log --oneline -5", "leek-skills:finding-verifier").returncode, 0)
        self.assertEqual(shell_call("git commit -m x", "leek-skills:pr-reviewer").returncode, 2)
        self.assertEqual(shell_call("rm -rf x", "leek-skills:browser-tester").returncode, 2)

        # Read-only git-only agents are guarded; agents that run bash/composer/agent-browser are not.
        for agent in ("leek-skills:standards-reviewer", "leek-skills:spec-reviewer",
                      "leek-skills:deepening-scout", "standards-reviewer",
                      "spec-reviewer", "deepening-scout"):
            self.assertAllowed("git diff main...HEAD", agent=agent)
            self.assertAllowed("git log --oneline -10", agent=agent)
            self.assertBlocked("git commit -m x", "not a read-only git command", agent=agent)
            self.assertBlocked("rm -rf app", "`rm` is not allowed", agent=agent)
        self.assertAllowed("bash extract-signal.sh log.jsonl", agent="leek-skills:session-miner")
        self.assertAllowed("composer audit --format=json", agent="leek-skills:dependency-auditor")
        self.assertAllowed("agent-browser snapshot -i", agent="leek-skills:ui-reviewer")

    def test_empty_quote_io_number_desync_is_blocked(self):
        # Empty quotes disqualify IO_NUMBER in bash/zsh, so `""2>/dev/null` passes `2` as an
        # argument and redirects stdout instead of stderr.
        self.assertBlocked('echo pwned | uniq -f ""2>/dev/null - /tmp/pwned', "redirects")
        self.assertBlocked("echo pwned | uniq -f ''2>/dev/null - /tmp/pwned", "redirects")
        self.assertBlocked('echo pwned | uniq -f 2"">/dev/null - /tmp/pwned', "redirects")
        self.assertBlocked("echo pwned | uniq -f 2''>/dev/null - /tmp/pwned", "redirects")
        self.assertBlocked('gh api -q ""2>/dev/null -X DELETE repos/o/r', "redirects")
        self.assertBlocked('git log ""2>&1', "redirects")
        self.assertAllowed("git log --oneline -5 2>/dev/null")
        self.assertAllowed("git log 2>&1 | head -5")

    def test_jq_env_secret_exposure_is_blocked(self):
        self.assertBlocked("jq -n env", "environment variables")
        self.assertBlocked("jq 'env'", "environment variables")
        self.assertBlocked("jq '$ENV'", "environment variables")
        self.assertBlocked("jq -n 'env.GITHUB_TOKEN'", "environment variables")
        self.assertBlocked("jq -n '$ENV.AWS_SECRET_ACCESS_KEY'", "environment variables")
        self.assertBlocked("jq -n '{t: env}'", "environment variables")
        self.assertBlocked('jq -n \'"\\(env.TOKEN)"\'', "environment variables")
        self.assertBlocked('jq -n \'"\\($ENV.TOKEN)"\'', "environment variables")
        self.assertBlocked("jq -f evil.jq data.json", "--from-file")
        self.assertBlocked("jq --from-file=evil.jq data.json", "--from-file")
        self.assertBlocked("gh pr view 1 --json title --jq env", "environment variables")
        self.assertBlocked("gh pr view 1 --json title -q '$ENV'", "environment variables")
        self.assertBlocked("gh pr list --json number --jq 'env.GITHUB_TOKEN'", "environment variables")
        self.assertBlocked("gh api user --jq 'env'", "environment variables")
        self.assertBlocked("gh api user -q'$ENV'", "environment variables")
        self.assertBlocked("gh api user --jq='env.SECRET'", "environment variables")
        # Field access and longer identifiers stay allowed.
        self.assertAllowed("jq -r '.env' config.json")
        self.assertAllowed("jq -r '.foo.env' config.json")
        self.assertAllowed("jq -r '.environment' config.json")
        self.assertAllowed("jq -r '.[\"env\"]' config.json")
        self.assertAllowed("jq -r '.my_env' config.json")
        self.assertAllowed("gh api user --jq '.env'")
        self.assertAllowed("gh pr list --json name --jq '.[].environment'")
        self.assertAllowed("gh pr view 1 --json title -q '.title'")

    def test_jq_module_loading_is_blocked(self):
        # A module on -L defining `def leak: env;` reads the environment past the filter check.
        for cmd in ["jq -n -L /tmp/jqmod 'include \"m\"; leak'",
                    "jq -n -L/tmp/jqmod 'leak'",
                    "jq -nL /tmp/jqmod 'leak'",
                    "jq --library-path /tmp/jqmod 'leak'",
                    "jq --library-path=/tmp/jqmod 'leak'",
                    "jq -n 'include \"m\"; leak'",
                    "jq -n 'import \"m\" as m; m::leak'",
                    "jq -n 'import \"m\" as $m; $m'",
                    "gh api user --jq 'include \"m\"; leak'"]:
            with self.subTest(cmd=cmd):
                self.assertBlocked(cmd, "modules")
        self.assertBlocked("jq --run-tests t.txt", "`jq --run-tests`")
        self.assertBlocked("jq -nZ .", "`jq -nZ`")
        self.assertAllowed("jq -r '.include' data.json")
        self.assertAllowed("jq -r '.[] | select(.kind == \"import\")' data.json")
        self.assertAllowed("jq -nr --arg x -L '$x'")
        self.assertAllowed("jq --indent 2 -S . data.json")
        self.assertAllowed("jq -s --slurpfile a a.json '.' b.json")

    def test_jq_env_check_reads_only_the_filter_and_builtin_calls(self):
        # Path-like file arguments are not filters, and a quoted object key is not the builtin.
        for cmd in ["jq '.name' config/env.json",
                    "jq . src/include/x.json",
                    "jq -r . import.json ./env",
                    "jq -- . env.json",
                    "jq . - data.json",
                    "gh pr view 1 --json body --jq '{\"env\": .environment}'",
                    "jq '{a: 1, \"env\": .e}' data.json",
                    "jq -n '$__loc__'"]:
            with self.subTest(cmd=cmd):
                self.assertAllowed(cmd)
        for cmd in ["jq -n '{a: env}'",
                    "jq -n '{env: env}'",
                    "jq -n '{env: 1} | env'",
                    "jq '.[env:]' data.json",
                    "jq -n 'env::x'",
                    "jq -n -- env",
                    "gh api user --jq '{env: env.HOME}'",
                    # A bare `-` must not stand in for the filter and hide the real one.
                    "jq -n - 'env'",
                    "jq - 'env' file.json",
                    "jq -n - 'env.x/1'",
                    # No unquoted-key exemption: `.[0,env:]` is a slice that evaluates env.
                    "jq -nc '[1,2,3] | .[0,env:]'",
                    "jq '{env: .environment}' data.json",
                    "jq . data.json env"]:
            with self.subTest(cmd=cmd):
                self.assertBlocked(cmd, "environment variables")

    def test_jq_env_split_by_space_or_comment_is_blocked(self):
        # jq 1.6 lexes `$` and `ENV` as separate tokens, so whitespace or a comment may sit between.
        self.assertBlocked("jq -n '$ ENV.PATH'", "environment variables")
        self.assertBlocked("jq -n '$\tENV.PATH'", "environment variables")
        for cmd in ["jq -n '$ #x\nENV.PATH'",
                    "jq -n '. # note'",
                    "jq -n 'e#x\nnv'",
                    "jq -n '\"\\(1 # c\n)\"'"]:
            with self.subTest(cmd=cmd):
                self.assertBlocked(cmd, "comments")
        self.assertBlocked("jq -n '\"abc'", "unterminated string")
        # `#` inside a string literal is text, not a comment.
        self.assertAllowed("gh pr list --json number,title --jq '.[] | \"#\\(.number) \\(.title)\"'")
        self.assertAllowed("jq -r '\"a\\\"#b\"' data.json")
        self.assertAllowed("jq -r '\"\\(\"#\" + .x)\"' data.json")

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
        self.assertBlocked("gh api graphql -F query=@payload.graphql", "sends a local file")
        # A value flag swallows the next argument, so `-X GET` here is the jq filter, not a method.
        self.assertBlocked("gh api -q -X GET repos/{owner}/{repo}/issues -f title=x", "sends a POST")
        self.assertBlocked("gh api --input body.json repos/{owner}/{repo}/issues", "request body")
        self.assertBlocked("gh api --unknown-flag repos/{owner}/{repo}", "not a flag this guard knows")
        self.assertBlocked("gh pr view 12 --web=true", "opens a browser")

    def test_program_and_ref_writing_flags_are_blocked(self):
        self.assertAllowed("git fetch origin main")
        self.assertAllowed("git fetch origin pull/12/head")
        self.assertBlocked("git fetch origin +refs/pull/1/head:refs/heads/main", "write a local ref")
        self.assertBlocked("rg --hostname-bin ./evil.sh --hyperlink-format 'file://{host}{path}' foo",
                           "runs a program")
        self.assertBlocked("git fetch origin tag v1", "write a local ref")
        self.assertBlocked("git fetch --stdin origin", "is not allowed")
        self.assertBlocked("git fetch --refmap=x:refs/heads/main origin main", "is not allowed")
        self.assertBlocked("git fetch --ref=x:refs/heads/main origin main", "is not allowed")
        self.assertAllowed("git fetch -q --no-tags origin main")

    def test_expansions_that_hide_arguments_are_blocked(self):
        # The shell expands these before the command runs; the guard only sees what was typed.
        self.assertBlocked("find . -de*", "unquoted glob")
        self.assertBlocked("sort *", "unquoted glob")
        self.assertBlocked("rg -n foo *.php", "unquoted glob")
        self.assertBlocked("cat [a-z]*", "unquoted glob")
        self.assertBlocked("uniq notes*", "unquoted glob")
        self.assertBlocked("rg -n foo app/*.php", "unquoted glob")
        self.assertBlocked("sort ${X:--o} out.txt notes.txt", "parameter expansion")
        self.assertBlocked('sort "${X:--o}" out.txt notes.txt', "parameter expansion")
        self.assertBlocked("git log $GIT_FLAGS", "parameter expansion")
        self.assertBlocked('git log "$@"', "parameter expansion")
        self.assertBlocked("echo $=X", "parameter expansion")
        self.assertBlocked("echo $~X $^X $+X", "parameter expansion")
        # The shell joins a backslash-newline before it expands, so the guard must too.
        self.assertBlocked("echo $\\\n(rm -rf x)", "command substitution")
        self.assertBlocked('echo "$\\\n(rm -rf x)"', "command substitution")
        self.assertBlocked("sort $\\\n{X:--o} out.txt notes.txt", "parameter expansion")
        self.assertBlocked("echo `\\\nrm x`", "command substitution")
        self.assertAllowed("rg -n 'a\\\nb' app")
        self.assertAllowed("rg -n foo$ app")
        self.assertAllowed("rg -n 'total: \\$[0-9]+' app")
        self.assertAllowed('rg -n "foo$" app')
        self.assertAllowed("gh api graphql -f query='query($n: Int!) { viewer { login } }' -F n=1")
        self.assertBlocked("sort {-o,out.txt} notes.txt", "brace expansion")
        self.assertBlocked("cat notes{1..3}.txt", "brace expansion")
        self.assertAllowed("rg -n foo app -g '*.php'")
        self.assertAllowed("find app -name '*.php' -o -name \"-de*\"")
        self.assertAllowed("git log --oneline 'HEAD@{1}..HEAD@{0}' HEAD@{1}")
        self.assertBlocked("sort {-o,o{u}t.txt} notes.txt", "brace expansion")
        self.assertBlocked("sort {-o,'x'} notes.txt", "brace expansion")
        self.assertBlocked("git log HEAD@{1}..HEAD@{0}", "brace expansion")
        # zsh extended glob: ^x is every file but x, and x~y and x# are patterns too.
        self.assertBlocked("cat ^notes.txt", "unquoted glob")
        self.assertBlocked("find . -delete~x", "unquoted glob")
        self.assertBlocked("rg -n x app/Foo#Bar.php", "unquoted glob")
        self.assertAllowed("git show 'HEAD~3' 'HEAD^' ~/notes.txt")
        # code-review's review-scope.sh hands spec/standards reviewers unquoted revisions. Under
        # zsh extended glob `X~Y` can only shrink to the file X, so `~` mid-word is refused only
        # where X could be a flag (a word starting with `-`).
        for agent in ("leek-skills:spec-reviewer", "leek-skills:standards-reviewer"):
            self.assertAllowed("git diff HEAD~1...HEAD", agent=agent)
            self.assertAllowed("git log HEAD~1..HEAD --oneline", agent=agent)
            self.assertAllowed("git show main~3", agent=agent)
        self.assertBlocked("git log --output=x~y", "unquoted glob")
        self.assertBlocked("find . -delete~x", "unquoted glob")
        self.assertAllowed("rg -n 'a{1,3}' app")
        self.assertAllowed("gh api 'repos/{owner}/{repo}/pulls?per_page=5'")

    def test_panel_findings(self):
        # git fetch: a configured remote's name only; no shallow rewrite.
        self.assertAllowed("git fetch origin")
        self.assertAllowed("git fetch -q origin pull/12/head")
        self.assertBlocked("git fetch https://other.example/leak-data", "configured remote")
        self.assertBlocked("git fetch git@other.example:o/r.git main", "configured remote")
        self.assertBlocked("git fetch 'ext::sh -c touch-x'", "configured remote")
        self.assertBlocked("git fetch ../other-repo", "configured remote")
        self.assertBlocked("git fetch --depth=1 origin main", "is not allowed")
        # gh: github.com only, and no local file as a field value.
        self.assertBlocked("gh api --hostname other.example user", "not a flag this guard knows")
        self.assertBlocked("gh api https://other.example/x", "another host")
        self.assertBlocked("gh api -X GET search/code -F q=@/etc/passwd", "sends a local file")
        self.assertBlocked("gh api -X GET search/code -Fq=@-", "sends a local file")
        self.assertAllowed("gh api -X GET search/code -f q=@mention")
        self.assertAllowed("gh api https://github.com/api/v3/user")
        self.assertBlocked("gh pr view 1 -R other.example/o/r", "OWNER/REPO")
        self.assertBlocked("gh pr view 1 --repo=other.example/o/r", "OWNER/REPO")
        self.assertBlocked("gh pr view https://other.example/o/r/pull/1", "only github.com")
        self.assertAllowed("gh pr view 1 -R o/r --json title")
        self.assertBlocked("gh repo view other.example/o/r", "only OWNER/REPO")
        self.assertBlocked("gh repo view git@other.example:o/r", "only OWNER/REPO")
        self.assertBlocked("gh pr view other.example/o/r/pull/1", "only OWNER/REPO")
        self.assertAllowed("gh repo view o/r --json name")
        # A value flag takes the next token whatever it looks like: here the jq filter is
        # `-q`, and the host is a positional.
        self.assertBlocked("gh repo view -q -q other.example/o/r", "only OWNER/REPO")
        self.assertBlocked("gh repo view --jq --json other.example/o/r", "only OWNER/REPO")
        self.assertBlocked("gh repo view 'other.example/o/r x'", "only OWNER/REPO")
        self.assertBlocked("gh pr view 1 --unknown-flag x", "not a flag this guard knows")
        self.assertBlocked("gh pr view 1 -Rother.example/o/r", "OWNER/REPO")
        self.assertAllowed("gh pr checks 12 --watch --fail-fast -i 30")
        self.assertAllowed("gh pr list -s open -L 5 -S 'is:pr author:@me' --json number")
        self.assertAllowed("gh run view 123 --log-failed --job 456")
        self.assertAllowed("gh pr view https://github.com/o/r/pull/1")
        self.assertAllowed("gh pr view feature/login --json title")
        self.assertAllowed("gh pr list --json number --jq '.[] | \"\\(.a)/\\(.b)/\\(.c)\"'")
        # A 2 that is quoted, or apart from the operator, is an argument, not a file descriptor.
        self.assertAllowed("git log --oneline -5 2>/dev/null")
        self.assertAllowed("git log 2>&1 | head -5")
        self.assertBlocked('uniq -f "2">/dev/null input output', "redirects")
        self.assertBlocked("uniq -f 2 > /dev/null input output", "redirects")
        # BSD uniq reads the word after the input as the output file, dash or not.
        self.assertBlocked("uniq Makefile -out", "writes a file")
        self.assertAllowed("uniq -c notes.txt")
        # Programs run through git and rg.
        self.assertBlocked("git cat-file --filters HEAD:file", "runs a program")
        self.assertBlocked("git diff --textconv 'HEAD~1'", "runs a program")
        self.assertBlocked("rg -z foo app", "decompression")
        self.assertBlocked("rg --search-zip foo app", "runs a program")

    def test_unparseable_or_non_object_payloads_pass_through(self):
        for raw in ("", "{not json", "null", "[1, 2]", '"hello"'):
            with self.subTest(raw=raw):
                result = subprocess.run([sys.executable, str(DISPATCHER)], input=raw,
                                        text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stderr, "")

    def test_unguarded_agent_with_malformed_input_passes_through(self):
        payload = {"tool_name": "Bash", "tool_input": 5, "agent_type": "leek-skills:browser-writer"}
        result = subprocess.run([sys.executable, str(DISPATCHER)], input=json.dumps(payload),
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_a_crashing_guard_blocks(self):
        payload = {"tool_name": "Bash", "tool_input": {"command": 5},
                   "agent_type": "leek-skills:pr-reviewer"}
        result = subprocess.run([sys.executable, str(DISPATCHER)], input=json.dumps(payload),
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("guard failed", result.stderr)

    def test_unknown_tool_for_guarded_agent_blocks(self):
        payload = {"tool_name": "FutureShellTool", "tool_input": {"command": "rm -rf /"},
                   "agent_type": "leek-skills:pr-reviewer"}
        result = subprocess.run([sys.executable, str(DISPATCHER)], input=json.dumps(payload),
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("guard failed", result.stderr)

    def test_policies_never_reimport_entrypoint_or_duplicate_blocked(self):
        code = (
            "import runpy, sys; "
            f"sys.path.insert(0, {str(DISPATCHER.parent)!r}); "
            "import shell_syntax, review_guard, browser_guard, memory_write_guard; "
            "assert 'pre_tool_guard' not in sys.modules; "
            "assert review_guard.Blocked is shell_syntax.Blocked; "
            "assert browser_guard.Blocked is shell_syntax.Blocked; "
            "assert memory_write_guard.Blocked is shell_syntax.Blocked"
        )
        result = subprocess.run([sys.executable, "-c", code], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
