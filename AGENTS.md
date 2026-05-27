# AGENTS.md

This repository provides a local MCP server for Unreal Engine source retrieval using SQLite FTS5 with trigram tokenizer.

## Architecture

One file = one row. FTS5 `snippet()` extracts relevant code fragments, so the agent never needs to read whole files. Trigram tokenizer ensures code symbols like `GetGBuffer`, `Material.Roughness`, `UE_LOG` are searchable.

The system maintains a closed feedback loop: search results are automatically logged, and when the agent reads a file, feedback is recorded. Future similar searches are accelerated by this history.

## Tools (3)

1. **`search_unreal_source(query?, raw_query?, module?, limit?)`** — FTS5 search with automatic history acceleration.
   - `query`: simple literal match (single keyword or phrase)
   - `raw_query`: advanced FTS5 expression with AND/OR/NOT and column filters
   - System checks query_logs_fts for similar past queries first; falls back to full FTS5
   - Each search is auto-logged in query_logs
   - Results include `source` field: `"history_refined"` or `"fts"`

2. **`get_file_content(file_path, start_line?, end_line?, anchor?, context_chars?)`** — Read specific lines when snippet context is insufficient.
   - Automatically records feedback in query_note when the file was in recent search results

3. **`log_unreal_query(query_text, was_useful?, refinement?)`** — Record explicit feedback (optional).
   - Use only to correct or supplement automatic feedback

## FTS5 Query Syntax (for raw_query)

| Operator | Syntax | Example |
|----------|--------|---------|
| AND | `"A" AND "B"` | `'"GetGBuffer" AND "Emissive"'` |
| OR | `"A" OR "B"` | `'"Lumen" OR "RayTracing"'` |
| NOT | `"A" NOT "B"` | `'"Material" NOT "hlsl"'` |
| Grouping | `("A" OR "B") AND "C"` | `'("alpha" OR "beta") AND "gamma"'` |
| Column filter | `column : "term"` | `'file_path : "BasePass"'` |

Columns: `file_path`, `module_name`, `raw_content`

**Rules:**
- All terms must be 3+ characters (trigram tokenizer requirement)
- Phrase queries use `"double quotes"`
- NEAR and prefix (`*`) operators do NOT work with trigram tokenizer
- Use `query` for simple lookups, `raw_query` when you need boolean logic or column-scoped search

## Recommended flow

1. Call `search_unreal_source` with keywords — returns snippets, not whole files.
2. Call `get_file_content` with a narrow line range if snippet context is insufficient (auto-feedback).
3. Call `log_unreal_query` only if you need to correct the automatic feedback.

## Guidance

- Avoid returning large file bodies — use `search_unreal_source` first.
- The feedback loop is automatic — no need to manually log unless correcting.
- If the database has not been built yet, guide the user toward indexing first.
