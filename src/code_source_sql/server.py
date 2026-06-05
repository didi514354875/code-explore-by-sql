"""MCP server for source code navigation — four tools.

Tool 1: read_symbol(qualified_name)
  - Lookup by qualified name, returns identity + code/signature

Tool 2: search_fts_tool(keyword, path_filter)
  - FTS5 search, returns located blocks with code preview

Tool 3: read_file_range(file_path, start_line, end_line)
  - Read by position, returns code with symbol metadata

Tool 4: get_directory_structure()
  - Module/file counts from index
"""

from __future__ import annotations

import os
from typing import Any

from mcp.server.fastmcp import FastMCP

from .db import (
    connect,
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
def read_symbol(qualified_name: str, view: str = "full", expand_item: list[str] | None = None) -> dict[str, Any]:
    """Read a symbol's source code by qualified name.

    Accepts qualified names like 'ClassName::MethodName' or short names.
    Supports fuzzy matching: 'MethodName' matches 'ClassName::MethodName'.

    view: "full" (default) = complete code, "signature" = summary, "meta" = identity only.
    expand_item: optional ranking hints for ambiguous matches.

    Returns dict with {qn, type, file, range, code?, alt?} or {error, query, fts?}.
    """
    with _conn() as conn:
        entries = db_read_symbol(conn, qualified_name, view=view, expand_item=expand_item)
        if not entries:
            fts_results = db_search_fts(conn, qualified_name, limit=5)
            if fts_results:
                return {
                    "error": "not_found",
                    "query": qualified_name,
                    "fts": [
                        {"file": r["file"], "line": r["line"], "block": r.get("block")}
                        for r in fts_results[:5]
                    ],
                }
            return {"error": "not_found", "query": qualified_name}

        result = entries[0]
        if len(entries) > 1:
            result["alt"] = entries[1:5]
        return result


@mcp.tool()
def search_fts_tool(
    keyword: str = "",
    path_filter: str = "",
    expand_item: list[str] | None = None,
    raw_query: str = "",
) -> list[dict[str, Any]]:
    """Locate code blocks by keyword or raw FTS5 query.

    Two query modes (use one):
    - keyword: auto-escaped AND of tokens. Simple, safe. Example: "AddDynamic"
    - raw_query: full FTS5 MATCH expression. Column filters, OR, NOT.
      Example: '(file_path : "Character.h") AND "BeginPlay"'

    FTS5 columns: file_path, module_name, content (all trigram, ≥3 chars).

    raw_query operators:
      AND  →  '"AddDynamic" AND "UObject"'
      OR   →  '"AActor" OR "APawn"'
      NOT  →  '"Update" NOT "Test"'
      Column filter →  '(file_path : "Shader.h") AND "FShaderType"'
      Module filter  →  '(module_name : "Renderer") AND "VirtualTexture"'

    Each result includes file, line, and optionally block QN + block_type.
    For full code, use read_symbol with the block QN, or read_file_range with file+line.
    """
    with _conn() as conn:
        return db_search_fts(conn, keyword, path_filter, expand_item=expand_item, raw_query=raw_query)


@mcp.tool()
def read_file_range(
    file_path: str,
    start_line: int,
    end_line: int,
    view: str = "full",
    expand_item: list[str] | None = None,
) -> dict[str, Any]:
    """Read source code by file path and line range.

    Use when search_fts returns a location but read_symbol cannot resolve it,
    or when reading code outside symbol boundaries.

    view: "full" = complete code, "signature" = summary, "meta" = symbols only.

    Returns dict with {file, range, code?, symbols?} or {error, file}.
    """
    with _conn() as conn:
        entry = db_read_file_range(conn, file_path, start_line, end_line, view=view, expand_item=expand_item)
        if not entry:
            return {"error": "not_found", "file": file_path}
        return entry


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
