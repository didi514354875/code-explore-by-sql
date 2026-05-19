from __future__ import annotations

import os
from typing import Any

from mcp.server.fastmcp import FastMCP

from .chunker import chunk_to_dict, extract_chunks
from .db import (
    connect,
    get_cached_chunks,
    get_source_by_path,
    get_templates,
    initialize_schema,
    log_query,
    replace_chunks_for_file,
    save_template,
    search_chunks,
    search_source,
)

mcp = FastMCP("unreal-source-mcp")


def _db_path() -> str:
    return os.environ.get("UNREAL_SOURCE_DB", "unreal.db")


def _conn():
    conn = connect(_db_path())
    initialize_schema(conn)
    return conn


@mcp.tool()
def search_unreal_source(query: str, module: str | None = None, limit: int = 20) -> list[dict[str, Any]]:
    """Search Unreal source files using SQLite FTS5 MATCH syntax."""
    with _conn() as conn:
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
def extract_file_chunks(
    file_path: str,
    symbol: str | None = None,
    limit: int = 50,
    refresh: bool = False,
) -> list[dict[str, Any]]:
    """Return cached chunks for a file, falling back to heuristic extraction when needed."""
    with _conn() as conn:
        row = get_source_by_path(conn, file_path)
        if row is None:
            return []
        max_limit = max(1, min(limit, 200))
        if not refresh:
            cached = get_cached_chunks(conn, row["id"], symbol=symbol, limit=max_limit)
            if cached:
                return cached
        chunks = extract_chunks(row["raw_content"])
        replace_chunks_for_file(conn, row["id"], chunks)
        conn.commit()
        if symbol:
            chunks = [chunk for chunk in chunks if chunk.symbol_name and symbol.lower() in chunk.symbol_name.lower()]
        return [chunk_to_dict(chunk) for chunk in chunks[:max_limit]]


@mcp.tool()
def search_code_chunks(
    query: str,
    module: str | None = None,
    symbol_type: str | None = None,
    limit: int = 20,
    body_chars: int = 4000,
) -> list[dict[str, Any]]:
    """Search pre-cached function/class/macro chunks to reduce returned tokens."""
    with _conn() as conn:
        rows = search_chunks(
            conn,
            query=query,
            module=module,
            symbol_type=symbol_type,
            limit=max(1, min(limit, 100)),
            body_chars=max(200, min(body_chars, 12000)),
        )
        log_query(
            conn,
            query_text=query,
            fts_match=query,
            hit_file_ids=[row["file_id"] for row in rows],
            hit_chunk_ids=[row["id"] for row in rows],
        )
        return rows


@mcp.tool()
def search_then_extract_chunks(
    query: str,
    symbol: str | None = None,
    module: str | None = None,
    limit_files: int = 5,
    chunks_per_file: int = 3,
) -> list[dict[str, Any]]:
    """Search source files and return only top cached/extracted chunks in one round trip."""
    with _conn() as conn:
        files = search_source(conn, query=query, module=module, limit=max(1, min(limit_files, 20)))
        results: list[dict[str, Any]] = []
        for file_row in files:
            source = get_source_by_path(conn, file_row["file_path"])
            if source is None:
                continue
            chunks = get_cached_chunks(conn, source["id"], symbol=symbol, limit=chunks_per_file)
            if not chunks:
                extracted = extract_chunks(source["raw_content"])
                replace_chunks_for_file(conn, source["id"], extracted)
                conn.commit()
                chunks = get_cached_chunks(conn, source["id"], symbol=symbol, limit=chunks_per_file)
            for chunk in chunks[: max(1, min(chunks_per_file, 20))]:
                chunk["file_path"] = source["file_path"]
                chunk["module_name"] = source["module_name"]
                chunk["file_rank"] = file_row["rank"]
                results.append(chunk)
        log_query(conn, query_text=query, fts_match=query, hit_file_ids=[row["id"] for row in files])
        return results


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
    chunk_strategy: str = "heuristic",
    intent_keywords: list[str] | None = None,
) -> dict[str, int]:
    """Save a reusable search template after user confirmation."""
    with _conn() as conn:
        template_id = save_template(conn, intent_pattern, fts_template, chunk_strategy, intent_keywords)
        return {"id": template_id}


@mcp.tool()
def get_query_templates(query: str | None = None, limit: int = 20) -> list[dict[str, Any]]:
    """Return saved query templates, optionally ranked by template FTS search."""
    with _conn() as conn:
        return get_templates(conn, query=query, limit=max(1, min(limit, 100)))


@mcp.tool()
def suggest_query_templates(intent: str, limit: int = 5) -> list[dict[str, Any]]:
    """Suggest reusable query templates for an agent intent before running source search."""
    with _conn() as conn:
        return get_templates(conn, query=intent, limit=max(1, min(limit, 20)))


def main() -> None:
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
