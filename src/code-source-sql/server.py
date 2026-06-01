"""MCP server for UE Semantic Search — two tools per plan.md.

Tool 1: Read_Symbol(qualified_name)
  - Precise lookup via symbol_index
  - Returns code with [System Hint] header (edges, UE metadata, action guide)

Tool 2: Search_FTS(keyword, path_filter)
  - FTS5 full-text search, grep-mode results
  - Returns hit line + 2 lines context, minimal token cost
"""

from __future__ import annotations

import os
from typing import Any

from mcp.server.fastmcp import FastMCP

from db import (
    connect,
    initialize_schema,
    read_symbol as db_read_symbol,
    search_fts as db_search_fts,
    format_symbol_response,
    get_directory_structure as db_get_directory_structure,
)

mcp = FastMCP("code-source-sql")


def _db_path() -> str:
    return os.environ.get("CODE_SOURCE_DB", "unreal.db")


def _conn():
    conn = connect(_db_path())
    initialize_schema(conn)
    return conn


@mcp.tool()
def read_symbol(qualified_name: str, expand_item: list[str] | None = None) -> str:
    """Read a symbol's source code with [System Hint] header.

    The core tool for precise code lookup. Accepts a qualified name
    (e.g., 'ACharacter::Jump', 'UWeaponComponent', 'FWeaponData').

    Returns the symbol's code block with a [System Hint] header that includes:
    - Qualified Name and file location
    - UE Metadata (UFUNCTION/UCLASS params, RPC routing hints)
    - Static Relations (inheritance, type dependencies, static calls, RPC targets)
    - Action Guide for resolving pointer calls via type dependencies

    Supports fuzzy resolution:
    - 'Actor' resolves to 'AActor' (UE prefix normalization)
    - 'Jump' matches 'ACharacter::Jump' (partial QN match)

    expand_item: optional signal-enrichment hints. These do not expand or
    filter the query; they only rank multiple matches and annotate matches in
    the [System Hint] header.
    """
    with _conn() as conn:
        entries = db_read_symbol(conn, qualified_name, expand_item=expand_item)
        if not entries:
            return f"Symbol '{qualified_name}' not found. Try with full qualified name (e.g., 'ClassName::MethodName')."

        # Return the best match with System Hint
        best = entries[0]
        result = format_symbol_response(best)

        # If multiple matches, list alternatives
        if len(entries) > 1:
            result += f"\n\n// Also found {len(entries) - 1} other definitions:"
            for e in entries[1:5]:
                result += f"\n//   {e['qualified_name']} at {e['file_path']}:{e['start_line']}"

        return result


@mcp.tool()
def search_fts_tool(
    keyword: str,
    path_filter: str = "",
    expand_item: list[str] | None = None,
) -> list[dict[str, Any]]:
    """Full-text search returning grep-style results with minimal token cost.

    Returns matching lines with 2 lines of context before and after.
    Use this to find 'glue code' like delegate bindings (AddDynamic, Bind),
    macro calls, or any text pattern that doesn't have a qualified name.

    keyword: search text (supports trigram FTS5 matching)
    path_filter: optional module name to filter results (e.g., 'Engine', 'Renderer')
    expand_item: optional signal-enrichment hints. These do not expand or
    filter the query; they only boost/annotate results that contain confirmed
    related symbols, classes, routes, delegate names, or modules.
    """
    with _conn() as conn:
        results = db_search_fts(conn, keyword, path_filter, expand_item=expand_item)
        if not results:
            return [{"message": f"No results for '{keyword}'.", "keyword": keyword}]
        return results


@mcp.tool()
def get_directory_structure() -> dict[str, Any]:
    """Get the directory structure summary from the indexed database.

    Returns total files, total modules, and module breakdown.
    Use module names as path_filter in search_fts_tool.
    """
    with _conn() as conn:
        return db_get_directory_structure(conn)


def main() -> None:
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
