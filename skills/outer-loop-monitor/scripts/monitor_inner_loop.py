#!/usr/bin/env python3
"""Observe an OpenCode inner loop without reading model or prompt content."""

from __future__ import annotations

import argparse
import hashlib
import json
import sqlite3
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


ERROR_PATTERNS = (
    ("AUTH", ("invalid authentication", "invalid api key", "unauthorized", "status code 401")),
    (
        "QUOTA",
        (
            "余额不足",
            "无可用资源包",
            "insufficient balance",
            "insufficient quota",
            "quota exceeded",
        ),
    ),
    ("OVERLOAD", ("overload", "rate limit", "too many requests", "status code 429")),
    ("TIMEOUT", ("timed out", "timeout", "deadline exceeded")),
)


def parse_json(value: str) -> dict:
    try:
        parsed = json.loads(value)
    except (TypeError, json.JSONDecodeError):
        return {}
    return parsed if isinstance(parsed, dict) else {}


def default_database_path() -> Path:
    completed = subprocess.run(
        ["opencode", "db", "path"], text=True, capture_output=True, check=False
    )
    candidate = completed.stdout.strip()
    if completed.returncode == 0 and candidate:
        return Path(candidate)
    return Path.home() / ".local/share/opencode/opencode.db"


def session_family(connection: sqlite3.Connection, root_id: str) -> list[sqlite3.Row]:
    return connection.execute(
        """
        WITH RECURSIVE family(id, parent_id, agent, time_created, time_updated) AS (
          SELECT id, parent_id, agent, time_created, time_updated
          FROM session WHERE id = ?
          UNION ALL
          SELECT child.id, child.parent_id, child.agent,
                 child.time_created, child.time_updated
          FROM session child JOIN family parent ON child.parent_id = parent.id
        )
        SELECT * FROM family ORDER BY time_created, id
        """,
        (root_id,),
    ).fetchall()


def latest_message(connection: sqlite3.Connection, session_id: str) -> tuple[dict, int | None]:
    rows = connection.execute(
        "SELECT data, time_updated FROM message WHERE session_id = ? ORDER BY time_updated DESC",
        (session_id,),
    ).fetchall()
    for row in rows:
        data = parse_json(row["data"])
        if data.get("role") == "assistant":
            return data, row["time_updated"]
    return {}, None


def part_metadata(connection: sqlite3.Connection, session_id: str) -> tuple[dict, int | None, bool]:
    rows = connection.execute(
        "SELECT data, time_updated FROM part WHERE session_id = ? ORDER BY time_updated DESC",
        (session_id,),
    ).fetchall()
    latest: dict = {}
    latest_updated: int | None = None
    tool_running = False
    for index, row in enumerate(rows):
        data = parse_json(row["data"])
        if index == 0:
            latest = {
                "type": data.get("type"),
                "tool": data.get("tool"),
                "tool_status": (data.get("state") or {}).get("status")
                if isinstance(data.get("state"), dict)
                else None,
            }
            latest_updated = row["time_updated"]
        if data.get("type") == "tool" and isinstance(data.get("state"), dict):
            if data["state"].get("status") == "running":
                tool_running = True
    return latest, latest_updated, tool_running


def classify_error(line: str) -> str:
    lowered = line.lower()
    for kind, patterns in ERROR_PATTERNS:
        if any(pattern in lowered for pattern in patterns):
            return kind
    return "ERROR"


