# unreal-source-mcp

Local stdio MCP server for fast Unreal Engine source lookup with SQLite FTS5, cached heuristic C++ chunk extraction, and query templates.

## Features

- Index Unreal source files into SQLite FTS5.
- Search source text with SQLite `MATCH` queries.
- Retrieve full files or line ranges from the database.
- Extract function/class/macro chunks lazily with regex anchors and brace matching.
- Search cached chunks directly to return smaller function/class-level context.
- Store query logs, reusable query templates, and explicit usefulness feedback for Agent-assisted workflows.

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

To index and pre-cache chunks in one pass:

```bash
uv run unreal-source-build-db /path/to/UnrealEngine /path/to/unreal.db --extract-chunks
```

Optionally pre-cache function/class/macro chunks after indexing:

```bash
uv run unreal-source-extract-chunks /path/to/unreal.db
```

## Run the MCP server

Set the database path and start stdio transport:

```bash
UNREAL_SOURCE_DB=/path/to/unreal.db uv run unreal-source-mcp
```

The included `.vscode/mcp.json` points to `./unreal.db` in this workspace. Update `UNREAL_SOURCE_DB` to your actual database path after indexing.

## Tools

- `search_unreal_source`: SQLite FTS5 search over indexed files.
- `search_code_chunks`: search pre-cached function/class/macro chunks and return compact bodies/snippets.
- `search_then_extract_chunks`: run file search and chunk extraction in one MCP round trip.
- `get_file_content`: fetch a full indexed file or line range.
- `extract_file_chunks`: return cached chunks for one file, falling back to lazy extraction when needed.
- `log_unreal_query`: store query observations.
- `get_query_templates`: list or search saved query templates.
- `suggest_query_templates`: suggest templates for an Agent intent.
- `save_query_template`: save reusable templates after user confirmation.

## Claude Code customization

This repo now includes a Claude-oriented customization layer:

- `AGENTS.md`: repository-level retrieval policy for Claude-style agents
- `.github/skills/unreal-source-lookup/SKILL.md`: Unreal source lookup workflow skill
- `.github/agents/unreal-source-explorer.agent.md`: token-aware Unreal source exploration agent
- `.claude/README.md`: Claude client setup notes and MCP config example

These files are intended to steer Claude toward the low-token retrieval path: template suggestion → chunk search → combined retrieval → broad file search → narrow file ranges as fallback.

## Recommended Agent flow

To reduce token usage, prefer chunk-level retrieval before full-file retrieval:

1. Call `suggest_query_templates` or `get_query_templates` for repeated intent patterns.
2. Call `search_code_chunks` if chunks have been pre-cached.
3. Call `search_then_extract_chunks` when chunk cache may be incomplete.
4. Call `search_unreal_source` for broad file discovery.
5. Call `get_file_content` only for focused line ranges or as a fallback.

## Development

```bash
uv run pytest
uv run ruff check .
```

## Benchmark latency and payload size

You can measure the expected search-speed and token-size benefit directly:

```bash
uv run unreal-source-benchmark /path/to/unreal.db --query "BeginPlay Tick" --query "UWorld SpawnActor" --pretty
```

The report compares:

- file-level FTS search latency
- chunk-level FTS search latency
- combined file-search-plus-chunk-extract latency
- returned payload size in characters
- estimated token volume for full-file vs chunk results

## Notes

This is retrieval-first by design. It avoids full AST parsing because Unreal macros and templates can make parser-based extraction brittle. Chunk extraction is heuristic and should fall back to file/range retrieval when confidence is low.
