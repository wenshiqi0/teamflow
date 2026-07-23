---
name: memory-capture
description: Capture a verified coding-task outcome through emotional-salience detection, DeepSeek compression, GLM concept extraction and formatting, deterministic validation, and safe Basic Memory apply. Use only after tests and review report PASS; never use direct remember commands for automated task capture.
---

# Memory Capture

Write `.teamflow/runs/task-receipts/<run-id>/receipt.json` with this shape:

```json
{
  "schema_version": 1,
  "kind": "verified-task-receipt",
  "outcome": "PASS",
  "task": "Short task name",
  "summary": "Concise verified outcome",
  "changed_files": ["path"],
  "facts": ["durable fact"],
  "decisions": ["durable decision"],
  "constraints": ["scope or compatibility limit"],
  "risks": ["unverified or live-only risk"],
  "user_signals": [{"id": "signal-001", "text": "concise observable directive or correction"}],
  "evidence": [{"command": "test command", "status": "PASS", "summary": "what it proved"}],
  "related_memory": ["memory permalink recalled and verified during this task"]
}
```

Use concise paraphrased signals, not raw conversation. Never include secrets, full logs, temporary failures, or unsupported claims.

Run:

```bash
teamflow memory-capture --receipt .teamflow/runs/task-receipts/<run-id>/receipt.json
```

The runner performs Emotion -> DeepSeek -> GLM extraction -> GLM formatting serially. It validates lineage and applies only idempotent `create` operations. `update` and `supersede` proposals are recorded in `50-apply.json` without overwriting old notes. Do not call `teamflow memory remember` or `remember-global` as an automated fallback.

Model stages wait for provider queues indefinitely by default. To opt into a local wall-time limit for a specific invocation, set `TEAMFLOW_MODEL_STAGE_TIMEOUT_SECONDS` to a positive integer. Zero, negative, and non-integer values are rejected rather than silently changing behavior.

If an explicitly configured timeout or provider error stops a run after extraction but before formatting, resume only the remaining formal stages:

```bash
teamflow memory-capture --receipt <receipt.json> --resume-formatting <memory-run-id>
```

Use `--resume-run` only when candidates and validation already exist and only apply remains.
