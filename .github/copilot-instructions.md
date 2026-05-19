# Workspace Instructions

- [x] Verify that the `copilot-instructions.md` file in the `.github` directory is created.
- [x] Clarify Project Requirements
  - Python MCP server for Unreal source SQLite FTS5 indexing, search, lazy heuristic chunk extraction, query logs, and reusable query templates.
- [x] Scaffold the Project
  - Manual uv-based Python package scaffold in the current workspace.
- [x] Customize the Project
  - Implemented FastMCP stdio server, SQLite FTS5 schema, Unreal source indexer, heuristic chunk extractor, query logs, and query templates.
- [x] Install Required Extensions
  - No required VS Code extensions were specified.
- [x] Compile the Project
  - Installed dependencies with uv, ran `uv run pytest`, and ran `uv run ruff check .` successfully.
- [x] Create and Run Task
  - Skipped; no persistent VS Code task is required for this stdio MCP server.
- [x] Launch the Project
  - Skipped automatic launch; use `.vscode/mcp.json` or `UNREAL_SOURCE_DB=/path/to/unreal.db uv run unreal-source-mcp`.
- [x] Ensure Documentation is Complete
  - README and workspace instructions are present and current.

## Project Notes

This workspace implements a local stdio MCP server backed by SQLite FTS5 for Unreal Engine source lookup. Keep stdio server logs off stdout; use stderr or files only.
