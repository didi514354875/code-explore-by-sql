# Claude Code integration

## MCP server config

```json
{
  "servers": {
    "unreal-source-mcp": {
      "type": "stdio",
      "command": "uv",
      "args": [
        "--directory",
        "/home/yanwei/Documents/myproj/mysql",
        "run",
        "unreal-source-mcp"
      ],
      "env": {
        "UNREAL_SOURCE_DB": "/absolute/path/to/unreal.db"
      }
    }
  }
}
```

## Workflow

1. Check `get_query_templates` for cached templates matching the intent.
2. Search with `search_unreal_source` — returns snippets, not whole files.
3. Read specific lines with `get_file_content` if snippet context is insufficient.
4. Save query templates only after user confirmation.
