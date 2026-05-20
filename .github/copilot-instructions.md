# Workspace Instructions

## Project

Python MCP server for Unreal source SQLite FTS5 indexing and search with trigram tokenizer and query templates.

## Commands

```bash
uv run pytest
uv run ruff check .
```

## Notes

- stdio MCP server — keep logs off stdout, use stderr or files only
- Trigram tokenizer is required for code symbol search (`GetGBuffer`, `UE_LOG`, etc.)
- Rebuild the database after schema changes: `uv run unreal-source-build-db /path/to/source /path/to/unreal.db`
