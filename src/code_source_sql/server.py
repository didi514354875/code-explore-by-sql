"""MCP server for source code navigation — four tools.

Tool 1: read_symbol(qualified_name)
  - Precise lookup via symbol_index
  - Returns code with [System Hint] header (edges, metadata, action guide)

Tool 2: search_fts_tool(keyword, path_filter)
  - FTS5 full-text search, grep-mode results
  - Returns hit line + 2 lines context, minimal token cost

Tool 3: read_file_range(file_path, start_line, end_line)
  - File range read with symbol metadata overlay

Tool 4: get_directory_structure()
  - Module/file counts from index
"""

from __future__ import annotations

import os
from typing import Any

from mcp.server.fastmcp import FastMCP

from .db import (
    connect,
    format_file_range_response,
    format_symbol_response,
    initialize_schema,
)
from .db import (
    get_directory_structure as db_get_directory_structure,
)
from .db import (
    read_file_range as db_read_file_range,
)
from .db import (
    read_symbol as db_read_symbol,
)
from .db import (
    search_fts as db_search_fts,
)

mcp = FastMCP("code-source-sql")


def _db_path() -> str:
    return os.environ.get("CODE_SOURCE_DB", "code_source.db")


def _conn():
    conn = connect(_db_path())
    initialize_schema(conn)
    return conn


@mcp.tool()
def read_symbol(qualified_name: str, view: str = "full", expand_item: list[str] | None = None) -> str:
    """Read a symbol's source code with [System Hint] header.

    The core tool for precise code lookup. Accepts a qualified name
    (e.g., 'ClassName::MethodName', 'ClassName').

    Returns the symbol's code block with a [System Hint] header that includes:
    - Qualified Name and file location
    - Decoration metadata and framework-specific hints
    - Static Relations (inheritance, type dependencies, static calls, RPC targets)
    - Action Guide for resolving pointer calls via type dependencies

    Supports fuzzy resolution:
    - Partial names match qualified names (e.g., 'MethodName' matches 'ClassName::MethodName')

    view: controls output granularity:
    - "full" (default): complete source code
    - "signature": only member declarations (functions, variables, enums) — use for large classes
    - "meta": only [System Hint] header with edges and metadata, no code

    expand_item: optional signal-enrichment hints. These do not expand or
    filter the query; they only rank multiple matches and annotate matches in
    the [System Hint] header.
    """
    with _conn() as conn:
        entries = db_read_symbol(conn, qualified_name, expand_item=expand_item)
        if not entries:
            # FTS fallback: when symbol_index has no match, try full-text search
            fts_results = db_search_fts(conn, qualified_name, limit=5)
            if fts_results and "file_path" in fts_results[0]:
                lines = [f"Symbol '{qualified_name}' not found in symbol_index."]
                lines.append("FTS fallback — these source matches found:")
                for r in fts_results[:5]:
                    loc = f"  {r['file_path']}:{r['hit_line']}"
                    if r.get("block_name"):
                        loc += f" in {r['block_name']}"
                    lines.append(loc)
                lines.append("Use search_fts_tool or read_file_range for details.")
                return "\n".join(lines)
            return (
                f"Symbol '{qualified_name}' not found. "
                "Try with full qualified name "
                "(e.g., 'ClassName::MethodName' or 'ClassName.MethodName')."
            )

        # Return the best match with System Hint
        best = entries[0]
        result = format_symbol_response(best, view=view)

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
def read_file_range(
    file_path: str,
    start_line: int,
    end_line: int,
    view: str = "full",
    expand_item: list[str] | None = None,
) -> str:
    """Read source code by file path and line range, with [System Hint] metadata.

    Use this when search_fts returns a precise location but read_symbol
    cannot resolve the correct definition (e.g., returned .cpp implementation
    instead of .h declaration).

    Returns code with [System Hint] header that includes:
    - Symbols covered by the line range (from symbol_index)
    - UE Metadata and edges for those symbols
    - Module ownership

    view: controls output granularity:
    - "full" (default): complete source code
    - "signature": only member declarations — use for browsing large classes
    - "meta": only [System Hint] header with edges and UE metadata, no code

    expand_item: optional signal-enrichment hints for ranking and annotation.
    """
    with _conn() as conn:
        entry = db_read_file_range(conn, file_path, start_line, end_line, view=view, expand_item=expand_item)
        if not entry:
            return f"File '{file_path}' not found in the index."
        return format_file_range_response(entry, view=view)


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
