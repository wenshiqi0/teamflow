---
name: memory-notes
description: Write and maintain structured Basic Memory notes through the local CLI. Use when creating durable decisions, verified findings, observations, relations, or improving existing knowledge notes.
---

# Memory Notes

Load `basic-memory-cli` first. Use only local CLI commands and project `workflow`.

## Note structure

Write complete Markdown prose followed by queryable observations and optional relations:

```markdown
# Authentication Decision

Use short-lived access tokens and rotating refresh tokens.

## Observations

- [decision] Access tokens expire after 15 minutes.
- [constraint] Refresh tokens rotate after every use.
- [evidence] Integration test auth-refresh passed on 2026-07-21.

## Relations

- implements [[Authentication Architecture]]
- depends_on [[Identity Provider]]
```

Use semantic observation categories such as `decision`, `fact`, `requirement`, `constraint`, `evidence`, and `risk`. Use wiki-links for meaningful graph relations.

## Workflow

1. Search before writing:

   ```bash
   BASIC_MEMORY_SEMANTIC_SEARCH_ENABLED=false basic-memory tool search-notes "authentication decision" --project workflow --local
   ```

2. Read the closest existing note:

   ```bash
   basic-memory tool read-note "memory://architecture/authentication" --include-frontmatter --project workflow --local
   ```

3. Update a matching note instead of duplicating it:

   ```bash
   basic-memory tool edit-note "memory://architecture/authentication" --operation append --content "- [evidence] Refresh rotation test passed." --project workflow --local
   ```

4. Create a note only when no matching entity exists. Pass multiline bodies through stdin:

   ```bash
   printf '%s\n' '# Authentication Decision' '' 'Use rotating refresh tokens.' '' '## Observations' '' '- [decision] Rotate refresh tokens after every use.' | basic-memory tool write-note --title "Authentication Decision" --folder architecture --type decision --tags "auth,architecture" --project workflow --local
   ```

5. Traverse relations after writing:

   ```bash
   basic-memory tool build-context "memory://architecture/authentication" --depth 2 --timeframe 30d --project workflow --local
   ```

## Rules

- Preserve source, reason, evidence, and date.
- Store verified durable knowledge, not raw logs or chat transcripts.
- Never store secrets, credentials, private data, or unverified guesses.
- Prefer updating one authoritative note over creating near-duplicates.
- Use `--overwrite` only when intentionally replacing the entire existing note.
- Do not delete notes without explicit user authorization.
