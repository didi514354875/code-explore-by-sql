# unreal-source-mcp

Local stdio MCP server for fast source code navigation using **SQLite FTS5** (trigram tokenizer) + **bracket skeleton indexing**.

## Features

- **Full-text search**: FTS5 with trigram tokenizer for code-symbol-precise search (`GetGBuffer`, `FMaterial`, `UE_LOG`)
- **Bracket skeleton index**: lightweight structural indexing via FSM brace matching (no AST parser needed)
- **Symbol classification**: heuristic block-type detection (namespace/class/enum/function/macro) for C/C++
- **Include dependency graph**: O(1) include path matching with upstream/downstream traversal
- **Caller lookup**: find callers of any symbol using FTS5 + bracket skeleton with line-range verification
- **Search result clustering**: merge multiple hits in the same code block into one result
- **Scope filtering**: restrict search results to specific block types (function/class/namespace)
- **History-accelerated ranking**: past feedback adjusts ranking without filtering (prevents confirmation bias)
- **Anchor-based extraction**: efficient context retrieval around a symbol without reading the whole file
- **Token-efficient responses**: compact snippets (~2,600 tokens/20 results, 95% reduction vs full snippets)

## Setup

```bash
uv sync --dev
```

## Build the source index

```bash
# Full build (two-phase: fast import → parallel structural indexing)
uv run unreal-source-build-db /path/to/UnrealEngine /path/to/unreal.db

# Smoke test with limited files
uv run unreal-source-build-db /path/to/UnrealEngine /path/to/unreal.db --limit 1000
```

Performance: ~84,700 files indexed in ~3.3 minutes on a 2-core machine.

## Run the MCP server

```bash
UNREAL_SOURCE_DB=/path/to/unreal.db uv run unreal-source-mcp
```

## Tools (5)

| Tool | Purpose |
|------|---------|
| `search_unreal_source` | FTS5 search with history ranking, clustering, and scope filtering |
| `get_file_content` | Read full file, line range, or anchor-based context extraction |
| `log_unreal_query` | Record explicit feedback for a past query |
| `find_include_graph` | Query include dependency graph (upstream/downstream, recursive) |
| `find_callers` | Find callers of a symbol using FTS5 + bracket skeleton |

## Search query modes

### Simple mode (`query`)
Single keyword or phrase — auto-escaped for FTS5:
```
query="GetGBuffer"
query="FMaterial Render"
```

### Advanced mode (`raw_query`)
Full FTS5 boolean expressions:
```
raw_query='"GetGBuffer" AND "Emissive"'
raw_query='"Material" NOT "hlsl"'
raw_query='(file_path : "BasePass") AND "roughness"'
```

### Optional parameters
- `cluster=true` — merge hits in the same code block, includes `block_type` and `block_name`
- `scope_filter='{"block_type": "function"}'` — only return results inside matching blocks
- `expanded_terms=["FMaterial", "UMaterialInterface"]` — domain terms for history matching
- `module="Renderer"` — filter by module name

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    MCP Server (FastMCP)                      │
├──────────┬──────────┬──────────┬──────────┬─────────────────┤
│ search   │ get_file │ log_     │ find_    │ find_           │
│ _source  │ _content │ query    │ include  │ callers         │
├──────────┴──────────┴──────────┴──────────┴─────────────────┤
│                     Query Pipeline                           │
│  FTS5 (two-step) → History signals → Composite scoring      │
│  → Scope filter → Clustering → Log                          │
├─────────────────────────────────────────────────────────────┤
│                    SQLite Database                           │
│  source_files + FTS5 │ bracket_index │ include_edges        │
│  query_logs + FTS5   │ query_note                            │
└─────────────────────────────────────────────────────────────┘
```

### Bracket skeleton index
A 6-state finite state machine (CODE, LINE_COMMENT, BLOCK_COMMENT, STRING, CHAR_LITERAL, RAW_STRING) scans C/C++ source tracking brace pairs while correctly ignoring braces in comments and string literals. Each matched pair records `open_line`, `close_line`, `depth`, and `is_complete`.

Top-level blocks (depth=1) are further classified by a **symbol sniffer** that examines preceding lines using heuristic regex patterns, producing `block_type` (namespace/class/enum/function/macro/control_flow) and `block_name`.

### Include dependency graph
Include paths are matched to indexed files using a pre-built basename → file_id hash map with collision resolution. 96.5% of includes resolve in O(1); the rest use O(k) suffix matching.

### Two-step FTS5 query
Instead of computing `snippet()` for all matching rows (10K+ for common terms), the query is split:
1. `bm25() + ORDER BY + LIMIT` to get top-N rowids (fast)
2. `snippet()` computed only for those top-N rows, truncated to 300 chars

This provides **~100x speedup** for high-frequency terms and **95% token reduction**.

## Performance (example: 84,696 source files from a game engine codebase)

| Operation | Latency | ~Tokens |
|-----------|---------|---------|
| Single keyword search (20 results) | ~90 ms | ~2,600 |
| Full pipeline (FTS5 + history + scoring) | ~115 ms | ~2,600 |
| Module-filtered search | ~250 ms | ~2,600 |
| find_callers (precise, per-symbol) | 100–900 ms | 127–3,100 |
| Include graph (depth=1) | ~15 ms | 50–2,100 |
| Anchor-based content extraction | ~0.1 ms | ~125 |
| Full file read (avoid!) | ~25 ms | ~45,000 |
| **Typical 3-search workflow** | **~400 ms** | **~4,500** |

## Database schema

| Table | Purpose |
|-------|---------|
| `source_files` | File metadata + raw content |
| `source_files_fts` | FTS5 trigram index on content |
| `bracket_index` | Brace pairs with depth, block type/name |
| `include_edges` | #include source → target relationships |
| `query_logs` | Search history for ranking signals |
| `query_logs_fts` | FTS5 index on query text for similarity matching |
| `query_note` | Explicit feedback (useful/not useful) |

## Development

```bash
uv run pytest
uv run ruff check .
# Bracket scanner + symbol sniffer tests
PYTHONPATH=src python3 tests/test_bracket_scanner.py
# Query pipeline efficiency tests
PYTHONPATH=src python3 tests/test_query_efficiency.py
# Token & efficiency benchmark
PYTHONPATH=src python3 tests/test_benchmark.py
```
