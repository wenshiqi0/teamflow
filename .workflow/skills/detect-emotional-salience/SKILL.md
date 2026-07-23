---
name: detect-emotional-salience
description: "Detect communication signals, expression intensity, and durable memory salience without inferring mental health or personality. Use for passive memory prioritization, repeated-correction detection, boundary and preference discovery, and distinguishing transient emotion from low-emotion high-value project knowledge."
---

# Detect Emotional Salience

Classify observable communication signals. Never diagnose an internal psychological state.

Read `references/contract.md` before producing predictions.

## Separation rules

- Score expression intensity independently from memory salience.
- Treat explicit boundaries, corrections, and preferences as potentially durable even when calmly stated.
- Treat urgency, irritation, praise, and punctuation as signals only; they do not prove durable importance.
- Prefer the semantic target over surface tone. Identify what the signal is about.
- Do not store raw conversation as project memory. A promoted result should be a boundary, preference, conflict, or attention marker, not a statement about a person's psychology.
- Do not infer diagnosis, personality, intent beyond the text, or emotional history.

## Input and output behavior

- Read only the supplied input plus this Skill and its contract.
- Produce exactly one prediction for every item ID.
- Use only contract labels and actions.
- Write strict JSON without Markdown fences or commentary.
