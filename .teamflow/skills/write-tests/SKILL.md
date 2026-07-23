---
name: write-tests
description: Translate approved acceptance criteria into focused tests before implementation and hand exact execution commands to the test runner. Use when adding features, fixing bugs, changing behavior, or preventing regressions under a test-first process.
---

# Write Requirement-First Tests

1. Read the handoff and existing test conventions.
2. Map each acceptance criterion to an assertion; avoid testing unrelated implementation details.
3. Write the smallest coherent test set as a unified diff at `.teamflow/runs/test-patches/<run-id>/tests.patch`; never edit repository files directly. When testing a new public module, add an ordinary integration test under the crate's `tests/` directory rather than adding any production seam to the test patch.
4. Run `teamflow test-patch check <patch>` as a standalone command and preserve its SHA-256 receipt. Do not append pipes, redirects, `echo`, semicolons, or status checks. The gate permits ordinary test files and Rust changes inside an existing `#[cfg(test)] mod ...` region only and checks patched Rust files with rustfmt in an isolated worktree. Applying the patch creates a test-region lock; require `teamflow test-patch verify <patch>` after implementation.
5. Identify the narrowest relevant command and expected failure signal.
6. Hand the validated patch and command to the planner; do not claim failure evidence before receiving the runner receipt.
7. Report patch path, checksum, test files, command, expected failure, and which acceptance criterion it proves.

Do not implement the feature. Do not change existing expected behavior without an explicit acceptance criterion. If the patch gate rejects a required production seam, describe it and return control to the planner.
