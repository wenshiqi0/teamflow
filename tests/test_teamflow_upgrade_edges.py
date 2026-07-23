import json
import os
import subprocess
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BOOTSTRAP = ROOT / "scripts/bootstrap.sh"
INITIALIZER = ROOT / "scripts/init-project.sh"
PHASE_STATE = ROOT / ".teamflow/skills/plan-change/scripts/phase_state.py"


def write_executable(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    path.chmod(0o755)


class UpgradeHarness:
    def __init__(self, root: Path):
        self.root = root
        self.home = root / "home"
        self.bin = root / "fake-bin"
        self.launchers = root / "launchers"
        self.uv_bin = root / "uv-bin"
        self.tool_log = root / "tools.log"
        for path in (self.home, self.bin, self.launchers, self.uv_bin):
            path.mkdir(parents=True)
        write_executable(
            self.bin / "opencode",
            """#!/bin/sh
if [ "${1:-}" = "--version" ]; then
  printf '1.18.4\\n'
elif [ "${1:-}" = "debug" ] && [ "${2:-}" = "skill" ]; then
  printf 'plan-change\\nbasic-memory-cli\\n'
fi
exit 0
""",
        )
        write_executable(
            self.bin / "npm",
            """#!/bin/sh
if [ "${1:-}" = "--fetch-timeout=15000" ]; then
  printf '1.18.4\\n'
fi
exit 0
""",
        )
        write_executable(
            self.bin / "uv",
            """#!/bin/sh
if [ "${1:-} ${2:-} ${3:-}" = "tool dir --bin" ]; then
  printf '%s\\n' "${FAKE_UV_BIN:?}"
fi
exit 0
""",
        )
        write_executable(
            self.bin / "basic-memory",
            """#!/bin/sh
printf '%s\\n' "$*" >> "${FAKE_TOOL_LOG:?}"
if [ "${1:-}" = "--version" ]; then
  printf 'basic-memory 0.22.1\\n'
elif [ "${1:-} ${2:-}" = "project info" ]; then
  exit 1
elif [ "${1:-}" = "status" ]; then
  printf '{}\\n'
fi
exit 0
""",
        )

    def environment(self) -> dict[str, str]:
        env = os.environ.copy()
        for key in list(env):
            if key.startswith(("TEAMFLOW_", "WORKFLOW_", "OPENCODE_WORKFLOW_")):
                env.pop(key)
        env.update(
            {
                "HOME": str(self.home),
                "PATH": f"{self.bin}:{env['PATH']}",
                "TEAMFLOW_BIN_DIR": str(self.launchers),
                "FAKE_UV_BIN": str(self.uv_bin),
                "FAKE_TOOL_LOG": str(self.tool_log),
            }
        )
        return env

    def run_bootstrap(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(BOOTSTRAP)],
            cwd=ROOT,
            env=self.environment(),
            text=True,
            capture_output=True,
            timeout=30,
        )

    def run_initializer(self, project: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(INITIALIZER), str(project)],
            cwd=ROOT,
            env=self.environment(),
            text=True,
            capture_output=True,
            timeout=30,
        )

    def new_project(self, name: str) -> Path:
        project = self.root / name
        project.mkdir()
        subprocess.run(["git", "init", "-q", str(project)], check=True)
        return project


class BootstrapUpgradeTests(unittest.TestCase):
    def test_default_upgrade_copies_legacy_env_without_overwriting_or_printing_it(self):
        with tempfile.TemporaryDirectory() as directory:
            harness = UpgradeHarness(Path(directory))
            legacy = harness.home / ".workflow/.env"
            current = harness.home / ".teamflow/.env"
            legacy.parent.mkdir(parents=True)
            old_marker = "legacy-credential-marker"
            legacy.write_text(old_marker, encoding="utf-8")

            migrated = harness.run_bootstrap()
            self.assertEqual(migrated.returncode, 0, migrated.stderr)
            self.assertEqual(current.read_text(encoding="utf-8"), old_marker)
            self.assertTrue(legacy.is_file())
            self.assertNotIn(old_marker, migrated.stdout + migrated.stderr)

            new_marker = "new-credential-marker"
            current.write_text(new_marker, encoding="utf-8")
            legacy.write_text("different-legacy-marker", encoding="utf-8")
            repeated = harness.run_bootstrap()
            self.assertEqual(repeated.returncode, 0, repeated.stderr)
            self.assertEqual(current.read_text(encoding="utf-8"), new_marker)
            self.assertNotIn(new_marker, repeated.stdout + repeated.stderr)
            self.assertNotIn("different-legacy-marker", repeated.stdout + repeated.stderr)

    def test_bootstrap_removes_only_managed_legacy_launcher(self):
        cases = (
            ("managed", "#!/bin/sh\n# agent-workflow-launcher\n", False),
            ("unrelated", "#!/bin/sh\n# user-owned launcher\n", True),
        )
        for name, content, should_remain in cases:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                harness = UpgradeHarness(Path(directory))
                legacy = harness.launchers / "workflow"
                legacy.write_text(content, encoding="utf-8")
                legacy.chmod(0o755)
                completed = harness.run_bootstrap()
                self.assertEqual(completed.returncode, 0, completed.stderr)
                self.assertEqual(legacy.exists(), should_remain)
                if should_remain:
                    self.assertEqual(legacy.read_text(encoding="utf-8"), content)
                    self.assertIn("warning", completed.stderr.lower())
                self.assertTrue((harness.launchers / "teamflow").is_file())


