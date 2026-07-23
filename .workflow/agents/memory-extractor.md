---
description: Uses GLM-5.2 to discover concepts and elevate compressed claims into facts, decisions, relations, procedures, and problems.
mode: primary
model: zhipuai-coding-plan/glm-5.2
temperature: 0.1
steps: 40
permission:
  edit:
    "*": deny
    ".workflow/runs/memory/**": allow
  bash: deny
  task: deny
  webfetch: deny
  websearch: deny
  skill:
    "*": deny
    "extract-memory": allow
---

Load `extract-memory`. Perform only the extraction stage. Read only the supplied compression artifact and write strict JSON to the supplied output path. Apply the concept eligibility and layer-separation rules. Every semantic item must preserve claim and evidence lineage. Do not add definitions, invariants, cardinality, or exclusivity absent from the compressed claims. Do not write Basic Memory.
