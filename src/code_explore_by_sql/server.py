from __future__ import annotations

import os
from typing import Any

from mcp.server.fastmcp import FastMCP

from .db import (
    connect,
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

    The system automatically:
    - Always performs full FTS5 search (no history-based filtering)
    - Uses history signals for ranking (not filtering) to avoid confirmation bias
    - Records each search in query_logs
    - Results include "source" and "final_score" fields
    Returns filename + code snippet.
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
    """Return full or line-ranged source file content from the indexed database.

    Two extraction modes:
    1. Line range (start_line / end_line): returns lines between the given bounds.
    2. Anchor (anchor): finds the anchor string via instr() and extracts a
       context_chars-sized window centered on it. Avoids reading the entire file.
       context_chars defaults to 500, roughly 12-15 lines of code.

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
            return {
                "found": True,
                "file_path": result["file_path"],
                "module_name": result["module_name"],
                "anchor_pos": result["anchor_pos"],
                "total_chars": result["total_chars"],
                "content": result["content"],
            }

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
        result = {
            "found": True,
            "file_path": row["file_path"],
            "module_name": row["module_name"],
            "content": content,
            "total_lines": len(lines),
        }
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
    """Query include dependency relationships for a file.

    direction: "upstream" (who includes this file), "downstream" (what this file includes), or "both".
    depth: recursion depth (1 = direct dependencies only, 2 = one level deeper, etc.).
    Returns include graph as edges.
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


@mcp.tool()
def find_callers(
    symbol: str,
    scope: str | None = None,
) -> dict[str, Any]:
    """Find callers of a symbol using bracket skeleton + text search.

    Searches for the symbol name in all indexed files, then uses bracket_index
    to locate which function/class each occurrence belongs to by finding the
    symbol text within block line ranges (not just file-level matching).

    scope: optional module name to limit search scope.
    Returns list of callers with file, enclosing function, and line info.
    """
    with _conn() as conn:
        # Try fuzzy resolution first
        original_symbol = symbol
        fuzzy_result = _fuzzy_resolve_symbol(conn, symbol, limit=3)
        if fuzzy_result.get('expanded'):
            symbol = fuzzy_result['expanded']
        elif fuzzy_result.get('suggestions') and not fuzzy_result.get('exact'):
            return {
                "symbol": original_symbol,
                "did_you_mean": fuzzy_result['suggestions'],
                "callers": [],
                "message": f"No exact match for '{original_symbol}'. Did you mean one of these?",
            }

        results = search_source(conn, symbol, module=scope, limit=50)

        callers = []
        seen_blocks = set()
        symbol_lower = symbol.lower()

        for r in results:
            # Load ALL bracket blocks (not just depth=1) for precise enclosing
            brackets_all = load_bracket_index(conn, r["id"])
            if not brackets_all:
                continue

            # Build a quick lookup: depth=1 blocks by open_line
            top_blocks = {b["open_line"]: b for b in brackets_all if b["depth"] == 1}

            # Get file content to find exact symbol locations
            row = get_source_by_path(conn, r["file_path"])
            if not row:
                continue
            lines = row["raw_content"].splitlines()

            # Find all lines containing the symbol (1-based)
            for line_idx, line in enumerate(lines, start=1):
                if symbol_lower not in line.lower():
                    continue

                # Skip preprocessor #include and #define lines
                stripped = line.lstrip()
                if stripped.startswith("#include"):
                    continue

                # Find the enclosing block for this line
                enclosing = find_enclosing_block(brackets_all, line_idx)
                if not enclosing:
                    continue

                # The enclosing block might already be depth=1, or we need
                # to find which depth=1 block contains this line
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

                # Skip the definition block (where the symbol is the block name)
                if enclosing_top.get("block_name") and symbol_lower in (enclosing_top["block_name"] or "").lower():
                    # Extra check: if the symbol appears on the signature line,
                    # it's the definition, not a call
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

        result = {
            "symbol": symbol,
            "callers": callers,
            "total": len(callers),
        }
        if fuzzy_result.get('expanded'):
            result['expanded_from'] = original_symbol
        return result


@mcp.tool()
def find_references(symbol: str, limit: int = 100) -> dict[str, Any]:
    """Find references to a symbol from the pre-computed symbol_references table.

    symbol: the symbol name to find references for (e.g., "UMyClass", "BeginPlay").
    limit: maximum number of references to return (default 100).

    Returns pre-computed references with file paths and enclosing block info.
    Falls back to empty list if symbol_references table is not yet populated.
    """
    with _conn() as conn:
        # Try fuzzy resolution first
        original_symbol = symbol
        fuzzy_result = _fuzzy_resolve_symbol(conn, symbol, limit=3)
        if fuzzy_result.get('expanded'):
            symbol = fuzzy_result['expanded']
        elif fuzzy_result.get('suggestions') and not fuzzy_result.get('exact'):
            return {
                "symbol": original_symbol,
                "did_you_mean": fuzzy_result['suggestions'],
                "references": [],
                "message": f"No exact match for '{original_symbol}'. Did you mean one of these?",
            }

        refs = find_symbol_references(conn, symbol, limit)
        result = {
            "symbol": symbol,
            "references": refs,
            "total": len(refs),
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


def main() -> None:
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
