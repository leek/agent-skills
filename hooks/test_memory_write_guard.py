import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

GUARD = Path(__file__).with_name("pre_tool_guard.py")


class MemoryWriteGuardTest(unittest.TestCase):
    def invoke(self, payload, config_dir=None):
        env = {k: v for k, v in os.environ.items() if k != "CLAUDE_CONFIG_DIR"}
        if config_dir:
            env["CLAUDE_CONFIG_DIR"] = config_dir
        return subprocess.run([sys.executable, str(GUARD)], input=json.dumps(payload),
                              text=True, capture_output=True, env=env)

    def run_guard(self, path, agent="leek-skills:standards-reviewer", tool="Write", cwd="/repo",
                  config_dir=None, path_key="file_path"):
        payload = {"tool_name": tool, "tool_input": {path_key: path}, "cwd": cwd}
        if agent:
            payload["agent_type"] = agent
        return self.invoke(payload, config_dir=config_dir).returncode

    def test_user_memory_follows_claude_config_dir(self):
        # A profile (CLAUDE_CONFIG_DIR) keeps user memory at <config dir>/agent-memory/.
        miner = "leek-skills:session-miner"
        profile = "/profiles/work"
        self.assertEqual(self.run_guard(f"{profile}/agent-memory/leek-skills-session-miner/p.md",
                                        agent=miner, config_dir=profile), 0)
        self.assertEqual(self.run_guard(f"{profile}/agent-memory/session-miner/p.md",
                                        agent=miner, config_dir=profile), 0)
        self.assertEqual(self.run_guard(f"{profile}/settings.json", agent=miner, config_dir=profile), 2)
        self.assertEqual(self.run_guard(f"{profile}/agent-memory/x.md", agent=miner, config_dir=profile), 2)
        self.assertEqual(self.run_guard(f"{profile}/agent-memory/release-notes-collector/x.md",
                                        agent=miner, config_dir=profile), 2)
        self.assertEqual(self.run_guard(f"{profile}/agent-memory/leek-skills-session-miner/p.md",
                                        agent=miner), 2)

    def test_memory_files_pass(self):
        self.assertEqual(self.run_guard("/repo/.claude/agent-memory/standards-reviewer/MEMORY.md"), 0)
        self.assertEqual(self.run_guard("/repo/.claude/agent-memory/leek-skills-standards-reviewer/MEMORY.md"), 0)
        self.assertEqual(self.run_guard(".claude/agent-memory/standards-reviewer/notes.md"), 0)
        self.assertEqual(self.run_guard("~/.claude/agent-memory/leek-skills-session-miner/p.md",
                                        agent="leek-skills:session-miner", tool="Edit"), 0)
        self.assertEqual(self.run_guard("~/.claude/agent-memory/session-miner/p.md",
                                        agent="leek-skills:session-miner", tool="Edit"), 0)

    def test_other_writes_are_blocked(self):
        self.assertEqual(self.run_guard("/repo/app/Foo.php"), 2)
        self.assertEqual(self.run_guard("/repo/.claude/agent-memory/../../app/Foo.php"), 2)
        self.assertEqual(self.run_guard("/repo/.claude/agent-memory"), 2)
        self.assertEqual(self.run_guard("/repo/.claude/agent-memory/standards-reviewer"), 2)
        self.assertEqual(self.run_guard("/repo/.claude/settings.json", tool="search_replace",
                                        agent="leek-skills:finding-verifier"), 2)
        self.assertEqual(self.run_guard(""), 2)

    def test_agent_is_scoped_to_own_subdirectory(self):
        # Cannot write directly under agent-memory/ or into another agent's directory.
        self.assertEqual(self.run_guard("/repo/.claude/agent-memory/x.md"), 2)
        self.assertEqual(self.run_guard("/repo/.claude/agent-memory/finding-verifier/MEMORY.md",
                                        agent="leek-skills:standards-reviewer"), 2)
        self.assertEqual(self.run_guard("/repo/.claude/agent-memory/standards-reviewer-evil/MEMORY.md",
                                        agent="leek-skills:standards-reviewer"), 2)
        self.assertEqual(self.run_guard("~/.claude/agent-memory/release-notes-collector/p.md",
                                        agent="leek-skills:session-miner"), 2)
        self.assertEqual(self.run_guard("/repo/.claude/agent-memory/standards-reviewer/MEMORY.md",
                                        agent="../evil:standards-reviewer"), 0)
        self.assertEqual(self.run_guard("/repo/.claude/agent-memory/../evil-standards-reviewer/x.md",
                                        agent="../evil:standards-reviewer"), 2)

    def test_declared_memory_scope_is_enforced(self):
        # Project-scoped agents cannot write user memory (~ or CLAUDE_CONFIG_DIR),
        # even when cwd lies under ~.
        home_repo = str(Path.home() / "Code" / "sample-repo")
        for agent in ("leek-skills:finding-verifier", "leek-skills:standards-reviewer",
                      "leek-skills:deepening-scout", "leek-skills:dependency-auditor",
                      "leek-skills:upgrade-impact-scout"):
            bare = agent.split(":")[-1]
            self.assertEqual(self.run_guard(f"~/.claude/agent-memory/{bare}/MEMORY.md",
                                            agent=agent, cwd="/repo"), 2)
            self.assertEqual(self.run_guard(f"~/.claude/agent-memory/{bare}/MEMORY.md",
                                            agent=agent, cwd=home_repo), 2)
            self.assertEqual(self.run_guard(f"/profiles/work/agent-memory/{bare}/MEMORY.md",
                                            agent=agent, cwd="/repo", config_dir="/profiles/work"), 2)
            self.assertEqual(self.run_guard(f"{home_repo}/.claude/agent-memory/{bare}/MEMORY.md",
                                            agent=agent, cwd=home_repo), 0)
        # User-scoped agents cannot write project memory.
        for agent in ("leek-skills:session-miner", "leek-skills:release-notes-collector"):
            bare = agent.split(":")[-1]
            self.assertEqual(self.run_guard(f"/repo/.claude/agent-memory/{bare}/p.md",
                                            agent=agent, cwd="/repo"), 2)
            self.assertEqual(self.run_guard(f"~/.claude/agent-memory/{bare}/p.md",
                                            agent=agent, cwd="/repo"), 0)

    def test_project_memory_when_cwd_is_home(self):
        # Run from $HOME, a project agent's project memory is ~/.claude/agent-memory/<agent>/.
        home = str(Path.home())
        self.assertEqual(self.run_guard("~/.claude/agent-memory/standards-reviewer/MEMORY.md", cwd=home), 0)
        self.assertEqual(self.run_guard(".claude/agent-memory/standards-reviewer/MEMORY.md", cwd=home), 0)
        self.assertEqual(self.run_guard("~/.claude/agent-memory/finding-verifier/MEMORY.md", cwd=home), 2)
        self.assertEqual(self.run_guard("~/.claude/settings.json", cwd=home), 2)
        # Reached only as a parent of cwd, home is still not project memory.
        self.assertEqual(self.run_guard("~/.claude/agent-memory/standards-reviewer/MEMORY.md",
                                        cwd=os.path.join(home, "Code", "x")), 2)

    def test_symlinked_memory_root_is_refused(self):
        # A PR under triage can commit `.claude/agent-memory/<agent>` (or `agent-memory`) as a
        # symlink; following it would make its target (the whole repo, $HOME) the memory root.
        with tempfile.TemporaryDirectory() as tmp:
            repo = os.path.realpath(tmp)
            os.makedirs(os.path.join(repo, ".claude", "agent-memory"))
            os.symlink("../..", os.path.join(repo, ".claude", "agent-memory", "standards-reviewer"))
            self.assertEqual(self.run_guard(os.path.join(
                repo, ".claude", "agent-memory", "standards-reviewer", "app", "Foo.php"), cwd=repo), 2)
            self.assertEqual(self.run_guard(os.path.join(repo, "app", "Foo.php"), cwd=repo), 2)
        with tempfile.TemporaryDirectory() as tmp:
            repo = os.path.realpath(tmp)
            os.makedirs(os.path.join(repo, ".claude"))
            os.makedirs(os.path.join(repo, "app", "standards-reviewer"))
            os.symlink("../app", os.path.join(repo, ".claude", "agent-memory"))
            self.assertEqual(self.run_guard(os.path.join(
                repo, ".claude", "agent-memory", "standards-reviewer", "Foo.php"), cwd=repo), 2)
            self.assertEqual(self.run_guard(os.path.join(
                repo, "app", "standards-reviewer", "Foo.php"), cwd=repo), 2)
        with tempfile.TemporaryDirectory() as tmp:
            repo = os.path.realpath(tmp)
            os.makedirs(os.path.join(repo, "elsewhere", "agent-memory", "standards-reviewer"))
            os.symlink("elsewhere", os.path.join(repo, ".claude"))
            self.assertEqual(self.run_guard(os.path.join(
                repo, ".claude", "agent-memory", "standards-reviewer", "x.md"), cwd=repo), 2)

    def test_every_path_key_must_be_memory(self):
        ok = "/repo/.claude/agent-memory/standards-reviewer/notes.md"
        agent = "leek-skills:standards-reviewer"
        for extra in ({"target_file": "/repo/app/Foo.php"}, {"path": "/repo/app/Foo.php"},
                      {"notebook_path": "/repo/app/x.ipynb"}):
            with self.subTest(extra=extra):
                result = self.invoke({"tool_name": "Delete", "agent_type": agent, "cwd": "/repo",
                                      "tool_input": {"file_path": ok, **extra}})
                self.assertEqual(result.returncode, 2, result.stderr)
        both_ok = self.invoke({"tool_name": "Delete", "agent_type": agent, "cwd": "/repo",
                               "tool_input": {"file_path": ok, "target_file": ok}})
        self.assertEqual(both_ok.returncode, 0, both_ok.stderr)
        # A path key with a non-string value fails closed.
        for bad in (["/repo/app/Foo.php"], 1, {"p": "x"}):
            with self.subTest(bad=bad):
                result = self.invoke({"tool_name": "Delete", "agent_type": agent, "cwd": "/repo",
                                      "tool_input": {"file_path": ok, "target_file": bad}})
                self.assertEqual(result.returncode, 2, result.stderr)

    def test_path_keys_cover_all_write_tools(self):
        for key, tool in (("file_path", "Write"), ("path", "write"), ("target_file", "Delete"),
                          ("notebook_path", "EditNotebook"), ("target_notebook", "EditNotebook"),
                          ("file_path", "StrReplace"), ("path", "hashline_edit")):
            with self.subTest(tool=tool, key=key):
                self.assertEqual(
                    self.run_guard("/repo/.claude/agent-memory/standards-reviewer/notes.md",
                                   tool=tool, path_key=key), 0)
                self.assertEqual(self.run_guard("/repo/app/Foo.ipynb", tool=tool, path_key=key), 2)

    def test_memory_must_be_this_sessions_own(self):
        # A `.claude/agent-memory` segment somewhere else is not this session's memory.
        self.assertEqual(self.run_guard("/elsewhere/.claude/agent-memory/standards-reviewer/x.md"), 2)
        self.assertEqual(self.run_guard("/repo/sub/.claude/agent-memory/standards-reviewer/x.md"), 2)
        # A parent's memory directory is fine: the agent may run from a subdirectory.
        self.assertEqual(
            self.run_guard("/repo/.claude/agent-memory/standards-reviewer/x.md", cwd="/repo/app/deep"), 0)
        with tempfile.TemporaryDirectory() as tmp:
            repo = os.path.realpath(tmp)
            memory = os.path.join(repo, ".claude", "agent-memory", "standards-reviewer")
            os.makedirs(memory)
            os.makedirs(os.path.join(repo, "app"))
            os.symlink(os.path.join(repo, "app"), os.path.join(memory, "out"))
            self.assertEqual(self.run_guard(os.path.join(memory, "notes.md"), cwd=repo), 0)
            self.assertEqual(self.run_guard(os.path.join(memory, "out", "Foo.php"), cwd=repo), 2)

    def test_other_callers_pass_through(self):
        self.assertEqual(self.run_guard("/repo/app/Foo.php", agent=None), 0)
        self.assertEqual(self.run_guard("/repo/app/Foo.php", agent="leek-skills:researcher"), 0)

    def test_grok_write_payloads_are_guarded(self):
        blocked = self.invoke({
            "hookEventName": "pre_tool_use",
            "toolName": "search_replace",
            "toolInput": {"file_path": "/repo/app/Foo.php"},
            "subagentType": "leek-skills:standards-reviewer",
            "cwd": "/repo",
        })
        self.assertEqual(blocked.returncode, 2)
        self.assertIn("BLOCKED:", blocked.stderr)

        allowed = self.invoke({
            "hookEventName": "pre_tool_use",
            "toolName": "search_replace",
            "toolInput": {"file_path": "/repo/.claude/agent-memory/standards-reviewer/notes.md"},
            "subagentType": "leek-skills:standards-reviewer",
            "cwd": "/repo",
        })
        self.assertEqual(allowed.returncode, 0, allowed.stderr)

    def test_malformed_write_payloads_fail_closed(self):
        for bad in [
            {"tool_name": "Write", "tool_input": None, "agent_type": "leek-skills:standards-reviewer"},
            {"tool_name": "Write", "tool_input": "not-a-dict", "agent_type": "leek-skills:standards-reviewer"},
            {"tool_name": "Write", "tool_input": {"file_path": "/repo/.claude/agent-memory/x.md"},
             "cwd": 123, "agent_type": "leek-skills:standards-reviewer"},
        ]:
            with self.subTest(payload=bad):
                result = self.invoke(bad)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn("guard failed", result.stderr)

    def test_dual_guarded_agent_is_enforced_on_both_shell_and_write(self):
        self.assertEqual(self.run_guard("/repo/app/Foo.php", agent="leek-skills:finding-verifier"), 2)
        self.assertEqual(self.run_guard("/repo/.claude/agent-memory/finding-verifier/notes.md",
                                        agent="leek-skills:finding-verifier"), 0)
        shell_blocked = self.invoke({
            "tool_name": "Bash",
            "tool_input": {"command": "git commit -m x"},
            "agent_type": "leek-skills:finding-verifier",
        })
        self.assertEqual(shell_blocked.returncode, 2)
        self.assertIn("not a read-only git command", shell_blocked.stderr)

    def test_read_only_agents_without_memory_write_nothing(self):
        # Their disallowedTools drop Write/Edit on Claude Code; the hook holds where that is ignored.
        for agent in ("pr-reviewer", "spec-reviewer", "browser-tester", "browser-test-planner",
                      "ui-reviewer"):
            for tool in ("Write", "Edit", "search_replace"):
                with self.subTest(agent=agent, tool=tool):
                    self.assertEqual(self.run_guard("/repo/.claude/agent-memory/x/a.md",
                                                    agent=f"leek-skills:{agent}", tool=tool), 2)
        self.assertEqual(self.run_guard("/repo/app/Foo.php", agent="leek-skills:researcher"), 0)

    def test_every_memory_agent_is_guarded_or_a_named_writer(self):
        # `memory:` gives an agent Write and Edit even when its `tools:` line has neither.
        # `researcher` writes its findings file, so it is the one agent left unguarded.
        import importlib.util
        spec = importlib.util.spec_from_file_location("pre_tool_guard", GUARD)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        writers = {"researcher"}
        for agent in sorted(GUARD.parent.parent.glob("agents/*.md")):
            frontmatter = agent.read_text().split("---")[1]
            declared = next((line.split(":", 1)[1].strip() for line in frontmatter.splitlines()
                             if line.startswith("memory:")), None)
            if declared and agent.stem not in writers:
                with self.subTest(agent=agent.stem):
                    self.assertEqual(mod.MEMORY_ONLY.get(agent.stem), declared,
                                     f"{agent.stem} declares memory: {declared} but MEMORY_ONLY disagrees")
                    self.assertEqual(
                        self.run_guard("/repo/app/Foo.php", agent=f"leek-skills:{agent.stem}"),
                        2,
                        f"{agent.stem} has memory: but is not blocked from writing outside agent-memory",
                    )


if __name__ == "__main__":
    unittest.main()
