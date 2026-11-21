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
                  config_dir=None):
        payload = {"tool_name": tool, "tool_input": {"file_path": path}, "cwd": cwd}
        if agent:
            payload["agent_type"] = agent
        return self.invoke(payload, config_dir=config_dir).returncode

    def test_user_memory_follows_claude_config_dir(self):
        # A profile (CLAUDE_CONFIG_DIR) keeps user memory at <config dir>/agent-memory/.
        miner = "leek-skills:session-miner"
        profile = "/profiles/work"
        self.assertEqual(self.run_guard(f"{profile}/agent-memory/leek-skills-session-miner/p.md",
                                        agent=miner, config_dir=profile), 0)
        self.assertEqual(self.run_guard(f"{profile}/settings.json", agent=miner, config_dir=profile), 2)
        self.assertEqual(self.run_guard(f"{profile}/agent-memory/x.md", agent=miner), 2)

    def test_memory_files_pass(self):
        self.assertEqual(self.run_guard("/repo/.claude/agent-memory/standards-reviewer/MEMORY.md"), 0)
        self.assertEqual(self.run_guard(".claude/agent-memory/standards-reviewer/notes.md"), 0)
        self.assertEqual(self.run_guard("~/.claude/agent-memory/leek-skills-session-miner/p.md",
                                        agent="leek-skills:session-miner", tool="Edit"), 0)

    def test_other_writes_are_blocked(self):
        self.assertEqual(self.run_guard("/repo/app/Foo.php"), 2)
        self.assertEqual(self.run_guard("/repo/.claude/agent-memory/../../app/Foo.php"), 2)
        self.assertEqual(self.run_guard("/repo/.claude/agent-memory"), 2)
        self.assertEqual(self.run_guard("/repo/.claude/settings.json", tool="search_replace",
                                        agent="leek-skills:finding-verifier"), 2)
        self.assertEqual(self.run_guard(""), 2)

    def test_memory_must_be_this_sessions_own(self):
        # A `.claude/agent-memory` segment somewhere else is not this session's memory.
        self.assertEqual(self.run_guard("/elsewhere/.claude/agent-memory/x.md"), 2)
        self.assertEqual(self.run_guard("/repo/sub/.claude/agent-memory/x.md"), 2)
        # A parent's memory directory is fine: the agent may run from a subdirectory.
        self.assertEqual(self.run_guard("/repo/.claude/agent-memory/x.md", cwd="/repo/app/deep"), 0)
        with tempfile.TemporaryDirectory() as tmp:
            repo = os.path.realpath(tmp)
            memory = os.path.join(repo, ".claude", "agent-memory")
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

    def test_every_memory_agent_is_guarded_or_a_named_writer(self):
        # `memory:` gives an agent Write and Edit even when its `tools:` line has neither.
        # `researcher` writes its findings file, so it is the one agent left unguarded.
        writers = {"researcher"}
        for agent in sorted(GUARD.parent.parent.glob("agents/*.md")):
            frontmatter = agent.read_text().split("---")[1]
            if "\nmemory:" in frontmatter and agent.stem not in writers:
                with self.subTest(agent=agent.stem):
                    self.assertEqual(
                        self.run_guard("/repo/app/Foo.php", agent=f"leek-skills:{agent.stem}"),
                        2,
                        f"{agent.stem} has memory: but is not blocked from writing outside agent-memory",
                    )


if __name__ == "__main__":
    unittest.main()
