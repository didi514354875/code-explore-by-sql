from __future__ import annotations

import json
import re
import sqlite3
from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path
from typing import Any

SOURCE_EXTENSIONS = {".h", ".hpp", ".hh", ".inl", ".cpp", ".cc", ".cxx", ".cs", ".usf", ".ush", ".hlsl"}
DEFAULT_EXCLUDE_PARTS = {
    ".git",
    ".vs",
    "Binaries",
    "Build",
    "DerivedDataCache",
    "Intermediate",
    "Saved",
    "ThirdParty",
}


@dataclass(frozen=True)
class SourceFile:
    file_path: str
    module_name: str | None
    raw_content: str
    content_hash: str | None = None


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
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS source_files (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            file_path TEXT NOT NULL UNIQUE,
            module_name TEXT,
            raw_content TEXT NOT NULL,
            content_hash TEXT,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP
        );

        CREATE VIRTUAL TABLE IF NOT EXISTS source_files_fts USING fts5(
            file_path,
            module_name,
            raw_content,
            content=source_files,
            content_rowid=id,
            tokenize="trigram"
        );

        CREATE TRIGGER IF NOT EXISTS source_files_ai AFTER INSERT ON source_files BEGIN
            INSERT INTO source_files_fts(rowid, file_path, module_name, raw_content)
            VALUES (new.id, new.file_path, new.module_name, new.raw_content);
        END;

        CREATE TRIGGER IF NOT EXISTS source_files_ad AFTER DELETE ON source_files BEGIN
            INSERT INTO source_files_fts(source_files_fts, rowid, file_path, module_name, raw_content)
            VALUES ('delete', old.id, old.file_path, old.module_name, old.raw_content);
        END;

        CREATE TRIGGER IF NOT EXISTS source_files_au AFTER UPDATE ON source_files BEGIN
            INSERT INTO source_files_fts(source_files_fts, rowid, file_path, module_name, raw_content)
            VALUES ('delete', old.id, old.file_path, old.module_name, old.raw_content);
            INSERT INTO source_files_fts(rowid, file_path, module_name, raw_content)
            VALUES (new.id, new.file_path, new.module_name, new.raw_content);
        END;

        CREATE TABLE IF NOT EXISTS query_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            query_text TEXT NOT NULL,
            fts_match TEXT,
            hit_file_ids TEXT DEFAULT '[]',
            hit_count INTEGER DEFAULT 0,
            was_useful INTEGER,
            refinement TEXT,
            template_id INTEGER,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        );

        CREATE VIRTUAL TABLE IF NOT EXISTS query_logs_fts USING fts5(
            query_text,
            fts_match,
            content=query_logs,
            content_rowid=id,
            tokenize="trigram"
        );

        CREATE TRIGGER IF NOT EXISTS query_logs_ai AFTER INSERT ON query_logs BEGIN
            INSERT INTO query_logs_fts(rowid, query_text, fts_match)
            VALUES (new.id, new.query_text, new.fts_match);
        END;

        CREATE TRIGGER IF NOT EXISTS query_logs_ad AFTER DELETE ON query_logs BEGIN
            INSERT INTO query_logs_fts(query_logs_fts, rowid, query_text, fts_match)
            VALUES ('delete', old.id, old.query_text, old.fts_match);
        END;

        CREATE TABLE IF NOT EXISTS query_note (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            query_log_id INTEGER NOT NULL REFERENCES query_logs(id) ON DELETE CASCADE,
            adopted_file_id INTEGER REFERENCES source_files(id),
            was_useful INTEGER,
            refinement TEXT,
            note TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        );

        CREATE INDEX IF NOT EXISTS idx_note_log ON query_note(query_log_id);
        CREATE INDEX IF NOT EXISTS idx_logs_created ON query_logs(created_at);
        """
    )
    conn.commit()

    _migrate_legacy(conn)
    _migrate_add_adopted_file_id(conn)
    _ensure_view(conn)


def _migrate_legacy(conn: sqlite3.Connection) -> None:
    """One-time migration: drop query_templates if it exists from older schema."""
    try:
        conn.execute("DROP TABLE IF EXISTS query_templates")
        conn.execute("DROP TABLE IF EXISTS query_templates_fts")
        conn.execute("DROP TRIGGER IF EXISTS query_templates_ai")
        conn.execute("DROP TRIGGER IF EXISTS query_templates_ad")
        conn.execute("DROP TRIGGER IF EXISTS query_templates_au")
        conn.commit()
    except sqlite3.OperationalError:
        pass


def _migrate_add_adopted_file_id(conn: sqlite3.Connection) -> None:
    """Add adopted_file_id column to query_note if missing."""
    try:
        conn.execute("ALTER TABLE query_note ADD COLUMN adopted_file_id INTEGER REFERENCES source_files(id)")
        conn.commit()
    except sqlite3.OperationalError:
        pass  # Column already exists
    try:
        conn.execute("CREATE INDEX IF NOT EXISTS idx_note_adopted ON query_note(adopted_file_id)")
        conn.commit()
    except sqlite3.OperationalError:
        pass


def _ensure_view(conn: sqlite3.Connection) -> None:
    """Create or recreate query_log_view (must run after adopted_file_id migration)."""
    conn.execute("DROP VIEW IF EXISTS query_log_view")
    conn.execute("""
        CREATE VIEW query_log_view AS
        SELECT
            ql.id AS log_id,
            ql.query_text,
            ql.fts_match,
            ql.hit_file_ids,
            ql.hit_count,
            ql.created_at AS query_time,
            qn.id AS note_id,
            qn.adopted_file_id,
            qn.was_useful,
            qn.refinement,
            qn.note,
            qn.created_at AS feedback_time,
            sf.file_path AS adopted_file_path
        FROM query_logs ql
        LEFT JOIN query_note qn ON qn.query_log_id = ql.id
        LEFT JOIN source_files sf ON qn.adopted_file_id = sf.id
    """)
    conn.commit()


def upsert_source_file(conn: sqlite3.Connection, source: SourceFile) -> int:
    conn.execute(
        """
        INSERT INTO source_files(file_path, module_name, raw_content, content_hash, updated_at)
        VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
        ON CONFLICT(file_path) DO UPDATE SET
            module_name=excluded.module_name,
            raw_content=excluded.raw_content,
            content_hash=excluded.content_hash,
            updated_at=CURRENT_TIMESTAMP
        """,
        (source.file_path, source.module_name, source.raw_content, source.content_hash),
    )
    row = conn.execute("SELECT id FROM source_files WHERE file_path = ?", (source.file_path,)).fetchone()
    return int(row["id"])


def get_source_by_path(conn: sqlite3.Connection, file_path: str) -> sqlite3.Row | None:
    return conn.execute("SELECT * FROM source_files WHERE file_path = ?", (file_path,)).fetchone()


def get_source_anchored(
    conn: sqlite3.Connection,
    file_path: str,
    anchor: str,
    context_chars: int = 500,
) -> dict[str, Any] | None:
    margin = context_chars // 2
    row = conn.execute(
        """
        SELECT
            file_path,
            module_name,
            instr(raw_content, ?) AS anchor_pos,
            length(raw_content) AS total_chars,
            CASE
                WHEN instr(raw_content, ?) > 0 THEN
                    substr(raw_content,
                           max(1, instr(raw_content, ?) - ?),
                           ?)
                ELSE NULL
            END AS content
        FROM source_files
        WHERE file_path = ?
        """,
        (anchor, anchor, anchor, margin, context_chars, file_path),
    ).fetchone()
    if row is None or row["anchor_pos"] == 0:
        return None
    return dict(row)


def _fts5_escape(query: str) -> str:
    words = re.findall(r'[A-Za-z0-9_]{3,}', query)
    if not words:
        stripped = query.strip()
        if len(stripped) >= 3:
            words = [stripped]
    if not words:
        return '""'
    return " AND ".join(f'"{w.replace(chr(34), chr(34)+chr(34))}"' for w in words)


def _extract_search_terms(query: str) -> list[str]:
    """Extract meaningful keywords from a query for history matching.

    General approach: pull all alphanumeric words >= 3 chars, deduplicate
    case-insensitively, skip FTS5/SQL operators. Domain-agnostic.
    """
    _STOP_WORDS = frozenset({
        'and', 'or', 'not', 'in', 'is', 'null', 'like', 'the', 'for',
        'from', 'with', 'where', 'select', 'class', 'void', 'struct',
    })

    raw_words = re.findall(r'[A-Za-z_][A-Za-z0-9_]{2,}', query)

    seen: set[str] = set()
    terms: list[str] = []
    for w in raw_words:
        low = w.lower()
        if low not in seen and low not in _STOP_WORDS:
            seen.add(low)
            terms.append(w)

    if not terms:
        stripped = query.strip()
        if len(stripped) >= 3:
            terms = [stripped]

    return terms[:12]


def _search_fts(
    conn: sqlite3.Connection, fts_query: str, module: str | None = None, limit: int = 20
) -> list[dict[str, Any]]:
    sql = (
        "SELECT sf.id, sf.file_path, sf.module_name, bm25(source_files_fts) AS rank, "
        "snippet(source_files_fts, 2, '[', ']', ' … ', 16) AS snippet "
        "FROM source_files_fts JOIN source_files sf ON sf.id = source_files_fts.rowid "
        "WHERE source_files_fts MATCH ?"
    )
    params: list[Any] = [fts_query]
    if module:
        sql += " AND sf.module_name = ?"
        params.append(module)
    sql += " ORDER BY rank LIMIT ?"
    params.append(limit)
    return [dict(row) for row in conn.execute(sql, params)]


def search_source(
    conn: sqlite3.Connection, query: str, module: str | None = None, limit: int = 20
) -> list[dict[str, Any]]:
    return _search_fts(conn, _fts5_escape(query), module, limit)


def search_source_raw(
    conn: sqlite3.Connection, fts_query: str, module: str | None = None, limit: int = 20
) -> list[dict[str, Any]]:
    return _search_fts(conn, fts_query, module, limit)


def log_query(
    conn: sqlite3.Connection,
    query_text: str,
    fts_match: str | None,
    hit_file_ids: Iterable[int],
) -> int:
    ids = list(dict.fromkeys(hit_file_ids))
    if ids:
        rows = conn.execute(
            f"SELECT id FROM source_files WHERE id IN ({','.join('?' * len(ids))})", ids
        ).fetchall()
        valid_set = {r["id"] for r in rows}
        ids = [i for i in ids if i in valid_set]

    conn.execute(
        """
        INSERT INTO query_logs(query_text, fts_match, hit_file_ids, hit_count)
        VALUES (?, ?, ?, ?)
        """,
        (query_text, fts_match, json.dumps(ids), len(ids)),
    )
    conn.commit()
    return int(conn.execute("SELECT last_insert_rowid()").fetchone()[0])


def _find_candidate_files_from_history(
    conn: sqlite3.Connection, search_terms: list[str], top_k: int = 10
) -> list[int]:
    """Find candidate file IDs from similar past queries' hit_file_ids.

    Uses FTS5 on query_logs_fts (OR logic: any term match qualifies).
    Ranks by composite score (feedback boost + time decay).
    """
    if not search_terms:
        return []
    terms = [t for t in search_terms if len(t) >= 3]
    if not terms:
        return []

    fts_or = " OR ".join(f'"{t}"' for t in terms)

    rows = conn.execute(
        """
        SELECT ql.id, ql.hit_file_ids, ql.hit_count, ql.created_at
        FROM query_logs_fts qft
                JOIN query_logs ql ON ql.id = qft.rowid
                LEFT JOIN query_note qn ON qn.query_log_id = ql.id
        WHERE qft.query_logs_fts MATCH ?
        GROUP BY ql.id
        ORDER BY (
            COUNT(CASE WHEN qn.was_useful = 1 THEN 1 END) * 5
            - COUNT(CASE WHEN qn.was_useful = 0 THEN 1 END) * 3
            + CASE WHEN ql.hit_count BETWEEN 1 AND 50 THEN 1 ELSE 0 END
        ) * (1.0 / (1 + julianday('now') - julianday(ql.created_at))) DESC
        LIMIT ?
        """,
        (fts_or, top_k),
    ).fetchall()

    candidates: list[int] = []
    seen: set[int] = set()
    for row in rows:
        for fid in json.loads(row["hit_file_ids"]):
            if fid not in seen:
                candidates.append(fid)
                seen.add(fid)
    return candidates


def search_source_with_feedback(
    conn: sqlite3.Connection,
    *,
    query: str | None = None,
    raw_query: str | None = None,
    expanded_terms: list[str] | None = None,
    module: str | None = None,
    limit: int = 20,
) -> list[dict[str, Any]]:
    """Search with history-first logic and automatic query logging.

    Path 1: Find similar past queries via LIKE OR → collect hit_file_ids
            as candidate set → FTS5 search within candidates (fast, targeted).
    Path 2: Fallback to full FTS5 search (no history or candidates yielded nothing).

    expanded_terms: extra keywords from intent expansion (agent-supplied).
    """
    query_text = raw_query or query
    if not query_text:
        return []
    fts_query = raw_query if raw_query else _fts5_escape(query)
    terms = _extract_search_terms(query_text)

    # Merge agent-supplied expanded terms
    if expanded_terms:
        seen = {t.lower() for t in terms}
        for t in expanded_terms:
            if len(t) >= 3 and t.lower() not in seen:
                seen.add(t.lower())
                terms.append(t)

    # Path 1: history candidates + targeted FTS5
    candidates = _find_candidate_files_from_history(conn, terms)
    if candidates:
        ph = ",".join("?" * len(candidates))
        rows = conn.execute(
            f"""
            SELECT sf.id, sf.file_path, sf.module_name,
                   bm25(source_files_fts) AS rank,
                   snippet(source_files_fts, 2, '[', ']', ' … ', 16) AS snippet
            FROM source_files_fts
            JOIN source_files sf ON sf.id = source_files_fts.rowid
            WHERE source_files_fts MATCH ? AND sf.id IN ({ph})
            """,
            [fts_query, *candidates],
        ).fetchall()

        if rows:
            results = [dict(r) for r in rows]
            # Sort by candidate order (adopted files ranked higher) + BM25
            rank_map = {fid: i for i, fid in enumerate(candidates)}
            results.sort(key=lambda r: (rank_map.get(r["id"], 999), r["rank"]))
            results = results[:limit]
            for r in results:
                r["source"] = "history_refined"
            log_query(conn, query_text, fts_query, [r["id"] for r in results])
            return results

    # Path 2: fallback to full FTS5
    rows = _search_fts(conn, fts_query, module, limit)
    results = [dict(r) for r in rows]
    for r in results:
        r["source"] = "fts"
    log_query(conn, query_text, fts_query, [r["id"] for r in results])
    return results


def record_feedback(conn: sqlite3.Connection, file_path: str, was_useful: bool = True) -> bool:
    """Mark a file as adopted if it was in recent search results."""
    file_row = conn.execute(
        "SELECT id FROM source_files WHERE file_path = ?", (file_path,)
    ).fetchone()
    if file_row is None:
        return False
    file_id = file_row["id"]

    log_row = conn.execute(
        """
        SELECT ql.id FROM query_logs ql, json_each(ql.hit_file_ids) AS je
        WHERE ql.created_at > datetime('now', '-2 hours')
          AND je.value = ?
        ORDER BY ql.created_at DESC LIMIT 1
        """,
        (file_id,),
    ).fetchone()
    if log_row is None:
        return False

    existing = conn.execute(
        "SELECT id FROM query_note WHERE query_log_id = ?", (log_row["id"],)
    ).fetchone()
    if existing:
        conn.execute(
            "UPDATE query_note SET was_useful = ?, adopted_file_id = ? WHERE query_log_id = ?",
            (int(was_useful), file_id, log_row["id"]),
        )
    else:
        conn.execute(
            "INSERT INTO query_note(query_log_id, adopted_file_id, was_useful) VALUES (?, ?, ?)",
            (log_row["id"], file_id, int(was_useful)),
        )
    conn.commit()
    return True


def prune_stale_data(conn: sqlite3.Connection) -> dict[str, int]:
    """Remove dead data. Returns counts of deleted items."""
    stale_logs = conn.execute(
        """
        DELETE FROM query_logs
        WHERE created_at < datetime('now', '-60 days')
          AND id NOT IN (SELECT query_log_id FROM query_note)
        """
    ).rowcount

    stale_notes = conn.execute(
        """
        DELETE FROM query_note
        WHERE created_at < datetime('now', '-90 days')
        """
    ).rowcount

    if stale_logs + stale_notes > 100:
        conn.execute("VACUUM")
    conn.commit()
    return {"logs_deleted": stale_logs, "notes_deleted": stale_notes}
