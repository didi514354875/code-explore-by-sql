from __future__ import annotations

import os
from typing import Any

from mcp.server.fastmcp import FastMCP

from .db import (
    connect,
    get_source_by_path,
    get_templates,
    initialize_schema,
    log_query,
    save_template,
    search_source,
    search_source_raw,
)

mcp = FastMCP("unreal-source-mcp")


def _db_path() -> str:
    return os.environ.get("UNREAL_SOURCE_DB", "unreal.db")


def _conn():
    conn = connect(_db_path())
    initialize_schema(conn)
    return conn


@mcp.tool()
def search_unreal_source(
    query: str | None = None,
    raw_query: str | None = None,
    module: str | None = None,
    limit: int = 20,
) -> list[dict[str, Any]]:
    """Search Unreal source files. Two modes:

    1. Simple mode (query): literal text match. Use for single keyword or phrase lookups.
    2. Advanced mode (raw_query): raw FTS5 MATCH expression with AND, OR, NOT, column filters,
       and parentheses for grouping. Trigram tokenizer requires 3+ characters per term.
       Examples:
         - '"GetGBuffer" AND "Emissive"'
         - '(file_path : "BasePass") AND "roughness"'
         - '"Material" NOT "hlsl"'
         - '"Lumen" OR "RayTracing"'
    If both query and raw_query are given, raw_query takes precedence.
    Returns filename + code snippet.
    """
    if raw_query is None and query is None:
        return [{"error": "Provide either query or raw_query"}]
    with _conn() as conn:
        if raw_query is not None:
            try:
                rows = search_source_raw(conn, fts_query=raw_query, module=module, limit=max(1, min(limit, 100)))
            except Exception as exc:
                return [{"error": f"FTS5 query error: {exc}", "query": raw_query}]
            log_query(conn, query_text=raw_query, fts_match=raw_query, hit_file_ids=[row["id"] for row in rows])
        else:
            rows = search_source(conn, query=query, module=module, limit=max(1, min(limit, 100)))
            log_query(conn, query_text=query, fts_match=query, hit_file_ids=[row["id"] for row in rows])
        return rows


@mcp.tool()
def get_file_content(file_path: str, start_line: int | None = None, end_line: int | None = None) -> dict[str, Any]:
    """Return full or line-ranged source file content from the indexed database."""
    with _conn() as conn:
        row = get_source_by_path(conn, file_path)
        if row is None:
            return {"found": False, "file_path": file_path}
        content = row["raw_content"]
        if start_line is not None or end_line is not None:
            lines = content.splitlines()
            start = max(1, start_line or 1)
            end = min(len(lines), end_line or len(lines))
            content = "\n".join(lines[start - 1 : end])
        return {
            "found": True,
            "file_path": row["file_path"],
            "module_name": row["module_name"],
            "content": content,
        }


@mcp.tool()
def log_unreal_query(
    query_text: str,
    fts_match: str | None = None,
    was_useful: bool | None = None,
    refinement: str | None = None,
    template_id: int | None = None,
) -> dict[str, int]:
    """Store a query observation for later template mining."""
    with _conn() as conn:
        log_id = log_query(
            conn,
            query_text,
            fts_match,
            [],
            was_useful=was_useful,
            refinement=refinement,
            template_id=template_id,
        )
        return {"id": log_id}


@mcp.tool()
def save_query_template(
    intent_pattern: str,
    fts_template: str,
    intent_keywords: list[str] | None = None,
) -> dict[str, int]:
    """Save a reusable search template after user confirmation."""
    with _conn() as conn:
        template_id = save_template(conn, intent_pattern, fts_template, intent_keywords)
        return {"id": template_id}


@mcp.tool()
def get_query_templates(query: str | None = None, limit: int = 20) -> list[dict[str, Any]]:
    """Return saved query templates, optionally ranked by template FTS search."""
    with _conn() as conn:
        return get_templates(conn, query=query, limit=max(1, min(limit, 100)))


def main() -> None:
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
