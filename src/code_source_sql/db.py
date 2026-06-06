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
            content_hash TEXT,
            language TEXT NOT NULL DEFAULT 'cpp'
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
        conn.execute("ALTER TABLE file_content ADD COLUMN language TEXT NOT NULL DEFAULT 'cpp'")
    except Exception:
        pass  # Column already exists
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
                content: str, content_hash: str | None = None,
                language: str = "cpp") -> int:
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
        """INSERT INTO file_content(file_path, module_name, content, content_hash, language)
           VALUES (?, ?, ?, ?, ?)
           ON CONFLICT(file_path) DO UPDATE SET
               module_name=excluded.module_name,
               content=excluded.content,
               content_hash=excluded.content_hash,
               language=excluded.language""",
        (file_path, module_name, content, content_hash, language),
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
    view: str = "full",
    expand_item: list[str] | None = None,
) -> list[dict[str, Any]]:
    """Look up symbols by qualified_name. Returns minimal identity + code."""
    expand_item = _normalize_expand_item(expand_item)

    # 1. Exact match
    rows = conn.execute(
        """SELECT si.*, fc.file_path, fc.content
           FROM symbol_index si
           JOIN file_content fc ON fc.file_id = si.file_id
           WHERE si.qualified_name = ?
           ORDER BY si.file_id, si.start_line""",
        (qualified_name,),
    ).fetchall()

    # 2. Type prefix resolution
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
                        """SELECT si.*, fc.file_path, fc.content
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

    # 3. Partial match
    if not rows:
        rows = conn.execute(
            """SELECT si.*, fc.file_path, fc.content
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
        lines = r["content"].split("\n")
        code = "\n".join(lines[start - 1 : end])

        qn = r["qualified_name"]

        # Signal text for ranking only
        signal_text = "\n".join([qn, r["file_path"] or "", r["signature"] or "", code])
        expand_item_hits = _signal_hits(signal_text, expand_item)

        results.append({
            "qn": qn,
            "type": r["block_type"],
            "file": r["file_path"],
            "range": [start, end],
            "_code_raw": code,
            "_expand_item_hits": expand_item_hits,
            "_language": r["language"],
            "_block_type_raw": r["block_type"],
        })

    if expand_item:
        results.sort(key=lambda item: len(item.get("_expand_item_hits", [])), reverse=True)

    # Apply view to best match only, strip internals
    for i, item in enumerate(results):
        if i == 0 and view != "meta":
            lang, fw = _resolve_lang_fw(item["_language"])
            item["code"] = _apply_view(
                item["_code_raw"], view,
                block_type=item["_block_type_raw"],
                qualified_name=item["qn"],
                lang=lang, fw=fw,
                max_lines=80 if view == "signature" else 0,
            )
        # Strip internal fields
        item.pop("_code_raw", None)
        item.pop("_expand_item_hits", None)
        item.pop("_language", None)
        item.pop("_block_type_raw", None)

    return results


def _apply_view(
    code: str,
    view: str,
    *,
    block_type: str | None = None,
    qualified_name: str | None = None,
    child_symbols: list[dict] | None = None,
    lang: Any | None = None,
    fw: Any | None = None,
    max_lines: int = 0,
) -> str:
    from .code_block_summary import apply_view
    return apply_view(
        code, view,
        block_type=block_type,
        qualified_name=qualified_name,
        child_symbols=child_symbols,
        lang=lang,
        fw=fw,
        max_lines=max_lines,
    )


# ── Search_FTS query ─────────────────────────────────────────────────

