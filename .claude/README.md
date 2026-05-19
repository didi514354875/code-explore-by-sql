# Claude Code integration

This repository includes a Claude-oriented customization layer for the local `unreal-source-mcp` server.

## Included artifacts

- `AGENTS.md`
  - repository-level behavior guidance for Claude-style agents
- `.github/skills/unreal-source-lookup/SKILL.md`
  - workflow skill for Unreal source retrieval
- `.github/agents/unreal-source-explorer.agent.md`
  - specialized agent for token-aware Unreal source navigation

## Expected MCP server

Use the same stdio launch pattern as `.vscode/mcp.json`:

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

Adjust the exact config format to the Claude client you use, but keep the same command, args, and environment variable.

## Recommended Claude workflow

1. Try `suggest_query_templates` or `get_query_templates` for repeated intents.
2. Prefer `search_code_chunks` for direct symbol retrieval.
3. Use `search_then_extract_chunks` when chunk cache coverage may be incomplete.
4. Use `search_unreal_source` only for broader recall.
5. Use `get_file_content` only for narrow ranges or when chunk context is insufficient.

## Notes

- This MCP is designed to reduce token usage by returning chunks instead of whole files.
- Save query templates only after user confirmation.
- For best latency, build the DB with `--extract-chunks` or run `unreal-source-extract-chunks` after indexing.