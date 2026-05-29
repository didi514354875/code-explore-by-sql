# Workspace Instructions

## Project

Python MCP server for source code navigation using SQLite FTS5 (trigram tokenizer) with bracket skeleton structural indexing, include dependency graph, and history-accelerated search.

## Commands

```bash
uv sync --dev
uv run pytest
uv run ruff check .

# Bracket scanner + symbol sniffer tests (53 tests)
PYTHONPATH=src python3 tests/test_bracket_scanner.py

# Query pipeline efficiency tests
PYTHONPATH=src python3 tests/test_query_efficiency.py
```

## Key Files

| File | Purpose |
|------|---------|
| `src/code_explore_by_sql/server.py` | MCP server with 5 tools |
| `src/code_explore_by_sql/db.py` | Database layer, query pipeline, bracket/sniff logic |
| `src/code_explore_by_sql/bracket_scanner.py` | 6-state FSM for brace matching |
| `src/code_explore_by_sql/symbol_sniffer.py` | Heuristic block-type classification |
| `src/code_explore_by_sql/indexer.py` | Two-phase build: import → parallel structural indexing |

## Notes

- stdio MCP server — keep logs off stdout, use stderr or files only
- Trigram tokenizer requires 3+ character search terms
- Bracket skeleton index is heuristic, not AST — robust against macros but no type info
- Rebuild database after schema changes: `uv run code-explore-by-sql-build-db /path/to/source /path/to/unreal.db`
