import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

GUARD = Path(__file__).with_name("memory_write_guard.py")


class MemoryWriteGuardTest(unittest.TestCase):
    def run_guard_result(self, path, agent="leek-skills:standards-reviewer", tool="Write", cwd="/repo",
                         config_dir=None, path_key="file_path"):
        payload = {"tool_name": tool, "tool_input": {path_key: path}, "cwd": cwd}
        if agent:
            payload["agent_type"] = agent
        env = {k: v for k, v in os.environ.items() if k != "CLAUDE_CONFIG_DIR"}
        if config_dir:
            env["CLAUDE_CONFIG_DIR"] = config_dir
        return subprocess.run([sys.executable, str(GUARD)], input=json.dumps(payload),
                              text=True, capture_output=True, env=env)

    def run_guard(self, path, agent="leek-skills:standards-reviewer", tool="Write", cwd="/repo",
                  config_dir=None, path_key="file_path"):
        return self.run_guard_result(path, agent=agent, tool=tool, cwd=cwd,
                                     config_dir=config_dir, path_key=path_key).returncode

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

    def test_path_keys_cover_all_write_tools(self):
        for key, tool in (("file_path", "Write"), ("path", "write"), ("target_file", "Delete"),
                          ("notebook_path", "EditNotebook"), ("target_notebook", "EditNotebook")):
            self.assertEqual(
                self.run_guard("/repo/.claude/agent-memory/standards-reviewer/notes.md",
                               tool=tool, path_key=key), 0)
            self.assertEqual(
                self.run_guard("/repo/app/Foo.ipynb", tool=tool, path_key=key), 2)

    def test_malformed_payloads_fail_closed(self):
        for raw in (
            "not json{{{",
            "[]",
            '"just a string"',
            json.dumps({"agent_type": "leek-skills:finding-verifier", "tool_input": ["bad"]}),
            json.dumps({"agent_type": "leek-skills:finding-verifier", "tool_input": {"file_path": "/repo/x"}, "cwd": 123}),
        ):
            res = subprocess.run([sys.executable, str(GUARD)], input=raw, text=True, capture_output=True)
            self.assertEqual(res.returncode, 2, f"did not fail closed for {raw!r}")
            self.assertIn("BLOCKED:", res.stderr)

    def test_other_callers_pass_through(self):
        self.assertEqual(self.run_guard("/repo/app/Foo.php", agent=None), 0)
        self.assertEqual(self.run_guard("/repo/app/Foo.php", agent="leek-skills:researcher"), 0)

    def test_every_memory_agent_is_guarded_or_a_named_writer(self):
        # `memory:` gives an agent Write and Edit even when its `tools:` line has neither.
        # `researcher` writes its findings file, so it is the one agent left unguarded.
        import importlib.util
        spec = importlib.util.spec_from_file_location("memory_write_guard", GUARD)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        writers = {"researcher"}
        for agent in sorted(GUARD.parent.parent.glob("agents/*.md")):
            frontmatter = agent.read_text().split("---")[1]
            for line in frontmatter.splitlines():
                if line.startswith("memory:") and agent.stem not in writers:
                    declared = line.split(":", 1)[1].strip()
                    self.assertIn(agent.stem, mod.MEMORY_ONLY,
                                  f"{agent.stem} has memory: but is not in MEMORY_ONLY")
                    self.assertEqual(mod.MEMORY_ONLY[agent.stem], declared,
                                     f"{agent.stem} scope mismatch: guard={mod.MEMORY_ONLY[agent.stem]} vs agent={declared}")
        self.assertEqual(self.run_guard("/repo/app/Foo.php", agent="leek-skills:upgrade-impact-scout"), 2)
        self.assertEqual(self.run_guard("/repo/app/Foo.php", agent="leek-skills:release-notes-collector"), 2)


if __name__ == "__main__":
    unittest.main()
