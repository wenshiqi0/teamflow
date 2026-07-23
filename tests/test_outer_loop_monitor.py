import json
import sqlite3
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "skills/outer-loop-monitor/scripts/monitor_inner_loop.py"


def create_database(path: Path, include_timeout: bool) -> Path:
    connection = sqlite3.connect(path)
    connection.executescript(
        """
        CREATE TABLE session (
          id TEXT PRIMARY KEY,
          parent_id TEXT,
          agent TEXT,
          time_created INTEGER NOT NULL,
          time_updated INTEGER NOT NULL
        );
        CREATE TABLE message (
          id TEXT PRIMARY KEY,
          session_id TEXT NOT NULL,
          time_created INTEGER NOT NULL,
          time_updated INTEGER NOT NULL,
          data TEXT NOT NULL
        );
        CREATE TABLE part (
          id TEXT PRIMARY KEY,
          message_id TEXT NOT NULL,
          session_id TEXT NOT NULL,
          time_created INTEGER NOT NULL,
          time_updated INTEGER NOT NULL,
          data TEXT NOT NULL
        );
        """
    )
    connection.executemany(
        "INSERT INTO session VALUES (?, ?, ?, ?, ?)",
        [
            ("root", None, "planner", 1000, 9000),
            ("child", "root", "test-writer", 2000, 10000),
        ],
    )
    connection.executemany(
        "INSERT INTO message VALUES (?, ?, ?, ?, ?)",
        [
            (
                "root-message",
                "root",
                1000,
                9000,
                json.dumps({"role": "assistant", "agent": "planner", "finish": None}),
            ),
            (
                "child-message",
                "child",
                2000,
                10000,
                json.dumps({"role": "assistant", "agent": "test-writer", "finish": None}),
            ),
        ],
    )
    connection.executemany(
        "INSERT INTO part VALUES (?, ?, ?, ?, ?, ?)",
        [
            (
                "root-tool",
                "root-message",
                "root",
                8000,
                9000,
                json.dumps(
                    {
                        "type": "tool",
                        "tool": "task",
                        "state": {"status": "running"},
                        "text": "SECRET_PROMPT_SHOULD_NOT_LEAK",
                    }
                ),
            ),
            (
                "child-reasoning",
                "child-message",
                "child",
                9000,
                10000,
                json.dumps(
                    {"type": "reasoning", "text": "SECRET_REASONING_SHOULD_NOT_LEAK"}
                ),
            ),
        ],
    )
    connection.commit()
    connection.close()

    log_path = path.with_suffix(".log")
    if include_timeout:
        log_path.write_text(
            "timestamp=2026-07-23T07:04:05.334Z level=ERROR "
            "session.id=child error=\"The operation timed out. SECRET_LOG_SHOULD_NOT_LEAK\"\n",
            encoding="utf-8",
        )
    else:
        log_path.write_text("", encoding="utf-8")
    return log_path


class OuterLoopMonitorTests(unittest.TestCase):
    def run_snapshot(self, include_timeout: bool) -> tuple[dict, str]:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            database = root / "opencode.db"
            log_path = create_database(database, include_timeout)
            completed = subprocess.run(
                [
                    "python3",
                    str(SCRIPT),
                    "snapshot",
                    "--db",
                    str(database),
                    "--log",
                    str(log_path),
                    "--session-id",
                    "root",
                    "--project-root",
                    str(root),
                    "--waiting-after-seconds",
                    "5",
                    "--now-ms",
                    "20000",
                    "--expected-artifact",
                    ".teamflow/runs/test-patches/example/tests.patch",
                ],
                text=True,
                capture_output=True,
                check=True,
            )
            return json.loads(completed.stdout), completed.stdout

    def test_waiting_child_is_not_treated_as_disconnected(self):
        snapshot, output = self.run_snapshot(include_timeout=False)
        self.assertEqual(snapshot["state"], "DELEGATED_WAITING_PROVIDER")
        child = next(item for item in snapshot["sessions"] if item["id"] == "child")
        self.assertEqual(child["state"], "WAITING_PROVIDER")
        self.assertNotIn("SECRET_PROMPT", output)
        self.assertNotIn("SECRET_REASONING", output)

    def test_timeout_log_overrides_empty_or_waiting_state_without_leaking_log(self):
        snapshot, output = self.run_snapshot(include_timeout=True)
        self.assertEqual(snapshot["state"], "PROVIDER_TIMEOUT")
        child = next(item for item in snapshot["sessions"] if item["id"] == "child")
        self.assertEqual(child["provider_error_kind"], "TIMEOUT")
        self.assertNotIn("SECRET_LOG", output)

    def test_outer_monitor_is_not_part_of_target_installation(self):
        installer = (ROOT / "scripts/init-project.sh").read_text(encoding="utf-8")
        self.assertNotIn("skills/outer-loop-monitor", installer)


if __name__ == "__main__":
    unittest.main()
