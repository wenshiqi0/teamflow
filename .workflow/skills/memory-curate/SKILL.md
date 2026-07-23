---
name: memory-curate
description: Curate the local Basic Memory knowledge graph through CLI commands. Use to find duplicates, repair sparse notes, add confirmed relations, normalize tags, and create topic hubs.
---

# Memory Curate

Load `basic-memory-cli` first and operate only on the local `workflow` project.

## Audit

List recent activity and broad search results:

```bash
basic-memory tool recent-activity --timeframe 30d --page-size 50 --project workflow --local
BASIC_MEMORY_SEMANTIC_SEARCH_ENABLED=false basic-memory tool search-notes "*" --page-size 100 --project workflow --local
```

Check candidate notes in full:

```bash
basic-memory tool read-note "memory://<note-permalink>" --include-frontmatter --project workflow --local
```

Look for:

- duplicate notes covering the same entity;
- observations without provenance or evidence;
- inconsistent tags or folders;
- isolated notes that should relate to an existing topic;
- stale facts contradicted by newer verified evidence.

## Improve

Append a confirmed relation or observation:

```bash
basic-memory tool edit-note "memory://<note-permalink>" --operation append --content $'\n## Relations\n\n- depends_on [[Shared Runtime]]' --project workflow --local
```

Replace a stale section precisely:

```bash
basic-memory tool edit-note "memory://<note-permalink>" --operation replace_section --section "## Observations" --content $'## Observations\n\n- [fact] Current verified fact.\n- [evidence] Verification command passed.' --project workflow --local
```

Create a hub only when it improves navigation:

```bash
printf '%s\n' '# Authentication Hub' '' '## Relations' '' '- includes [[Token Rotation]]' '- includes [[Identity Provider]]' | basic-memory tool write-note --title "Authentication Hub" --folder hubs --type hub --tags "hub,authentication" --project workflow --local
```

Verify graph context afterward:

```bash
basic-memory tool build-context "memory://hubs/authentication-hub" --depth 2 --timeframe 365d --project workflow --local
```

## Safety

- Propose destructive consolidation before applying it.
- Never delete a note without explicit user authorization.
- Preserve stronger provenance and richer verified context when merging duplicates.
- Do not invent relations merely to make the graph denser.
- Re-run search and context commands after curation.