class InitializerUpgradeTests(unittest.TestCase):
    def test_initializer_removes_only_managed_legacy_launcher(self):
        cases = (
            ("managed", "#!/bin/sh\n# agent-workflow-launcher\n", False),
            ("unrelated", "#!/bin/sh\n# user-owned launcher\n", True),
        )
        for name, content, should_remain in cases:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                harness = UpgradeHarness(Path(directory))
                project = harness.new_project("target")
                legacy = harness.launchers / "workflow"
                legacy.write_text(content, encoding="utf-8")
                legacy.chmod(0o755)
                completed = harness.run_initializer(project)
                self.assertEqual(completed.returncode, 0, completed.stderr)
                self.assertEqual(legacy.exists(), should_remain)
                if should_remain:
                    self.assertEqual(legacy.read_text(encoding="utf-8"), content)
                    self.assertIn("warning", completed.stderr.lower())
                self.assertTrue((harness.launchers / "teamflow").is_file())


class RemainingNamespaceEdgeTests(unittest.TestCase):
    def test_memory_compare_and_monitor_examples_use_teamflow_command(self):
        compare = (
            ROOT / ".teamflow/experiments/scripts/compare_stage.py"
        ).read_text(encoding="utf-8")
        self.assertIn('runtime / "bin" / "teamflow"', compare)
        self.assertNotIn('runtime / "bin" / "workflow"', compare)

        monitor = (ROOT / "skills/outer-loop-monitor/SKILL.md").read_text(
            encoding="utf-8"
        )
        self.assertIn("teamflow session list --format json -n 5", monitor)
        self.assertNotIn("workflow session list --format json -n 5", monitor)

    def test_teamflow_phase_timeout_is_primary_and_workflow_is_fallback(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            phase = project / ".teamflow/runs/code/example/phases/one.json"
            phase.parent.mkdir(parents=True)
            phase.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "run_id": "example",
                        "phase": "one",
                        "status": "RUNNING",
                        "started_at": datetime(2020, 1, 1, tzinfo=timezone.utc).isoformat(),
                    }
                ),
                encoding="utf-8",
            )
            current = project / ".teamflow/runs/code/example/current.json"
            current.write_text(
                json.dumps({"phase": "one", "path": str(phase)}), encoding="utf-8"
            )
            base_env = os.environ.copy()
            base_env.pop("TEAMFLOW_PHASE_TIMEOUT_SECONDS", None)
            base_env.pop("WORKFLOW_PHASE_TIMEOUT_SECONDS", None)

            primary_env = base_env | {
                "TEAMFLOW_PHASE_TIMEOUT_SECONDS": "9999999999",
                "WORKFLOW_PHASE_TIMEOUT_SECONDS": "1",
            }
            primary = subprocess.run(
                ["python3", str(PHASE_STATE), "status", "--run-id", "example"],
                cwd=project,
                env=primary_env,
                text=True,
                capture_output=True,
                check=True,
            )
            self.assertIs(json.loads(primary.stdout)["stale"], False)

            fallback_env = base_env | {"WORKFLOW_PHASE_TIMEOUT_SECONDS": "1"}
            fallback = subprocess.run(
                ["python3", str(PHASE_STATE), "status", "--run-id", "example"],
                cwd=project,
                env=fallback_env,
                text=True,
                capture_output=True,
                check=True,
            )
            self.assertIs(json.loads(fallback.stdout)["stale"], True)
