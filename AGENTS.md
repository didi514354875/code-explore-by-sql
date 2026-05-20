# AGENTS.md

This repository provides a local MCP server for Unreal Engine source retrieval using SQLite FTS5 with trigram tokenizer.

## Architecture

One file = one row. FTS5 `snippet()` extracts relevant code fragments, so the agent never needs to read whole files. Trigram tokenizer ensures code symbols like `GetGBuffer`, `Material.Roughness`, `UE_LOG` are searchable.

## Tools (5)

1. **`search_unreal_source(query, module?, limit?)`** — FTS5 search, returns filename + code snippet.
2. **`get_file_content(file_path, start_line?, end_line?)`** — Read specific lines when snippet context is insufficient.
3. **`get_query_templates(query?, limit?)`** — Check cached templates for recurring intents.
4. **`log_unreal_query(...)`** — Record query feedback for template learning.
5. **`save_query_template(...)`** — Persist a template after user confirmation.

## Recommended flow

1. Call `get_query_templates` to check for cached templates matching the intent.
2. Call `search_unreal_source` with keywords — returns snippets, not whole files.
3. If snippet context is insufficient, call `get_file_content` with a narrow line range.
4. Optionally save a query template if the search was useful and likely to recur.

## Guidance

- Avoid returning large file bodies — use `search_unreal_source` first.
- Save query templates only after user confirmation.
- If the database has not been built yet, guide the user toward indexing first.
