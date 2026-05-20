# unreal-source-mcp

Local stdio MCP server for fast Unreal Engine source lookup with SQLite FTS5 (trigram tokenizer) and query templates.

## Features

- Index Unreal source files into SQLite FTS5 with trigram tokenizer.
- Search code symbols like `GetGBuffer`, `Material.Roughness`, `UE_LOG` precisely.
- Returns code snippets (not whole files) via FTS5 `snippet()`.
- Read specific line ranges when more context is needed.
- Query template caching for recurring intents.

## Setup

```bash
uv sync --dev
```

## Build the source index

```bash
uv run unreal-source-build-db /path/to/UnrealEngine /path/to/unreal.db
```

For a smoke test:

```bash
uv run unreal-source-build-db /path/to/UnrealEngine /path/to/unreal.db --limit 1000
```

## Run the MCP server

```bash
UNREAL_SOURCE_DB=/path/to/unreal.db uv run unreal-source-mcp
```

## Tools (5)

| Tool | Purpose |
|------|---------|
| `search_unreal_source` | FTS5 search → filename + code snippet |
| `get_file_content` | Read full file or line range |
| `get_query_templates` | Lookup cached query templates |
| `log_unreal_query` | Record query feedback |
| `save_query_template` | Persist a template (with user confirmation) |

## Development

```bash
uv run pytest
uv run ruff check .
```
