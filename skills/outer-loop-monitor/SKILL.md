---
name: outer-loop-monitor
description: Observe an OpenCode planner and subagent loop from the external coordinator without imposing local timeouts or exposing prompt, reasoning, response, or credential content.
---

# Outer Loop Monitor

This Skill belongs only to the workflow repository's external coordinator. It is intentionally outside `.workflow/` and must never be copied by `scripts/init-project.sh` or exposed to inner planner, test-writer, runner, coder, command, or memory Agents.

Use it whenever an outer loop starts or resumes `workflow run` and needs to distinguish provider waiting from a disconnected or failed inner loop.

## Start monitoring

Find the root session without printing configuration:

```bash
workflow session list --format json -n 5
```

Take a metadata-only snapshot:

```bash
python3 skills/outer-loop-monitor/scripts/monitor_inner_loop.py snapshot \
  --session-id <session-id> \
  --project-root <target-project> \
  --run-id <run-id> \
  --expected-artifact <relative-path>
```

For a long-running phase, use the NDJSON watcher. It has no default wall-time limit and never sends signals to OpenCode:

```bash
python3 skills/outer-loop-monitor/scripts/monitor_inner_loop.py watch \
  --session-id <session-id> \
  --project-root <target-project> \
  --run-id <run-id> \
  --expected-artifact <relative-path>
```

## Interpret states

- `ACTIVE` or `TOOL_RUNNING`: the selected session is making progress.
- `DELEGATED`: a child Agent session is active. OpenCode subagents are sessions in the same process, so the absence of an OS child process is not evidence of failure.
- `WAITING_PROVIDER` or `DELEGATED_WAITING_PROVIDER`: the latest assistant step is unfinished and no tool is running. Continue waiting; silence is not a timeout.
- `PROVIDER_TIMEOUT`, `PROVIDER_QUOTA`, `PROVIDER_AUTH`, `PROVIDER_OVERLOAD`, or `PROVIDER_ERROR`: the OpenCode log contains an explicit provider failure for the root or descendant session. Stop retry loops, preserve evidence, and close the phase truthfully.
- `COMPLETED`: verify every expected artifact and phase receipt before accepting success. A completed process with missing artifacts is not a passing phase.

The script reads only session relationships, timestamps, finish metadata, part types, tool status, phase status, artifact metadata, and classified error kinds. It never emits prompt text, reasoning text, model response text, raw log errors, environment variables, or provider configuration.

## External coordinator policy

1. Keep the `workflow run` process handle and root OpenCode session id.
2. Poll the watcher or snapshots while the command is running; report meaningful state changes and periodic heartbeats.
3. Do not terminate on elapsed time or lack of terminal output.
4. Treat explicit provider errors, process exit, user cancellation, and receipt/artifact validation as terminal evidence.
5. After a terminal event, verify the process tree, phase receipt, expected artifacts, and repository diff independently.
