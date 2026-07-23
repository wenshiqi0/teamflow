#!/usr/bin/env python3
import argparse
import json
import os
from pathlib import Path


def fail(message: str) -> None:
    raise SystemExit(f"error: {message}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Capture a verified task through the curated memory pipeline")
    parser.add_argument("--receipt", required=True)
    parser.add_argument("--run-id")
    parser.add_argument("--resume-run")
    parser.add_argument("--resume-formatting")
    args = parser.parse_args()
    project = Path.cwd().resolve()
    receipt = Path(args.receipt).expanduser().resolve()
    allowed = (project / ".workflow" / "runs" / "task-receipts").resolve()
    if not receipt.is_file() or allowed not in receipt.parents:
        fail("receipt must be below .workflow/runs/task-receipts/")
    try:
        value = json.loads(receipt.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        fail(f"invalid receipt JSON: {exc}")
    related = value.get("related_memory", [])
    if not isinstance(related, list) or not all(isinstance(item, str) for item in related):
        fail("related_memory must be an array of memory permalinks")
    runner = project / ".workflow" / "skills" / "extract-memory" / "scripts" / "run_pipeline.py"
    if args.resume_run:
        os.execvp("python3", ["python3", str(runner), "--resume-apply", args.resume_run])
    if args.resume_formatting:
        os.execvp(
            "python3",
            ["python3", str(runner), "--resume-formatting", args.resume_formatting, "--apply"],
        )
    command = [
        "python3", str(runner), "--capture-file", str(receipt), "--apply",
    ]
    if args.run_id:
        command.extend(["--run-id", args.run_id])
    for source in related:
        command.extend(["--source", source])
    os.execvp(command[0], command)


if __name__ == "__main__":
    main()
