# Claude Code integration

## MCP server config

```json
{
  "servers": {
    "code-explore-by-sql": {
      "type": "stdio",
      "command": "uv",
      "args": [
        "--directory",
        "/path/to/CodeExploreBySQL",
        "run",
        "code-explore-by-sql"
      ],
      "env": {
        "UNREAL_SOURCE_DB": "/absolute/path/to/unreal.db"
      }
    }
  }
}
```

## Available tools (5)

| Tool | Purpose |
|------|---------|
| `search_unreal_source` | FTS5 search with history ranking, clustering, scope filtering |
| `get_file_content` | Read file content by line range or anchor |
| `log_unreal_query` | Record explicit feedback for a query |
| `find_include_graph` | Query include dependency graph (upstream/downstream) |
| `find_callers` | Find callers of a symbol using FTS5 + bracket skeleton |

## Workflow

1. Search with `search_unreal_source` — returns code snippets, not whole files.
   - Use `cluster=true` for common terms to reduce noise.
   - Use `scope_filter` to narrow to specific block types (function/class).
2. Read specific lines with `get_file_content` (anchor mode or line range) if snippet context is insufficient.
3. Explore structure with `find_include_graph` and `find_callers`.
4. Use `log_unreal_query` only to correct automatic feedback.
