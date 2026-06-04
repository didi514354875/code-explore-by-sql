"""Database schema and query functions — three-table architecture per plan.md.

Tables:
  file_content     — raw source files with FTS5 trigram index
  symbol_index     — qualified names with decoration metadata, line ranges
  strict_edges     — deterministic edges only (inheritance, type_dependency, static_call, rpc_routing)
"""

from __future__ import annotations

import json
import sqlite3
from pathlib import Path
from typing import Any

from .edge_extractor import StrictEdge
from .symbol_analyzer import ExtraSymbol, SymbolDef


def _resolve_lang_fw(language: str) -> tuple[Any, Any]:
    """Resolve a language name string to (LanguageConfig, FrameworkConfig).

    Uses the language registry for LanguageConfig lookup.
    C++ keeps Unreal framework for backward compat with existing databases.
    """
    from .configs import get_language, make_generic_framework
    lang = get_language(language)
    if language == "cpp":
        from .unreal_rules import make_unreal_framework
        return lang, make_unreal_framework()
    return lang, make_generic_framework()


def _get_lang_for(language: str) -> Any:
    """Resolve a language name string to a LanguageConfig instance."""
    lang, _ = _resolve_lang_fw(language)
    return lang


def connect(db_path: str | Path) -> sqlite3.Connection:
    path = Path(db_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA synchronous=NORMAL")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn


def initialize_schema(conn: sqlite3.Connection) -> None:
    conn.executescript("""
        -- Table 1: File_Content_FTS
        CREATE TABLE IF NOT EXISTS file_content (
            file_id INTEGER PRIMARY KEY AUTOINCREMENT,
            module_name TEXT,
            file_path TEXT NOT NULL UNIQUE,
            content TEXT NOT NULL,
            content_hash TEXT
        );

        CREATE VIRTUAL TABLE IF NOT EXISTS file_content_fts USING fts5(
            file_path,
            module_name,
            content,
            content=file_content,
            content_rowid=file_id,
            tokenize="trigram"
        );

        CREATE TRIGGER IF NOT EXISTS fc_ai AFTER INSERT ON file_content BEGIN
            INSERT INTO file_content_fts(rowid, file_path, module_name, content)
            VALUES (new.file_id, new.file_path, new.module_name, new.content);
        END;

        CREATE TRIGGER IF NOT EXISTS fc_ad AFTER DELETE ON file_content BEGIN
            INSERT INTO file_content_fts(file_content_fts, rowid, file_path, module_name, content)
            VALUES ('delete', old.file_id, old.file_path, old.module_name, old.content);
        END;

        CREATE TRIGGER IF NOT EXISTS fc_au AFTER UPDATE ON file_content BEGIN
            INSERT INTO file_content_fts(file_content_fts, rowid, file_path, module_name, content)
            VALUES ('delete', old.file_id, old.file_path, old.module_name, old.content);
            INSERT INTO file_content_fts(rowid, file_path, module_name, content)
            VALUES (new.file_id, new.file_path, new.module_name, new.content);
        END;

        -- Table 2: Symbol_Index
        CREATE TABLE IF NOT EXISTS symbol_index (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            qualified_name TEXT NOT NULL,
            block_type TEXT NOT NULL,
            file_id INTEGER NOT NULL REFERENCES file_content(file_id) ON DELETE CASCADE,
            start_line INTEGER NOT NULL,
            end_line INTEGER NOT NULL,
            decoration_meta TEXT,
            parent_class TEXT,
            signature TEXT,
            inheritance_base TEXT,
            language TEXT NOT NULL DEFAULT 'cpp'
        );

        CREATE INDEX IF NOT EXISTS idx_sym_qn ON symbol_index(qualified_name);
        CREATE INDEX IF NOT EXISTS idx_sym_file ON symbol_index(file_id);
        CREATE INDEX IF NOT EXISTS idx_sym_type ON symbol_index(block_type);
        CREATE INDEX IF NOT EXISTS idx_sym_file_line ON symbol_index(file_id, start_line);

        -- Table 3: Strict_Edges
        CREATE TABLE IF NOT EXISTS strict_edges (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source_qn TEXT NOT NULL,
            target_qn TEXT NOT NULL,
            edge_type TEXT NOT NULL,
            language TEXT NOT NULL DEFAULT 'cpp'
        );

        CREATE INDEX IF NOT EXISTS idx_edge_source ON strict_edges(source_qn);
        CREATE INDEX IF NOT EXISTS idx_edge_target ON strict_edges(target_qn);
        CREATE INDEX IF NOT EXISTS idx_edge_type ON strict_edges(edge_type);
    """)

    # Migrations for existing databases
    try:
        conn.execute("ALTER TABLE symbol_index ADD COLUMN language TEXT NOT NULL DEFAULT 'cpp'")
    except Exception:
        pass  # Column already exists
    try:
        conn.execute("ALTER TABLE strict_edges ADD COLUMN language TEXT NOT NULL DEFAULT 'cpp'")
    except Exception:
        pass
    try:
        conn.execute("ALTER TABLE symbol_index RENAME COLUMN ue_meta TO decoration_meta")
    except Exception:
        pass

    conn.commit()


# ── Write functions ──────────────────────────────────────────────────

def upsert_file(conn: sqlite3.Connection, file_path: str, module_name: str | None,
                content: str, content_hash: str | None = None) -> int:
    conn.execute(
        "DELETE FROM symbol_index WHERE file_id = "
        "(SELECT file_id FROM file_content WHERE file_path = ?)",
        (file_path,),
    )
    conn.execute(
        "DELETE FROM strict_edges WHERE source_qn IN "
        "(SELECT qualified_name FROM symbol_index WHERE file_id = "
        "(SELECT file_id FROM file_content WHERE file_path = ?))",
        (file_path,),
    )
    conn.execute(
        """INSERT INTO file_content(file_path, module_name, content, content_hash)
           VALUES (?, ?, ?, ?)
           ON CONFLICT(file_path) DO UPDATE SET
               module_name=excluded.module_name,
               content=excluded.content,
               content_hash=excluded.content_hash""",
        (file_path, module_name, content, content_hash),
    )
    row = conn.execute("SELECT file_id FROM file_content WHERE file_path = ?", (file_path,)).fetchone()
    return row["file_id"]


def insert_symbols(conn: sqlite3.Connection, symbols: list[SymbolDef]) -> None:
    if not symbols:
        return
    conn.executemany(
        """INSERT INTO symbol_index
           (qualified_name, block_type, file_id, start_line, end_line,
            decoration_meta, parent_class, signature, inheritance_base, language)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        [
            (
                s.qualified_name, s.block_type, s.file_id,
                s.start_line, s.end_line,
                json.dumps(s.decoration_meta) if s.decoration_meta else None,
                s.parent_class,
                s.signature,
                s.inheritance_base,
                s.language,
            )
            for s in symbols
        ],
    )


def insert_extra_symbols(conn: sqlite3.Connection, extras: list[ExtraSymbol]) -> None:
    if not extras:
        return
    conn.executemany(
        """INSERT INTO symbol_index
           (qualified_name, block_type, file_id, start_line, end_line, signature, language)
           VALUES (?, ?, ?, ?, ?, ?, ?)""",
        [
            (e.qualified_name, e.block_type, e.file_id, e.start_line, e.end_line, e.signature, e.language)
            for e in extras
        ],
    )


def insert_edges(conn: sqlite3.Connection, edges: list[StrictEdge]) -> None:
    if not edges:
        return
    conn.executemany(
        "INSERT INTO strict_edges(source_qn, target_qn, edge_type, language) VALUES (?, ?, ?, ?)",
        [(e.source_qn, e.target_qn, e.edge_type, e.language) for e in edges],
    )


def delete_file(conn: sqlite3.Connection, file_path: str) -> None:
    conn.execute("DELETE FROM file_content WHERE file_path = ?", (file_path,))


def commit(conn: sqlite3.Connection) -> None:
    conn.commit()


# ── Signal enrichment helpers ────────────────────────────────────────

def _normalize_expand_item(expand_item: list[str] | None) -> list[str]:
    if not expand_item:
        return []
    seen: set[str] = set()
    items: list[str] = []
    for item in expand_item:
        item = str(item).strip()
        key = item.lower()
        if len(item) >= 3 and key not in seen:
            seen.add(key)
            items.append(item)
    return items


def _signal_hits(text: str, expand_item: list[str]) -> list[str]:
    text_lower = text.lower()
    return [item for item in expand_item if item.lower() in text_lower]


# ── Read_Symbol query ────────────────────────────────────────────────

def read_symbol(
    conn: sqlite3.Connection,
    qualified_name: str,
    expand_item: list[str] | None = None,
) -> list[dict[str, Any]]:
    """Look up symbols by qualified_name. Supports exact and fuzzy matching.

    Returns list of dicts with symbol metadata + source code + edges.
    """
    expand_item = _normalize_expand_item(expand_item)

    # 1. Exact match
    rows = conn.execute(
        """SELECT si.*, fc.file_path, fc.module_name, fc.content
           FROM symbol_index si
           JOIN file_content fc ON fc.file_id = si.file_id
           WHERE si.qualified_name = ?
           ORDER BY si.file_id, si.start_line""",
        (qualified_name,),
    ).fetchall()

    # 2. Type prefix resolution: Actor -> AActor, UActor, FActor...
    #    Try if no exact results, or if exact results are only namespace/weak matches
    _weak_types = frozenset({"namespace", "macro_def"})
    need_prefix = not rows or all(r["block_type"] in _weak_types for r in rows)
    if need_prefix:
        db_langs = [r["language"] for r in conn.execute(
            "SELECT DISTINCT language FROM symbol_index"
        ).fetchall()]
        for lang_name in db_langs:
            _, fw_resolve = _resolve_lang_fw(lang_name)
            if fw_resolve.resolve_type_prefixes:
                for candidate in fw_resolve.resolve_type_prefixes(qualified_name):
                    prefix_rows = conn.execute(
                        """SELECT si.*, fc.file_path, fc.module_name, fc.content
                           FROM symbol_index si
                           JOIN file_content fc ON fc.file_id = si.file_id
                           WHERE si.qualified_name = ?
                           ORDER BY si.file_id, si.start_line""",
                        (candidate,),
                    ).fetchall()
                    if prefix_rows:
                        rows = prefix_rows
                        break
            if rows:
                break

    # 3. Partial match: contains the name (e.g., "Jump" matches "ACharacter::Jump")
    if not rows:
        rows = conn.execute(
            """SELECT si.*, fc.file_path, fc.module_name, fc.content
               FROM symbol_index si
               JOIN file_content fc ON fc.file_id = si.file_id
               WHERE si.qualified_name LIKE ?
               ORDER BY si.file_id, si.start_line""",
            (f"%{qualified_name}%",),
        ).fetchall()

    if not rows:
        return []

    results = []
    for r in rows:
        start = r["start_line"]
        end = r["end_line"]
        content = r["content"]
        lines = content.split("\n")

        # Extract the code slice
        code_lines = lines[start - 1 : end]
        code = "\n".join(code_lines)

        # Get edges for this symbol
        qn = r["qualified_name"]
        edges = conn.execute(
            """SELECT target_qn, edge_type FROM strict_edges
               WHERE source_qn = ?
               ORDER BY edge_type, target_qn""",
            (qn,),
        ).fetchall()

        # Get reverse edges (who points to this symbol)
        reverse_edges = conn.execute(
            """SELECT source_qn, edge_type FROM strict_edges
               WHERE target_qn = ?
               ORDER BY edge_type, source_qn""",
            (qn,),
        ).fetchall()

        decoration_meta = json.loads(r["decoration_meta"]) if r["decoration_meta"] else None

        signal_text = "\n".join(
            [
                qn,
                r["file_path"] or "",
                r["module_name"] or "",
                r["signature"] or "",
                r["parent_class"] or "",
                r["inheritance_base"] or "",
                json.dumps(decoration_meta) if decoration_meta else "",
                " ".join(e["target_qn"] for e in edges),
                " ".join(e["source_qn"] for e in reverse_edges),
                code,
            ]
        )
        expand_item_hits = _signal_hits(signal_text, expand_item)

        results.append({
            "qualified_name": qn,
            "block_type": r["block_type"],
            "file_path": r["file_path"],
            "module_name": r["module_name"],
            "language": r["language"],
            "start_line": start,
            "end_line": end,
            "code": code,
            "decoration_meta": decoration_meta,
            "signature": r["signature"],
            "parent_class": r["parent_class"],
            "inheritance_base": r["inheritance_base"],
            "edges": [{"target": e["target_qn"], "type": e["edge_type"]} for e in edges],
            "reverse_edges": [{"source": e["source_qn"], "type": e["edge_type"]} for e in reverse_edges],
            "expand_item_hits": expand_item_hits,
        })

    if expand_item:
        results.sort(key=lambda item: len(item.get("expand_item_hits", [])), reverse=True)

    return results


# Edge priority: lower = more important; only top 5 are shown
_EDGE_PRIORITY = {
    "rpc_routing": 0,
    "inheritance": 1,
    "static_call": 2,
    "type_dependency": 3,
}
_MAX_EDGES = 5


def _format_edges(edges: list[dict[str, str]]) -> str:
    sorted_edges = sorted(edges, key=lambda e: _EDGE_PRIORITY.get(e["type"], 99))
    shown = []
    for e in sorted_edges[:_MAX_EDGES]:
        etype = e["type"]
        target = e["target"]
        label = {"rpc_routing": "RPC", "inheritance": "Base", "static_call": "Call"}.get(etype, "Dep")
        shown.append(f"{label}:{target}")
    result = f"[Rel] {' | '.join(shown)}"
    if len(edges) > _MAX_EDGES:
        result += f"\n[Rel] ...+{len(edges) - _MAX_EDGES} more"
    return result


def _format_meta_display(meta: dict | None, fw: Any) -> list[str]:
    """Format decoration metadata into display parts for [Meta] line."""
    if not meta:
        return []
    # Use framework callback if available
    if fw.format_meta_display is not None:
        return fw.format_meta_display(meta)
    # Generic fallback: format without framework-specific routing info
    return [f"{macro}({','.join(params)})" for macro, params in meta.items()]


def _apply_view(
    code: str,
    view: str,
    *,
    block_type: str | None = None,
    qualified_name: str | None = None,
    child_symbols: list[dict] | None = None,
    lang: Any | None = None,
    fw: Any | None = None,
) -> str:
    from .code_block_summary import apply_view
    return apply_view(
        code, view,
        block_type=block_type,
        qualified_name=qualified_name,
        child_symbols=child_symbols,
        lang=lang,
        fw=fw,
    )


def format_symbol_response(entry: dict[str, Any], view: str = "full") -> str:
    """Format a symbol entry with [System Hint] header per plan.md."""
    lang, fw = _resolve_lang_fw(entry.get("language", "cpp"))
    lines = []
    lines.append(f"[Hint] {entry['qualified_name']} | {entry['file_path']}")

    # Decoration Metadata (compact, single line)
    meta_parts = _format_meta_display(entry.get("decoration_meta"), fw)
    if meta_parts:
        lines.append(f"[Meta] {' '.join(meta_parts)}")

    # Signal enrichment metadata (compact)
    expand_item_hits = entry.get("expand_item_hits") or []
    if expand_item_hits:
        lines.append(f"[Signal] matched: {', '.join(expand_item_hits)}")

    # Static Relations — prioritized, limited to top 5
    edges = entry.get("edges", [])
    if edges:
        lines.append(_format_edges(edges))

    # Inheritance base (fallback if not in edges)
    base = entry.get("inheritance_base")
    if base and not any(e["type"] == "inheritance" for e in edges if e["target"] == base):
        lines.append(f"[Rel] Base:{base}")

    if view == "meta":
        return "\n".join(lines)

    code = _apply_view(
        entry["code"], view,
        block_type=entry.get("block_type"),
        qualified_name=entry.get("qualified_name"),
        lang=lang,
        fw=fw,
    )
    lines.append("---")
    lines.append(code)
    return "\n".join(lines)


# ── Search_FTS query ─────────────────────────────────────────────────

def _fts5_escape(query: str) -> str:
    import re
    words = re.findall(r'[A-Za-z0-9_]{3,}', query)
    if not words:
        stripped = query.strip()
        if len(stripped) >= 3:
            words = [stripped]
    if not words:
        return '""'
    return " AND ".join(f'"{w}"' for w in words)


def search_fts(
    conn: sqlite3.Connection,
    keyword: str,
    path_filter: str = "",
    expand_item: list[str] | None = None,
    limit: int = 30,
) -> list[dict[str, Any]]:
    """FTS5 search returning grep-style results (hit line + 2 lines context)."""
    fts_query = _fts5_escape(keyword)
    expand_item = _normalize_expand_item(expand_item)

    # Get matching file IDs
    if path_filter:
        # Apply module/path filter — match module_name exactly OR file_path prefix
        fetch_limit = limit * (8 if expand_item else 5)
        ranked = [dict(r) for r in conn.execute(
            "SELECT file_content_fts.rowid AS fts_rowid, bm25(file_content_fts) AS rank "
            "FROM file_content_fts "
            "JOIN file_content fc ON fc.file_id = file_content_fts.rowid "
            "WHERE file_content_fts MATCH ? AND (fc.module_name = ? OR fc.file_path LIKE ? || '%') "
            "ORDER BY rank LIMIT ?",
            (fts_query, path_filter, path_filter + "/", fetch_limit),
        ).fetchall()]
    else:
        ranked = [dict(r) for r in conn.execute(
            "SELECT file_content_fts.rowid AS fts_rowid, bm25(file_content_fts) AS rank "
            "FROM file_content_fts "
            "WHERE file_content_fts MATCH ? "
            "ORDER BY rank LIMIT ?",
            (fts_query, limit * (6 if expand_item else 3)),
        ).fetchall()]

    if not ranked:
        return []

    # For each matching file, find the hit lines and extract context
    results = []
    keyword_lower = keyword.lower()
    words = keyword_lower.split()

    for r in ranked:
        file_id = r["fts_rowid"]
        row = conn.execute(
            "SELECT file_path, module_name, content FROM file_content WHERE file_id = ?",
            (file_id,),
        ).fetchone()
        if not row:
            continue

        lines = row["content"].split("\n")
        hit_lines = []

        for i, line in enumerate(lines):
            line_lower = line.lower()
            if all(w in line_lower for w in words):
                hit_lines.append(i + 1)  # 1-based

        for hit_line in hit_lines[:5]:  # Max 5 hits per file
            # Extract context: 2 lines before + hit + 2 lines after
            ctx_start = max(0, hit_line - 3)  # 0-based, 2 lines before
            ctx_end = min(len(lines), hit_line + 2)  # 0-based, 2 lines after
            context_lines = lines[ctx_start : ctx_end]

            # Find enclosing symbol for block metadata
            block_info = _find_enclosing_symbol(conn, file_id, hit_line)

            result = {
                "file_path": row["file_path"],
                "module_name": row["module_name"],
                "hit_line": hit_line,
                "context": "\n".join(context_lines),
            }
            if block_info:
                result["block_type"] = block_info["block_type"]
                result["block_name"] = block_info["qualified_name"]
                result["block_range"] = f"{block_info['start_line']}-{block_info['end_line']}"

            if expand_item:
                signal_text = "\n".join(
                    [
                        row["file_path"] or "",
                        row["module_name"] or "",
                        result.get("block_name", ""),
                        result["context"],
                        row["content"],
                    ]
                )
                hits = _signal_hits(signal_text, expand_item)
                if hits:
                    result["expand_item_hits"] = hits

            results.append(result)

        if len(results) >= limit:
            break

    if expand_item:
        results.sort(key=lambda item: len(item.get("expand_item_hits", [])), reverse=True)

    return results[:limit]


def _find_enclosing_symbol(
    conn: sqlite3.Connection, file_id: int, line: int
) -> dict[str, Any] | None:
    """Find the deepest enclosing symbol for a line number."""
    row = conn.execute(
        """SELECT qualified_name, block_type, start_line, end_line
           FROM symbol_index
           WHERE file_id = ? AND start_line <= ? AND end_line >= ?
           ORDER BY (end_line - start_line) ASC
           LIMIT 1""",
        (file_id, line, line),
    ).fetchone()
    return dict(row) if row else None


# ── Directory structure ──────────────────────────────────────────────

def get_directory_structure(conn: sqlite3.Connection) -> dict[str, Any]:
    total = conn.execute("SELECT COUNT(*) AS c FROM file_content").fetchone()["c"]
    modules = [
        dict(r) for r in conn.execute(
            "SELECT module_name, COUNT(*) AS file_count "
            "FROM file_content GROUP BY module_name ORDER BY file_count DESC LIMIT 30"
        ).fetchall()
    ]
    total_modules = conn.execute(
        "SELECT COUNT(DISTINCT module_name) AS c FROM file_content"
    ).fetchone()["c"]

    return {
        "total_files": total,
        "total_modules": total_modules,
        "modules": modules,
    }


# ── Read_File_Range query ─────────────────────────────────────────────

def _find_intersecting_symbols(
    conn: sqlite3.Connection, file_id: int, start_line: int, end_line: int,
) -> list[dict[str, Any]]:
    rows = conn.execute(
        """SELECT id, qualified_name, block_type, start_line, end_line, decoration_meta,
                  parent_class, signature, inheritance_base
           FROM symbol_index
           WHERE file_id = ? AND start_line <= ? AND end_line >= ?
           ORDER BY (end_line - start_line) ASC""",
        (file_id, end_line, start_line),
    ).fetchall()
    return [dict(r) for r in rows]


def _collect_edges_for_symbols(
    conn: sqlite3.Connection, qualified_names: list[str],
) -> list[dict[str, str]]:
    seen: set[tuple[str, str]] = set()
    edges: list[dict[str, str]] = []
    for qn in qualified_names:
        for e in conn.execute(
            "SELECT target_qn, edge_type FROM strict_edges WHERE source_qn = ? ORDER BY edge_type, target_qn",
            (qn,),
        ).fetchall():
            key = (e["target_qn"], e["edge_type"])
            if key not in seen:
                seen.add(key)
                edges.append({"target": e["target_qn"], "type": e["edge_type"]})
    return edges


def read_file_range(
    conn: sqlite3.Connection,
    file_path: str,
    start_line: int,
    end_line: int,
    view: str = "full",
    expand_item: list[str] | None = None,
) -> dict[str, Any] | None:
    row = conn.execute(
        "SELECT file_id, module_name, content FROM file_content WHERE file_path = ?",
        (file_path,),
    ).fetchone()
    if not row:
        return None

    lines = row["content"].split("\n")
    code = "\n".join(lines[start_line - 1 : end_line])

    file_id = row["file_id"]
    symbols = _find_intersecting_symbols(conn, file_id, start_line, end_line)

    all_edges: list[dict[str, str]] = []
    decoration_meta_all: dict[str, list[str]] = {}
    for sym in symbols:
        qn = sym["qualified_name"]
        sym_edges = _collect_edges_for_symbols(conn, [qn])
        all_edges.extend(sym_edges)
        if sym["decoration_meta"]:
            decoration_meta_all.update(json.loads(sym["decoration_meta"]))

    # Deduplicate edges
    seen: set[tuple[str, str]] = set()
    deduped: list[dict[str, str]] = []
    for e in all_edges:
        key = (e["target"], e["type"])
        if key not in seen:
            seen.add(key)
            deduped.append(e)

    # Signal enrichment
    expand_item = _normalize_expand_item(expand_item)
    signal_text = "\n".join([
        file_path,
        row["module_name"] or "",
        " ".join(s["qualified_name"] for s in symbols),
        " ".join(e["target"] for e in deduped),
        code,
    ])
    expand_item_hits = _signal_hits(signal_text, expand_item)

    return {
        "file_path": file_path,
        "module_name": row["module_name"],
        "start_line": start_line,
        "end_line": end_line,
        "code": code,
        "symbols": symbols,
        "edges": deduped,
        "decoration_meta": decoration_meta_all or None,
        "expand_item_hits": expand_item_hits,
    }


def format_file_range_response(entry: dict[str, Any], view: str = "full") -> str:
    lines: list[str] = []
    lines.append(f"[Hint] {entry['file_path']}:{entry['start_line']}-{entry['end_line']}")

    # Determine language from symbols (use first symbol's language)
    symbols = entry.get("symbols", [])
    file_language = symbols[0].get("language", "cpp") if symbols else "cpp"
    lang, fw = _resolve_lang_fw(file_language)

    # Module
    if entry.get("module_name"):
        lines.append(f"[Module] {entry['module_name']}")

    # Symbols covered by this range
    if symbols:
        sym_strs = []
        for s in symbols[:8]:
            sym_strs.append(f"{s['qualified_name']} ({s['block_type']}) {s['start_line']}-{s['end_line']}")
        lines.append(f"[Symbol] {' | '.join(sym_strs)}")
        if len(symbols) > 8:
            lines.append(f"[Symbol] ...+{len(symbols) - 8} more")

    # Decoration Metadata
    meta_parts = _format_meta_display(entry.get("decoration_meta"), fw)
    if meta_parts:
        lines.append(f"[Meta] {' '.join(meta_parts)}")

    # Signal enrichment
    expand_item_hits = entry.get("expand_item_hits") or []
    if expand_item_hits:
        lines.append(f"[Signal] matched: {', '.join(expand_item_hits)}")

    # Edges (merged from all symbols, up to 10)
    edges = entry.get("edges", [])
    if edges:
        sorted_edges = sorted(edges, key=lambda e: _EDGE_PRIORITY.get(e["type"], 99))[:10]
        shown = []
        for e in sorted_edges:
            label = {"rpc_routing": "RPC", "inheritance": "Base", "static_call": "Call"}.get(e["type"], "Dep")
            shown.append(f"{label}:{e['target']}")
        lines.append(f"[Rel] {' | '.join(shown)}")
        if len(edges) > 10:
            lines.append(f"[Rel] ...+{len(edges) - 10} more")

    if view == "meta":
        return "\n".join(lines)

    single_block_type = symbols[0]["block_type"] if len(symbols) == 1 else None
    code = _apply_view(
        entry["code"], view,
        block_type=single_block_type,
        child_symbols=symbols if len(symbols) > 1 else None,
        lang=lang,
        fw=fw,
    )
    lines.append("---")
    lines.append(code)
    return "\n".join(lines)
