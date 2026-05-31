from __future__ import annotations

import os
from typing import Any

from mcp.server.fastmcp import FastMCP

from .db import (
    connect,
    exec_sql_query,
    find_block_for_line,
    find_enclosing_block,
    find_symbol_references,
    get_source_anchored,
    get_source_by_path,
    initialize_schema,
    load_bracket_index,
    record_feedback,
    search_source,
    search_source_with_feedback,
    _fuzzy_resolve_symbol,
)
from .db import (
    get_directory_structure as get_directory_structure_db,
)

mcp = FastMCP("code-explore-by-sql")


def _db_path() -> str:
    return os.environ.get("CODE_EXPLORE_DB", os.environ.get("UNREAL_SOURCE_DB", "unreal.db"))


def _conn():
    conn = connect(_db_path())
    initialize_schema(conn)
    return conn


@mcp.tool()
def search_code_source(
    query: str | None = None,
    raw_query: str | None = None,
    expanded_terms: list[str] | None = None,
    module: str | None = None,
    limit: int = 20,
    cluster: bool = False,
    scope_filter: dict | None = None,
) -> list[dict[str, Any]]:
    """Search source code files. Two modes:

    1. Simple mode (query): literal text match. Use for single keyword or phrase lookups.
       Supports fuzzy symbol resolution — e.g., "Actor" resolves to "AActor" for UE projects.
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
    matching, improving hit rate on past queries.

    cluster: If true, merge multiple hits in the same code block into one result
    with a hit_count field. Useful when a keyword appears many times in one function.

    scope_filter: Optional dict with block_type and/or block_name to narrow search.
    Example: {"block_type": "function", "block_name": "Render"}
    Only returns hits inside matching code blocks.

    Results are enriched with enclosing block metadata:
    - block_type: "function", "method", "class", "enum", etc.
    - block_name: e.g. "FShaderCache::GetShader"
    - block_range: e.g. "142-198"

    The system automatically:
    - Always performs full FTS5 search (no history-based filtering)
    - Uses history signals for ranking (not filtering) to avoid confirmation bias
    - Records each search in query_logs
    - Results include "source", "final_score", and block metadata fields
    Returns filename + code snippet + block info.
    """
    if raw_query is None and query is None:
        return [{"error": "Provide either query or raw_query"}]

    with _conn() as conn:
        try:
            # Try fuzzy resolution if query is a simple symbol name
            fuzzy_result = None
            if query and not raw_query and ' ' not in query and len(query) >= 3:
                fuzzy_result = _fuzzy_resolve_symbol(conn, query, limit=5)
                if fuzzy_result.get('expanded'):
                    # UE prefix normalization succeeded
                    query = fuzzy_result['expanded']
                elif fuzzy_result.get('suggestions') and not fuzzy_result.get('exact'):
                    # No exact match, return suggestions
                    return [{
                        "query": query,
                        "did_you_mean": fuzzy_result['suggestions'],
                        "message": f"No exact match for '{query}'. Did you mean one of these?",
                    }]

            results = search_source_with_feedback(
                conn,
                query=query,
                raw_query=raw_query,
                expanded_terms=expanded_terms,
                module=module,
                limit=max(1, min(limit, 100)),
                cluster=cluster,
                scope_filter=scope_filter,
            )

            # Add fuzzy metadata if expansion happened
            if fuzzy_result and fuzzy_result.get('expanded') and results:
                for r in results:
                    r['expanded_from'] = query.replace(fuzzy_result['expanded'], '')

            return results
        except Exception as exc:
            return [{"error": f"FTS5 query error: {exc}", "query": raw_query or query}]


MAX_LINE_SPAN = 200
MAX_CONTEXT_CHARS = 5000