def _fts_ranked(
    conn: sqlite3.Connection,
    fts_query: str,
    path_filter: str,
    expand_item: list[str],
    limit: int,
) -> list[dict[str, Any]]:
    """Execute FTS5 ranked query, return list of {fts_rowid, rank}."""
    if path_filter:
        fetch_limit = limit * (8 if expand_item else 5)
        return [dict(r) for r in conn.execute(
            "SELECT file_content_fts.rowid AS fts_rowid, bm25(file_content_fts) AS rank "
            "FROM file_content_fts "
            "JOIN file_content fc ON fc.file_id = file_content_fts.rowid "
            "WHERE file_content_fts MATCH ? AND (fc.module_name = ? OR fc.file_path LIKE ? || '%') "
            "ORDER BY rank LIMIT ?",
            (fts_query, path_filter, path_filter + "/", fetch_limit),
        ).fetchall()]
    return [dict(r) for r in conn.execute(
        "SELECT file_content_fts.rowid AS fts_rowid, bm25(file_content_fts) AS rank "
        "FROM file_content_fts "
        "WHERE file_content_fts MATCH ? "
        "ORDER BY rank LIMIT ?",
        (fts_query, limit * (6 if expand_item else 3)),
    ).fetchall()]


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
    keyword: str = "",
    path_filter: str = "",
    expand_item: list[str] | None = None,
    raw_query: str = "",
    limit: int = 30,
) -> list[dict[str, Any]]:
    """FTS5 search returning located code blocks with preview.

    Query modes (mutually exclusive — use one):
      - keyword: auto-escaped AND of tokens. Simple, safe.
      - raw_query: passed directly to FTS5 MATCH. Supports column filters,
        OR, NOT, and all FTS5 syntax.

    FTS5 columns: file_path, module_name, content (all trigram).
    All terms must be ≥3 characters.
    """
    if raw_query:
        fts_query = raw_query
    elif keyword:
        fts_query = _fts5_escape(keyword)
    else:
        return []
    expand_item = _normalize_expand_item(expand_item)

    # Execute FTS query — catch malformed raw_query
    try:
        ranked = _fts_ranked(conn, fts_query, path_filter, expand_item, limit)
    except Exception:
        return []
    if not ranked:
        return []

    if not ranked:
        return []

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
            block_info = _find_enclosing_symbol(conn, file_id, hit_line)

            result = {
                "file": row["file_path"],
                "line": hit_line,
            }
            if block_info:
                result["block"] = block_info["qualified_name"]
                result["block_type"] = block_info["block_type"]
            else:
                # No enclosing symbol — suggest a context window for read_file_range
                total_lines = len(lines)
                ctx_start = max(1, hit_line - 5)
                ctx_end = min(total_lines, hit_line + 25)
                result["range"] = [ctx_start, ctx_end]

            if expand_item:
                signal_text = "\n".join([
                    row["file_path"] or "",
                    row["module_name"] or "",
                    result.get("block", ""),
                    row["content"],
                ])
                hits = _signal_hits(signal_text, expand_item)
                if hits:
                    result["_expand_item_hits"] = hits  # internal ranking only

            results.append(result)

        if len(results) >= limit:
            break

    if expand_item:
        results.sort(key=lambda item: len(item.get("_expand_item_hits", [])), reverse=True)

    # Strip internal ranking field before returning
    for item in results:
        item.pop("_expand_item_hits", None)

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


def _get_language_for_symbol(conn: sqlite3.Connection, file_id: int, line: int) -> str:
    """Get language string for a symbol at a given position, defaulting to 'cpp'."""
    row = conn.execute(
        "SELECT language FROM symbol_index WHERE file_id = ? AND start_line <= ? AND end_line >= ? LIMIT 1",
        (file_id, line, line),
    ).fetchone()
    return row["language"] if row else "cpp"


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
                  parent_class, signature, inheritance_base, language
           FROM symbol_index
           WHERE file_id = ? AND start_line <= ? AND end_line >= ?
           ORDER BY (end_line - start_line) ASC""",
        (file_id, end_line, start_line),
    ).fetchall()
    return [dict(r) for r in rows]


def read_file_range(
    conn: sqlite3.Connection,
    file_path: str,
    start_line: int,
    end_line: int,
    view: str = "full",
    expand_item: list[str] | None = None,
) -> dict[str, Any] | None:
    row = conn.execute(
        "SELECT file_id, content, language FROM file_content WHERE file_path = ?",
        (file_path,),
    ).fetchone()
    if not row:
        return None

    lines = row["content"].split("\n")
    code = "\n".join(lines[start_line - 1 : end_line])

    file_id = row["file_id"]
    file_language = row["language"]
    symbols_full = _find_intersecting_symbols(conn, file_id, start_line, end_line)

    # Apply view to code
    if view != "meta":
        lang, fw = _resolve_lang_fw(file_language)
        single_block_type = symbols_full[0]["block_type"] if len(symbols_full) == 1 else None
        code = _apply_view(
            code, view,
            block_type=single_block_type,
            qualified_name=symbols_full[0]["qualified_name"] if len(symbols_full) == 1 else None,
            child_symbols=symbols_full if len(symbols_full) > 1 else None,
            lang=lang, fw=fw,
            max_lines=80 if view == "signature" else 0,
        )

    # Simplified symbols for output
    symbols_out = [
        {"qn": s["qualified_name"], "type": s["block_type"], "range": [s["start_line"], s["end_line"]]}
        for s in symbols_full
    ]

    result: dict[str, Any] = {
        "file": file_path,
        "range": [start_line, end_line],
    }
    if symbols_out:
        result["symbols"] = symbols_out
    if view != "meta":
        result["code"] = code
    return result
