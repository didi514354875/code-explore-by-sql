# AGENTS.md

This repository provides a local MCP server for Unreal Engine source retrieval. The preferred behavior for Claude-style agents is **retrieval-first and token-aware**.

## Goals

- Find relevant Unreal Engine source quickly.
- Prefer function/class/macro chunks over full-file dumps.
- Reduce unnecessary MCP round trips.
- Save reusable query templates only when the user confirms.

## Preferred retrieval order

1. `suggest_query_templates` or `get_query_templates`
2. `search_code_chunks`
3. `search_then_extract_chunks`
4. `search_unreal_source`
5. `get_file_content` only for narrow ranges or final fallback

## Guidance

- Use cached chunk search before requesting full file content.
- When chunk cache may be incomplete, use combined retrieval before falling back to whole-file reads.
- Treat `query_templates` as semi-automatic memory: suggest them, but do not persist new ones silently.
- Avoid returning very large file bodies unless the user explicitly asks for them.
- If the database has not been built yet, guide the user toward indexing first.

## MCP server expectations

- Server entry point: `unreal-source-mcp`
- Database path comes from `UNREAL_SOURCE_DB`
- For best latency, index with `--extract-chunks` or run `unreal-source-extract-chunks` after indexing

## Good task fits

- Find Unreal symbol definitions or likely implementations
- Trace function/class/macro usage paths
- Narrow large source trees to specific candidate chunks
- Suggest reusable FTS query templates for recurring Unreal questions

## Avoid by default

- Dumping full `.cpp` / `.h` files when chunks are enough
- Saving templates without confirmation
- Running expensive full pre-cache operations unless the user wants it
