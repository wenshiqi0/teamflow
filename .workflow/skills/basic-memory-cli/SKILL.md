---
name: basic-memory-cli
description: Use Basic Memory as a fully local cross-project knowledge store through its CLI, without MCP or cloud services. Use when an agent needs to recall prior work, read or build context from memory URLs, inspect recent activity, or store a verified reusable finding.
---

# Basic Memory CLI

Use `basic-memory tool ... --local` for all operations. Treat this Git repository as an initializer only. Keep the shared cross-project runtime under `~/.workflow/memory/`, with Markdown in `knowledge/` and Basic Memory config, SQLite, logs, and cache in `state/`. Use project `workflow` unless `WORKFLOW_MEMORY_PROJECT` explicitly selects another shared local project.

## Workflow wrapper

The Planner has intentionally narrow shell permission. In this repository, prefer the safe wrapper:

```bash
workflow memory recall "task keywords"
workflow memory remember "verified repository finding with evidence"
workflow memory remember-global "verified reusable finding with evidence"
workflow memory read "memory://note-permalink"
workflow memory context "memory://topic/*"
workflow memory list
workflow memory status
```

Recall at task start. Treat results as leads and verify them against the current repository. `remember` and `remember-global` are manual operations only. Automated coding-task capture must create a verified-task receipt and run `workflow memory-capture`; the Planner is intentionally denied direct remember permission.

## CLI translation

Official Basic Memory Skills describe MCP-style tool names. Translate them as follows:

| Skill operation | Local CLI |
| --- | --- |
| `search_notes` | `basic-memory tool search-notes` |
| `write_note` | `basic-memory tool write-note` |
| `read_note` | `basic-memory tool read-note` |
| `build_context` | `basic-memory tool build-context` |
| `recent_activity` | `basic-memory tool recent-activity` |
| `list_memory_projects` | `basic-memory tool list-projects` |

For direct CLI use, first bind Basic Memory to the shared Home directory, then append `--project workflow --local` to note operations:

```bash
MEMORY_ROOT="${WORKFLOW_MEMORY_HOME:-$HOME/.workflow/memory}"
export BASIC_MEMORY_CONFIG_DIR="$MEMORY_ROOT/state"
export BASIC_MEMORY_HOME="$MEMORY_ROOT/knowledge"
BASIC_MEMORY_SEMANTIC_SEARCH_ENABLED=false basic-memory tool search-notes "authentication decision" --page-size 8 --project workflow --local
basic-memory tool read-note "memory://architecture/authentication" --include-frontmatter --project workflow --local
basic-memory tool build-context "memory://architecture/*" --depth 2 --timeframe 30d --project workflow --local
basic-memory tool recent-activity --timeframe 7d --page-size 20 --project workflow --local
printf '%s\n' '# Decision' '' 'Verified content.' | basic-memory tool write-note --title "Authentication decision" --folder architecture --type decision --project workflow --local
```

Pass note bodies through stdin when they contain quotes or multiple lines. Search before writing; update an existing note instead of creating a duplicate. Use `--overwrite` only when intentionally replacing the whole note.

For guaranteed offline search, set `BASIC_MEMORY_SEMANTIC_SEARCH_ENABLED=false` as shown above. Use vector or hybrid retrieval only after the local FastEmbed model has been downloaded and indexed.

## Safety

- Keep memory local. Never use `--cloud`, cloud workspaces, login, or MCP commands.
- Never store secrets, credentials, private user data, raw conversations, full logs, or unverified claims.
- Preserve repository/source provenance and verification evidence in every durable finding.
- Do not delete notes unless the user explicitly authorizes deletion.
- If memory is unavailable, continue the coding task and report the memory failure separately.
