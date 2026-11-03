import json
import subprocess
import sys
import unittest
from pathlib import Path

GUARD = Path(__file__).with_name("memory_write_guard.py")


class MemoryWriteGuardTest(unittest.TestCase):
    def run_guard(self, path, agent="leek-skills:standards-reviewer", tool="Write", cwd="/repo"):
        payload = {"tool_name": tool, "tool_input": {"file_path": path}, "cwd": cwd}
        if agent:
            payload["agent_type"] = agent
        return subprocess.run([sys.executable, str(GUARD)], input=json.dumps(payload),
                              text=True, capture_output=True).returncode

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

    def test_other_callers_pass_through(self):
        self.assertEqual(self.run_guard("/repo/app/Foo.php", agent=None), 0)
        self.assertEqual(self.run_guard("/repo/app/Foo.php", agent="leek-skills:researcher"), 0)


if __name__ == "__main__":
    unittest.main()