@mcp.tool()
def get_file_content(
    file_path: str,
    start_line: int | None = None,
    end_line: int | None = None,
    anchor: str | None = None,
    context_chars: int = 500,
) -> dict[str, Any]:
    """Return source file content with enclosing block metadata.

    Two extraction modes:
    1. Line range (start_line / end_line): returns lines between the given bounds.
    2. Anchor (anchor): finds the anchor string via instr() and extracts a
       context_chars-sized window centered on it. context_chars defaults to 500
       (~12-15 lines of code). One of anchor or start_line/end_line is required.

    Returns enclosing_block metadata for the anchor/start_line position:
    - block_type: "function", "method", "class", etc.
    - block_name: e.g. "MyClass::Tick"
    - block_range: e.g. "142-198"
    - signature: e.g. "void MyClass::Tick(float DeltaTime)"

    Automatically records feedback when the file was in recent search results.
    """
    context_chars = min(context_chars, MAX_CONTEXT_CHARS)

    with _conn() as conn:
        if anchor is not None:
            result = get_source_anchored(conn, file_path, anchor, context_chars)
            if result is None:
                row = get_source_by_path(conn, file_path)
                if row is None:
                    return {"found": False, "file_path": file_path}
                return {"found": False, "file_path": file_path, "anchor_found": False}
            record_feedback(conn, file_path)

            # Compute line number from anchor_pos for block lookup
            file_id = result["id"]
            row_full = get_source_by_path(conn, file_path)
            if row_full:
                anchor_line = row_full["raw_content"][:result["anchor_pos"]].count("\n") + 1
                enclosing = find_block_for_line(conn, file_id, anchor_line)
            else:
                enclosing = None

            ret: dict[str, Any] = {
                "found": True,
                "file_path": result["file_path"],
                "module_name": result["module_name"],
                "anchor_pos": result["anchor_pos"],
                "total_chars": result["total_chars"],
                "content": result["content"],
            }
            if enclosing:
                ret["enclosing_block"] = enclosing
            return ret

        # Require anchor or line range — full-file read is disabled
        if start_line is None and end_line is None:
            return {"found": False, "file_path": file_path,
                    "error": "anchor or start_line/end_line required"}

        row = get_source_by_path(conn, file_path)
        if row is None:
            return {"found": False, "file_path": file_path}
        content = row["raw_content"]

        lines = content.splitlines()
        start = max(1, start_line or 1)
        end = min(len(lines), end_line or len(lines))
        actual_span = end - start
        content = "\n".join(lines[start - 1 : end])

        record_feedback(conn, file_path)

        enclosing = find_block_for_line(conn, row["id"], start)

        result: dict[str, Any] = {
            "found": True,
            "file_path": row["file_path"],
            "module_name": row["module_name"],
            "content": content,
            "total_lines": len(lines),
        }
        if enclosing:
            result["enclosing_block"] = enclosing
        if actual_span > MAX_LINE_SPAN:
            result["truncated_warning"] = True
            result["read_lines"] = f"{start}-{end}"
        return result


