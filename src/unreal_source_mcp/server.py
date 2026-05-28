from __future__ import annotations

import os
from typing import Any

from mcp.server.fastmcp import FastMCP

from .db import (
    connect,
    get_source_anchored,
    get_source_by_path,
    initialize_schema,
    record_feedback,
    search_source_with_feedback,
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
    expanded_terms: list[str] | None = None,
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

    expanded_terms: Optional extra keywords from intent expansion. Use world knowledge
    to expand the search intent into related terms that may appear in past query logs.
    Example: searching for "Material architecture" could expand to
    ["FMaterial", "UMaterialInterface", "MaterialResource", "MaterialRenderProxy",
     "MaterialShared"]. These terms are merged with auto-extracted terms for history
    matching via LIKE OR, improving hit rate on past queries.

    The system automatically:
    - Searches query_logs for similar past queries first (history-boosted)
    - Falls back to full FTS5 search if no history match
    - Records each search in query_logs
    - Results include a "source" field: "history_refined" or "fts"
    Returns filename + code snippet.
    """
    if raw_query is None and query is None:
        return [{"error": "Provide either query or raw_query"}]
    with _conn() as conn:
        try:
            return search_source_with_feedback(
                conn,
                query=query,
                raw_query=raw_query,
                expanded_terms=expanded_terms,
                module=module,
                limit=max(1, min(limit, 100)),
            )
        except Exception as exc:
            return [{"error": f"FTS5 query error: {exc}", "query": raw_query or query}]


@mcp.tool()
def get_file_content(
    file_path: str,
    start_line: int | None = None,
    end_line: int | None = None,
    anchor: str | None = None,
    context_chars: int = 500,
) -> dict[str, Any]:
    """Return full or line-ranged source file content from the indexed database.

    Two extraction modes:
    1. Line range (start_line / end_line): returns lines between the given bounds.
    2. Anchor (anchor): finds the anchor string via instr() and extracts a
       context_chars-sized window centered on it. Avoids reading the entire file.
       context_chars defaults to 500, roughly 12-15 lines of code.

    Automatically records feedback when the file was in recent search results.
    """
    with _conn() as conn:
        if anchor is not None:
            result = get_source_anchored(conn, file_path, anchor, context_chars)
            if result is None:
                row = get_source_by_path(conn, file_path)
                if row is None:
                    return {"found": False, "file_path": file_path}
                return {"found": False, "file_path": file_path, "anchor_found": False}
            record_feedback(conn, file_path)
            return {
                "found": True,
                "file_path": result["file_path"],
                "module_name": result["module_name"],
                "anchor_pos": result["anchor_pos"],
                "total_chars": result["total_chars"],
                "content": result["content"],
            }
        row = get_source_by_path(conn, file_path)
        if row is None:
            return {"found": False, "file_path": file_path}
        content = row["raw_content"]
        if start_line is not None or end_line is not None:
            lines = content.splitlines()
            start = max(1, start_line or 1)
            end = min(len(lines), end_line or len(lines))
            content = "\n".join(lines[start - 1 : end])
        record_feedback(conn, file_path)
        return {
            "found": True,
            "file_path": row["file_path"],
            "module_name": row["module_name"],
            "content": content,
        }


@mcp.tool()
def log_unreal_query(
    query_text: str,
    was_useful: bool | None = None,
    refinement: str | None = None,
) -> dict[str, str]:
    """Record explicit feedback for a recent query.

    Finds the most recent query_log matching query_text and writes a query_note.
    Use this to correct or supplement the automatic feedback from get_file_content.
    """
    with _conn() as conn:
        log_row = conn.execute(
            "SELECT id FROM query_logs WHERE query_text = ? ORDER BY created_at DESC LIMIT 1",
            (query_text,),
        ).fetchone()
        if log_row is None:
            return {"status": "no_matching_log"}
        if was_useful is not None or refinement is not None:
            existing = conn.execute(
                "SELECT id FROM query_note WHERE query_log_id = ?", (log_row["id"],)
            ).fetchone()
            if existing:
                if was_useful is not None:
                    conn.execute(
                        "UPDATE query_note SET was_useful = ? WHERE query_log_id = ?",
                        (int(was_useful), log_row["id"]),
                    )
                if refinement is not None:
                    conn.execute(
                        "UPDATE query_note SET refinement = ? WHERE query_log_id = ?",
                        (refinement, log_row["id"]),
                    )
            else:
                conn.execute(
                    "INSERT INTO query_note(query_log_id, was_useful, refinement) VALUES (?, ?, ?)",
                    (log_row["id"], int(was_useful) if was_useful is not None else None, refinement),
                )
            conn.commit()
        return {"status": "ok"}


def main() -> None:
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