def log_errors(log_path: Path | None, session_ids: set[str]) -> dict[str, dict]:
    if log_path is None or not log_path.is_file():
        return {}
    errors: dict[str, dict] = {}
    with log_path.open("r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            if "level=ERROR" not in line:
                continue
            session_id = next(
                (item for item in session_ids if f"session.id={item}" in line), None
            )
            if session_id is None:
                continue
            timestamp = None
            for field in line.split():
                if field.startswith("timestamp="):
                    timestamp = field.removeprefix("timestamp=")
                    break
            errors[session_id] = {
                "kind": classify_error(line),
                "timestamp": timestamp,
            }
    return errors


def session_state(
    *,
    finish: object,
    tool_running: bool,
    last_activity_ms: int,
    now_ms: int,
    waiting_after_ms: int,
    error_kind: str | None,
) -> str:
    if error_kind:
        return f"PROVIDER_{error_kind}"
    if tool_running:
        return "TOOL_RUNNING"
    if finish is None:
        if now_ms - last_activity_ms >= waiting_after_ms:
            return "WAITING_PROVIDER"
        return "ACTIVE"
    if finish == "tool-calls":
        return "ACTIVE"
    return "COMPLETED"


def artifact_metadata(project_root: Path, value: str) -> dict:
    requested = Path(value)
    path = requested if requested.is_absolute() else project_root / requested
    result = {"path": value, "exists": path.is_file()}
    if path.is_file():
        payload = path.read_bytes()
        result.update({"size": len(payload), "sha256": hashlib.sha256(payload).hexdigest()})
    return result


def phase_metadata(project_root: Path, run_id: str | None) -> dict | None:
    if not run_id:
        return None
    current_path = project_root / ".teamflow/runs/code" / run_id / "current.json"
    if not current_path.is_file():
        return {"run_id": run_id, "status": "MISSING"}
    current = parse_json(current_path.read_text(encoding="utf-8"))
    phase_path = current.get("path")
    if not isinstance(phase_path, str):
        return {"run_id": run_id, "status": "INVALID_CURRENT"}
    receipt_path = Path(phase_path)
    if not receipt_path.is_absolute():
        receipt_path = project_root / receipt_path
    if not receipt_path.is_file():
        return {"run_id": run_id, "phase": current.get("phase"), "status": "MISSING_RECEIPT"}
    receipt = parse_json(receipt_path.read_text(encoding="utf-8"))
    return {
        "run_id": run_id,
        "phase": receipt.get("phase"),
        "owner": receipt.get("owner"),
        "status": receipt.get("status"),
        "started_at": receipt.get("started_at"),
        "finished_at": receipt.get("finished_at"),
    }


def build_snapshot(args: argparse.Namespace) -> dict:
    database = Path(args.db).expanduser().resolve()
    connection = sqlite3.connect(f"file:{database}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    try:
        family = session_family(connection, args.session_id)
        if not family:
            raise SystemExit(f"error: OpenCode session not found: {args.session_id}")
        ids = {row["id"] for row in family}
        errors = log_errors(Path(args.log).expanduser() if args.log else None, ids)
        sessions = []
        for row in family:
            message, message_updated = latest_message(connection, row["id"])
            part, part_updated, tool_running = part_metadata(connection, row["id"])
            last_activity = max(
                value
                for value in (row["time_updated"], message_updated, part_updated)
                if value is not None
            )
            error = errors.get(row["id"])
            sessions.append(
                {
                    "id": row["id"],
                    "parent_id": row["parent_id"],
                    "agent": row["agent"] or message.get("agent"),
                    "state": session_state(
                        finish=message.get("finish"),
                        tool_running=tool_running,
                        last_activity_ms=last_activity,
                        now_ms=args.now_ms,
                        waiting_after_ms=args.waiting_after_seconds * 1000,
                        error_kind=error["kind"] if error else None,
                    ),
                    "created_at_ms": row["time_created"],
                    "updated_at_ms": row["time_updated"],
                    "last_activity_at_ms": last_activity,
                    "latest_finish": message.get("finish"),
                    "latest_part_type": part.get("type"),
                    "latest_tool": part.get("tool"),
                    "latest_tool_status": part.get("tool_status"),
                    "provider_error_kind": error["kind"] if error else None,
                    "provider_error_at": error["timestamp"] if error else None,
                }
            )
    finally:
        connection.close()

    descendants = [item for item in sessions if item["id"] != args.session_id]
    provider_failure = next(
        (item["state"] for item in reversed(sessions) if item["state"].startswith("PROVIDER_")),
        None,
    )
    if provider_failure:
        state = provider_failure
    elif any(item["state"] == "WAITING_PROVIDER" for item in descendants):
        state = "DELEGATED_WAITING_PROVIDER"
    elif any(item["state"] in {"ACTIVE", "TOOL_RUNNING"} for item in descendants):
        state = "DELEGATED"
    else:
        state = sessions[0]["state"]

    project_root = Path(args.project_root).expanduser().resolve()
    return {
        "schema_version": 1,
        "observed_at": datetime.fromtimestamp(
            args.now_ms / 1000, tz=timezone.utc
        ).isoformat(),
        "root_session_id": args.session_id,
        "state": state,
        "phase": phase_metadata(project_root, args.run_id),
        "expected_artifacts": [
            artifact_metadata(project_root, value) for value in args.expected_artifact
        ],
        "sessions": sessions,
    }


def add_observation_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--session-id", required=True)
    parser.add_argument("--project-root", default=".")
    parser.add_argument("--db", default=str(default_database_path()))
    parser.add_argument(
        "--log", default=str(Path.home() / ".local/share/opencode/log/opencode.log")
    )
    parser.add_argument("--run-id")
    parser.add_argument("--expected-artifact", action="append", default=[])
    parser.add_argument("--waiting-after-seconds", type=int, default=30)
    parser.add_argument("--now-ms", type=int, default=None, help=argparse.SUPPRESS)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    snapshot_parser = commands.add_parser("snapshot", help="print one JSON snapshot")
    add_observation_arguments(snapshot_parser)
    watch_parser = commands.add_parser("watch", help="emit changed snapshots and heartbeats as NDJSON")
    add_observation_arguments(watch_parser)
    watch_parser.add_argument("--interval-seconds", type=float, default=5.0)
    watch_parser.add_argument("--heartbeat-seconds", type=float, default=30.0)
    watch_parser.add_argument("--max-snapshots", type=int)
    args = parser.parse_args()

    if args.waiting_after_seconds <= 0:
        parser.error("--waiting-after-seconds must be positive")
    if args.now_ms is None:
        args.now_ms = int(time.time() * 1000)

    if args.command == "snapshot":
        print(json.dumps(build_snapshot(args), ensure_ascii=False, sort_keys=True))
        return 0

    emitted = 0
    last_fingerprint = None
    last_emitted_at = 0.0
    try:
        while True:
            args.now_ms = int(time.time() * 1000)
            snapshot = build_snapshot(args)
            fingerprint = json.dumps(
                {key: value for key, value in snapshot.items() if key != "observed_at"},
                ensure_ascii=False,
                sort_keys=True,
            )
            now = time.monotonic()
            if fingerprint != last_fingerprint or now - last_emitted_at >= args.heartbeat_seconds:
                print(json.dumps(snapshot, ensure_ascii=False, sort_keys=True), flush=True)
                last_fingerprint = fingerprint
                last_emitted_at = now
                emitted += 1
                if args.max_snapshots is not None and emitted >= args.max_snapshots:
                    return 0
            time.sleep(args.interval_seconds)
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    sys.exit(main())
