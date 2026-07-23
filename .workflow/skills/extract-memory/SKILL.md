---
name: extract-memory
description: "Transform verified raw memory into auditable atomic candidates through a four-stage pipeline: MiMo emotional-salience detection, DeepSeek compression, then GLM concept extraction and schema normalization. Use for verified memory capture, long-note cleanup, concept discovery, deduplication planning, and preparing create/update/supersede/skip operations without writing Basic Memory."
---

# Extract Memory

Treat memory extraction as a staged semantic transformation, not summarization.

## Pipeline

1. `emotion detection`: detect observable signals and memory salience without diagnosis. The result is attention metadata, not evidence.
2. `compression`: remove repetition and task narration while preserving claims, evidence, conflicts, and exclusions.
3. `extraction`: discover concepts and boundaries, then separate facts, decisions, relations, procedures, and problems.
4. `formatting`: normalize the extracted knowledge into atomic memory candidates and proposed operations.
5. `validation`: use the deterministic runner to validate JSON shape and lineage. Never repair semantic gaps by invention.

Read `references/contracts.md` for the stage contract before producing an artifact. The runner provides the input and output paths.

## Semantic rules

- Keep one claim per fact or decision.
- Keep a claim only when knowing it can change a future engineering decision. Move proof of a claim into evidence; do not turn test counts or task completion into knowledge claims.
- Require every fact to belong to a concept.
- Treat concepts as stable domain nouns with explicit boundaries. Files, commands, test names, incidents, and procedures are not concepts.
- Express relations as subject-predicate-object.
- Keep reusable methods in procedures, not facts.
- Preserve evidence references through every stage.
- Copy URLs, environment-variable names, model IDs, document IDs, table IDs, and other opaque identifiers byte-for-byte. Never reconstruct them from memory.
- Never add a concept property, invariant, or cardinality that is absent from the upstream claims.
- Mark uncertainty and contradictions; do not reconcile them without evidence.
- Use emotional salience only to avoid prematurely discarding a semantic target. High
  intensity never proves truth, durability, or importance; calm constraints can still
  be highly salient.
- Treat receipt `user_signals` as attention metadata, not evidence. Promote a signal
  target only when facts, decisions, or constraints independently support it. Exclude
  one-run branch handling and other transient execution instructions.
- When a newer verification receipt contradicts an old note, record the conflict and treat the old statement as stale rather than merging both as current truth.
- Separate repository-specific knowledge from cross-project practice.
- Exclude raw logs, duplicated prose, credentials, transient failures, and task chronology.
- During formatting, distinguish legacy `workflow_finding` notes from atomic
  `workflow_memory` notes. Equivalent atomic knowledge is `skip`, stronger evidence
  for the same atomic statement is `update`, and atomic sources remain `retain`.
  Rephrasing never justifies `create` or `supersede`.
- For one verified task, target 3-5 and propose at most 8 new memories. Prefer a small set of
  durable decisions, invariants, procedures, and risks over code-symbol
  definitions, duplicated concept/fact pairs, relation fragments, test counts,
  file lists, or task narration. Group knowledge by future decision value.
- Never write Basic Memory from this skill. Only write the requested artifact below `.workflow/runs/memory/`.

## Safety

- Read only the stage inputs supplied by the runner. During compression, read every source file explicitly listed by the evidence capsule. The formatting stage may read the evidence capsule solely to compare candidates with existing source memories and current verification receipts.
- Do not inspect product code, other memories, conversation history, or another stage's hidden inputs.
- Do not call tools except reading the supplied input and writing the requested output.
- Output strict JSON with no Markdown fence or commentary.
