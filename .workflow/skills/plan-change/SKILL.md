---
name: plan-change
description: Convert a software change request into an executable, test-first plan with observable acceptance criteria and a precise agent handoff. Use when planning a feature, bug fix, refactor, migration, or other repository change before implementation begins.
---

# Plan a Change

1. Read repository instructions and inspect the affected code and tests.
2. Restate the requested outcome in observable terms. Separate confirmed facts from assumptions.
3. Define scope, non-goals, compatibility constraints, and failure risks.
4. Write acceptance criteria that a test or deterministic check can prove.
5. Identify the smallest useful test slice and the likely implementation area without prescribing unnecessary code details.
6. Produce the handoff below. Do not edit product or test code.

## Handoff

```text
Goal:
Scope:
Acceptance:
-
Constraints:
-
Initial test target:
Evidence collected:
-
Open questions:
-
```

Reject vague criteria such as "works correctly", "is robust", or "tests pass". Name the input, behavior, and expected observable output.
