# Workflow Agent Instructions

This repository defines and evolves a multi-agent coding workflow.

## Roles

- `planner` uses GLM-5.2 and owns requirement analysis, acceptance criteria, delegation, and the final summary.
- `test-writer` uses GLM-5.2 and owns requirement-focused test design and final assertion/diff review.
- `test-runner` owns test execution and structured failure receipts without file edits.
- `coder` uses Kimi K3, focuses on product-code implementation, and must not redefine the acceptance criteria.
- `command` uses MiMo 2.5 Pro for explicit shell, Git, and GitHub operations that need semantic interpretation but no code edits or multi-agent planning.
- `memory-compressor`, `memory-extractor`, and `memory-formatter` form the curated serial memory pipeline; GLM-5.2 owns both extraction and final formatting. Models may write only below `.workflow/runs/memory/` and must never write Basic Memory directly.

Use this sequence unless the request is documentation-only or cannot be tested:

1. Inspect the repository and clarify the observable outcome.
2. Recall relevant cross-project memory and verify it against the current repository.
3. Write a plan with explicit acceptance criteria.
4. Ask `test-writer` to add focused tests and provide exact execution commands.
5. Ask `test-runner` to execute them and return a structured failure receipt.
6. Ask `coder` to implement the smallest coherent change.
7. Ask `test-runner` to execute focused and relevant regression checks.
8. Ask `test-writer` to review the assertions and final diff.
9. Persist only verified, reusable findings after execution and review pass.
10. Report changed files, execution receipts, memory written, and remaining risks.

If test-first execution is skipped, state the concrete reason in the final report.

## Handoff contract

Every handoff between agents must contain:

- Goal: one observable outcome.
- Scope: files or components that may change.
- Acceptance: verifiable criteria.
- Constraints: compatibility, security, and non-goals.
- Evidence: commands and results already obtained.
- Open questions: unresolved facts that can affect implementation.

Do not hand off vague requests such as "fix it" or "make tests pass".

## Engineering rules

- Read the repository's existing instructions before editing.
- Preserve user changes and avoid unrelated rewrites.
- Never expose, print, or commit API keys and secrets.
- Do not weaken assertions merely to make a test pass.
- Prefer focused tests first, then the repository's broader lint, typecheck, test, and build gates.
- Do not run `git push`, destructive reset, or workspace-cleaning commands unless the user explicitly requests them.
- Record workflow run artifacts only below `.workflow/runs/`.
- Record each long-running code phase with `workflow phase`; explicit provider timeout, authentication, quota, overload, transport failure, or user cancellation ends that phase as `BLOCKED` instead of silently restarting it. Silence and elapsed wall time alone are not failures.
- Run `workflow source-check` after code edits to reject accidental non-printing control bytes.
- Keep target-project integration limited to the standard `.workflow/` entry in `.gitignore`; do not scatter runtime files across the repository root.
- Keep Agent prompts and Skills concise; put shared policy here instead of duplicating it.

## External loop monitoring

External coordinators must load `skills/outer-loop-monitor/SKILL.md` when starting or resuming an inner `workflow run`. Use its script to observe the OpenCode root session, descendant Agent sessions, tool status, classified provider errors, phase receipt, and expected artifacts. Do not infer disconnection from missing terminal output or the absence of an OS child process; OpenCode subagents are child sessions inside the same process.

The monitor is external-only. Keep it below `skills/outer-loop-monitor/`; never add it to `.workflow/`, `scripts/init-project.sh`, or target-project Agent instructions. It must not expose prompt, reasoning, response, raw error, configuration, or credential content, and it must never terminate the inner loop on its own.

## Cross-project memory

Basic Memory is the fully local shared memory backend. This repository contains only workflow definitions and initialization logic; it is not a working-project or memory-data repository. Cross-project runtime memory lives under `~/.workflow/memory/`: Markdown source files in `knowledge/`, and Basic Memory config, SQLite index, logs, and optional FastEmbed cache in `state/`. Do not start or configure MCP, cloud sync, accounts, or API keys. The planner owns all memory access through `workflow memory`; implementation and test agents receive relevant context through their handoffs.

- Recall at the start of a task, but validate every recalled claim against current files and commands.
- Store only durable decisions, reproducible fixes, repository conventions, and verified commands.
- Include the reason and evidence in the memory text; avoid context-free conclusions.
- Use `remember` for repository-specific findings and `remember-global` only for practices proven reusable across projects.
- Never store secrets, credentials, private user data, raw conversations, full logs, unverified hypotheses, or temporary failures.
- Do not write memory when verification fails or remains blocked.
- Correct stale memory by writing the new verified fact with explicit supersession context; do not silently rely on the old entry.

## Maintaining this repository

When changing Agent models, permissions, workflow order, environment variables, or scripts:

1. Update the implementation.
2. Update README usage and architecture notes.
3. Run `./scripts/doctor.sh`.
4. Confirm all project Agents and Skills appear in `workflow debug` output.
5. Dry-run `./scripts/init-project.sh` against a disposable Git project when installable files change.
6. Keep the four Basic Memory Skills CLI-only; use `./scripts/update-basic-memory-skills.sh` to prepare upstream refreshes.