@mcp.tool()
def log_code_query(
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
            conn.execute(
                """INSERT INTO query_note(query_log_id, was_useful, refinement)
                   VALUES (?, ?, ?)
                   ON CONFLICT(query_log_id) DO UPDATE SET
                       was_useful = excluded.was_useful,
                       refinement = excluded.refinement""",
                (log_row["id"], int(was_useful) if was_useful is not None else None, refinement),
            )
            conn.commit()
        return {"status": "ok"}


@mcp.tool()
def find_include_graph(
    file_path: str,
    direction: str = "both",
    depth: int = 1,
) -> dict[str, Any]:
    """Query #include dependency relationships for a file.

    Complements find_callers: use find_callers for symbol-level references (who calls what),
    and find_include_graph for file-level dependencies (who includes whom).

    direction: "upstream" (who includes this file), "downstream" (what this file includes), or "both".
    depth: recursion depth (1 = direct dependencies only, 2 = one level deeper, etc.).
    Returns include graph as edges with file paths.
    """
    with _conn() as conn:
        row = get_source_by_path(conn, file_path)
        if row is None:
            return {"found": False, "file_path": file_path}

        file_id = row["id"]
        edges = []
        visited = set()

        def _collect(fid: int, current_depth: int) -> None:
            if current_depth > depth or fid in visited:
                return
            visited.add(fid)

            if direction in ("downstream", "both"):
                rows = conn.execute(
                    """
                    SELECT ie.include_path, ie.target_file_id, sf.file_path AS target_path
                    FROM include_edges ie
                    LEFT JOIN source_files sf ON sf.id = ie.target_file_id
                    WHERE ie.source_file_id = ?
                    """,
                    (fid,),
                ).fetchall()
                for r in rows:
                    edges.append({
                        "source_file_id": fid,
                        "include_path": r["include_path"],
                        "target_file_id": r["target_file_id"],
                        "target_path": r["target_path"],
                        "direction": "downstream",
                    })
                    if r["target_file_id"] and current_depth < depth:
                        _collect(r["target_file_id"], current_depth + 1)

            if direction in ("upstream", "both"):
                rows = conn.execute(
                    """
                    SELECT ie.source_file_id, sf.file_path AS source_path, ie.include_path
                    FROM include_edges ie
                    JOIN source_files sf ON sf.id = ie.source_file_id
                    WHERE ie.target_file_id = ?
                    """,
                    (fid,),
                ).fetchall()
                for r in rows:
                    edges.append({
                        "source_file_id": r["source_file_id"],
                        "source_path": r["source_path"],
                        "include_path": r["include_path"],
                        "target_file_id": fid,
                        "direction": "upstream",
                    })
                    if current_depth < depth:
                        _collect(r["source_file_id"], current_depth + 1)

        _collect(file_id, 1)

        return {
            "found": True,
            "file_path": file_path,
            "file_id": file_id,
            "edges": edges,
            "total_edges": len(edges),
        }


def _find_callers_from_fts(
    conn,
    symbol: str,
    scope: str | None,
    limit: int,
) -> list[dict[str, Any]]:
    """FTS5 fallback: text search + bracket attribution for callers."""
    results = search_source(conn, symbol, module=scope, limit=50)

    callers = []
    seen_blocks = set()
    symbol_lower = symbol.lower()

    for r in results:
        brackets_all = load_bracket_index(conn, r["id"])
        if not brackets_all:
            continue

        top_blocks = {b["open_line"]: b for b in brackets_all if b["depth"] == 1}

        row = get_source_by_path(conn, r["file_path"])
        if not row:
            continue
        lines = row["raw_content"].splitlines()

        for line_idx, line in enumerate(lines, start=1):
            if symbol_lower not in line.lower():
                continue

            stripped = line.lstrip()
            if stripped.startswith("#include"):
                continue

            enclosing = find_enclosing_block(brackets_all, line_idx)
            if not enclosing:
                continue

            enclosing_top = None
            for _tb_open, tb in top_blocks.items():
                if tb["open_line"] <= line_idx <= tb["close_line"]:
                    enclosing_top = tb
                    break

            if not enclosing_top:
                continue

            block_key = (r["id"], enclosing_top["open_line"])
            if block_key in seen_blocks:
                continue

            if enclosing_top.get("block_name") and symbol_lower in (enclosing_top["block_name"] or "").lower():
                sig = enclosing_top.get("signature") or ""
                if sig and line_idx <= enclosing_top["open_line"] + 2:
                    continue

            seen_blocks.add(block_key)

            callers.append({
                "file_path": r["file_path"],
                "module_name": r["module_name"],
                "block_type": enclosing_top["block_type"],
                "block_name": enclosing_top.get("block_name"),
                "block_range": f"{enclosing_top['open_line']}-{enclosing_top['close_line']}",
                "caller_line": line_idx,
            })

            if len(callers) >= limit:
                return callers

    return callers


@mcp.tool()
def find_callers(
    symbol: str,
    scope: str | None = None,
    limit: int = 50,
) -> dict[str, Any]:
    """Find callers/references of a symbol with pre-computed data + FTS5 fallback.

    Two-phase search:
    1. Query symbol_references table (fast, block-type-aware, pre-computed during index).
    2. If no pre-computed results, fallback to FTS5 full-text search + bracket attribution.

    Supports fuzzy symbol resolution — e.g., "Actor" resolves to "AActor".

    symbol: the symbol name to search for (e.g., "FVector", "BeginPlay", "Actor").
    scope: optional module name to limit search scope (use get_directory_structure to
           discover valid module names).
    limit: maximum number of callers to return (default 50).

    Each caller includes:
    - file_path, module_name
    - block_type: "function", "method", "class", etc.
    - block_name: e.g. "FShaderCache::GetShader"
    - block_range: e.g. "142-198"
    - caller_line: the line where the symbol is referenced

    Result includes 'source' field: "symbol_references" (pre-computed) or
    "fts5_fallback" (runtime text search). Prefer symbol_references results
    as they are block-type-aware and context-filtered.
    """
    with _conn() as conn:
        original_symbol = symbol
        fuzzy_result = _fuzzy_resolve_symbol(conn, symbol, limit=3)
        if fuzzy_result.get('expanded'):
            symbol = fuzzy_result['expanded']
        elif fuzzy_result.get('suggestions') and not fuzzy_result.get('exact'):
            return {
                "symbol": original_symbol,
                "source": None,
                "did_you_mean": fuzzy_result['suggestions'],
                "callers": [],
                "message": f"No exact match for '{original_symbol}'. Did you mean one of these?",
            }

        # Phase 1: pre-computed symbol_references
        refs = find_symbol_references(conn, symbol, limit=limit, scope=scope)
        if refs:
            callers = []
            seen = set()
            for r in refs:
                key = (r["ref_file_path"], r.get("ref_block_name"), r["ref_line"])
                if key in seen:
                    continue
                seen.add(key)
                callers.append({
                    "file_path": r["ref_file_path"],
                    "module_name": r.get("ref_module_name"),
                    "block_type": r.get("ref_block_type"),
                    "block_name": r.get("ref_block_name"),
                    "block_range": (
                        f"{r['ref_block_open']}-{r['ref_block_close']}"
                        if r.get("ref_block_open") else None
                    ),
                    "caller_line": r["ref_line"],
                })
            result = {
                "symbol": symbol,
                "source": "symbol_references",
                "callers": callers,
                "total": len(callers),
            }
            if fuzzy_result.get('expanded'):
                result['expanded_from'] = original_symbol
            return result

        # Phase 2: FTS5 fallback
        callers = _find_callers_from_fts(conn, symbol, scope, limit)
        result = {
            "symbol": symbol,
            "source": "fts5_fallback",
            "callers": callers,
            "total": len(callers),
        }
        if fuzzy_result.get('expanded'):
            result['expanded_from'] = original_symbol
        return result


@mcp.tool()
def get_directory_structure() -> dict[str, Any]:
    """Get the directory structure summary from the indexed database.

    Returns:
      - total_files: total number of indexed source files.
      - total_modules: total number of distinct modules.
      - modules: list of {module_name, file_count} — top 30 by file_count.
        Use module_name as `module` param in search_code_source or `scope` in find_callers.
      - top_dirs: dict with level_1 and level_2 keys, each a list of {path, file_count}.

    Use this to discover valid module names before searching, especially when
    exploring an unfamiliar codebase.
    """
    with _conn() as conn:
        return get_directory_structure_db(conn)


# @mcp.tool()
# def exec_sql(
#     sql: str,
#     expanded_terms: list[str] | None = None,
# ) -> dict[str, Any]:
#     """Execute a raw SQL SELECT query against the indexed source code database.

#     Tables:
#       source_files        (id, file_path, module_name, raw_content, content_hash, updated_at)
#       source_files_fts    FTS5 virtual table on source_files (file_path, module_name, raw_content)
#       bracket_index       (id, file_id, open_line, close_line, depth, block_type, block_name, signature, is_complete, parent_id, extra_fields)
#       symbol_references   (id, symbol_name, symbol_type, symbol_file_id, ref_file_id, ref_block_id, ref_line, confidence, context, edge_type)
#       include_edges       (id, source_file_id, include_path, target_file_id, line_number)
#       symbol_name_index   (name, source_type, source_id, file_id, block_type, module_name, qualified_name, member_types) WITHOUT ROWID
#       extra_blocks        (id, file_id, name, block_type, start_line, end_line, params, signature)
#       member_types        (id, block_id, type_name, line_number)
#       query_logs          (id, query_text, fts_match, hit_file_ids, hit_count, was_useful, refinement, template_id, created_at)
#       query_logs_fts      FTS5 virtual table on query_logs (query_text, fts_match)
#       query_note          (id, query_log_id, adopted_file_id, was_useful, refinement, note, created_at)
#       query_log_view      VIEW joining query_logs + query_note + source_files

#     Security: Only SELECT/WITH statements. Max 200 result rows.
#     expanded_terms: keywords for history-based score enrichment. If results contain
#       file_id or file_path, each row may get a 'history_score' field.
#     """
#     with _conn() as conn:
#         return exec_sql_query(conn, sql, expanded_terms=expanded_terms)


def main() -> None:
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
