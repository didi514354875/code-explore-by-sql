from __future__ import annotations

import json
import sqlite3
from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .chunker import CodeChunk

SOURCE_EXTENSIONS = {".h", ".hpp", ".hh", ".inl", ".cpp", ".cc", ".cxx", ".cs"}
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
            content_rowid=id
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

        CREATE TABLE IF NOT EXISTS code_chunks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            file_id INTEGER NOT NULL,
            symbol_name TEXT,
            symbol_type TEXT,
            signature TEXT,
            body TEXT NOT NULL,
            start_line INTEGER NOT NULL,
            end_line INTEGER NOT NULL,
            comment TEXT,
            extraction_method TEXT DEFAULT 'heuristic',
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(file_id, symbol_name, start_line, end_line),
            FOREIGN KEY (file_id) REFERENCES source_files(id) ON DELETE CASCADE
        );

        CREATE VIRTUAL TABLE IF NOT EXISTS code_chunks_fts USING fts5(
            symbol_name,
            symbol_type,
            signature,
            body,
            content=code_chunks,
            content_rowid=id
        );

        CREATE TRIGGER IF NOT EXISTS code_chunks_ai AFTER INSERT ON code_chunks BEGIN
            INSERT INTO code_chunks_fts(rowid, symbol_name, symbol_type, signature, body)
            VALUES (new.id, new.symbol_name, new.symbol_type, new.signature, new.body);
        END;

        CREATE TRIGGER IF NOT EXISTS code_chunks_ad AFTER DELETE ON code_chunks BEGIN
            INSERT INTO code_chunks_fts(code_chunks_fts, rowid, symbol_name, symbol_type, signature, body)
            VALUES ('delete', old.id, old.symbol_name, old.symbol_type, old.signature, old.body);
        END;

        CREATE TRIGGER IF NOT EXISTS code_chunks_au AFTER UPDATE ON code_chunks BEGIN
            INSERT INTO code_chunks_fts(code_chunks_fts, rowid, symbol_name, symbol_type, signature, body)
            VALUES ('delete', old.id, old.symbol_name, old.symbol_type, old.signature, old.body);
            INSERT INTO code_chunks_fts(rowid, symbol_name, symbol_type, signature, body)
            VALUES (new.id, new.symbol_name, new.symbol_type, new.signature, new.body);
        END;

        CREATE TABLE IF NOT EXISTS query_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            query_text TEXT NOT NULL,
            fts_match TEXT,
            hit_file_ids TEXT DEFAULT '[]',
            hit_count INTEGER DEFAULT 0,
            was_useful INTEGER,
            refinement TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS query_templates (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            intent_pattern TEXT NOT NULL,
            fts_template TEXT NOT NULL,
            chunk_strategy TEXT DEFAULT 'heuristic',
            intent_keywords TEXT DEFAULT '[]',
            useful_count INTEGER DEFAULT 0,
            success_rate REAL DEFAULT 0.0,
            example_queries TEXT DEFAULT '[]',
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP
        );

        CREATE VIRTUAL TABLE IF NOT EXISTS query_templates_fts USING fts5(
            intent_pattern,
            fts_template,
            intent_keywords,
            content=query_templates,
            content_rowid=id
        );

        CREATE TRIGGER IF NOT EXISTS query_templates_ai AFTER INSERT ON query_templates BEGIN
            INSERT INTO query_templates_fts(rowid, intent_pattern, fts_template, intent_keywords)
            VALUES (new.id, new.intent_pattern, new.fts_template, new.intent_keywords);
        END;

        CREATE TRIGGER IF NOT EXISTS query_templates_ad AFTER DELETE ON query_templates BEGIN
            INSERT INTO query_templates_fts(query_templates_fts, rowid, intent_pattern, fts_template, intent_keywords)
            VALUES ('delete', old.id, old.intent_pattern, old.fts_template, old.intent_keywords);
        END;

        CREATE TRIGGER IF NOT EXISTS query_templates_au AFTER UPDATE ON query_templates BEGIN
            INSERT INTO query_templates_fts(query_templates_fts, rowid, intent_pattern, fts_template, intent_keywords)
            VALUES ('delete', old.id, old.intent_pattern, old.fts_template, old.intent_keywords);
            INSERT INTO query_templates_fts(rowid, intent_pattern, fts_template, intent_keywords)
            VALUES (new.id, new.intent_pattern, new.fts_template, new.intent_keywords);
        END;
        """
    )
    _ensure_column(conn, "query_logs", "template_id", "INTEGER")
    _ensure_column(conn, "query_logs", "hit_chunk_ids", "TEXT DEFAULT '[]'")
    conn.commit()


def _ensure_column(conn: sqlite3.Connection, table: str, column: str, definition: str) -> None:
    columns = {row["name"] for row in conn.execute(f"PRAGMA table_info({table})")}
    if column not in columns:
        conn.execute(f"ALTER TABLE {table} ADD COLUMN {column} {definition}")


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


def search_source(
    conn: sqlite3.Connection, query: str, module: str | None = None, limit: int = 20
) -> list[dict[str, Any]]:
    sql = (
        "SELECT sf.id, sf.file_path, sf.module_name, bm25(source_files_fts) AS rank, "
        "snippet(source_files_fts, 2, '[', ']', ' … ', 16) AS snippet "
        "FROM source_files_fts JOIN source_files sf ON sf.id = source_files_fts.rowid "
        "WHERE source_files_fts MATCH ?"
    )
    params: list[Any] = [query]
    if module:
        sql += " AND sf.module_name = ?"
        params.append(module)
    sql += " ORDER BY rank LIMIT ?"
    params.append(limit)
    return [dict(row) for row in conn.execute(sql, params)]


def replace_chunks_for_file(conn: sqlite3.Connection, file_id: int, chunks: Iterable[CodeChunk]) -> int:
    conn.execute("DELETE FROM code_chunks WHERE file_id = ?", (file_id,))
    count = 0
    for chunk in chunks:
        conn.execute(
            """
            INSERT OR IGNORE INTO code_chunks(
                file_id, symbol_name, symbol_type, signature, body, start_line, end_line, comment, extraction_method
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                file_id,
                chunk.symbol_name,
                chunk.symbol_type,
                chunk.signature,
                chunk.body,
                chunk.start_line,
                chunk.end_line,
                chunk.comment,
                chunk.extraction_method,
            ),
        )
        count += 1
    return count


def get_cached_chunks(
    conn: sqlite3.Connection,
    file_id: int,
    symbol: str | None = None,
    limit: int = 50,
) -> list[dict[str, Any]]:
    sql = "SELECT * FROM code_chunks WHERE file_id = ?"
    params: list[Any] = [file_id]
    if symbol:
        sql += " AND lower(coalesce(symbol_name, '')) LIKE ?"
        params.append(f"%{symbol.lower()}%")
    sql += " ORDER BY start_line LIMIT ?"
    params.append(limit)
    return [dict(row) for row in conn.execute(sql, params)]


def search_chunks(
    conn: sqlite3.Connection,
    query: str,
    module: str | None = None,
    symbol_type: str | None = None,
    limit: int = 20,
    body_chars: int = 4000,
) -> list[dict[str, Any]]:
    sql = (
        "SELECT cc.id, cc.file_id, sf.file_path, sf.module_name, cc.symbol_name, cc.symbol_type, "
        "cc.signature, cc.body, cc.start_line, cc.end_line, bm25(code_chunks_fts) AS rank, "
        "snippet(code_chunks_fts, 3, '[', ']', ' … ', 24) AS snippet "
        "FROM code_chunks_fts "
        "JOIN code_chunks cc ON cc.id = code_chunks_fts.rowid "
        "JOIN source_files sf ON sf.id = cc.file_id "
        "WHERE code_chunks_fts MATCH ?"
    )
    params: list[Any] = [query]
    if module:
        sql += " AND sf.module_name = ?"
        params.append(module)
    if symbol_type:
        sql += " AND cc.symbol_type = ?"
        params.append(symbol_type)
    sql += " ORDER BY rank LIMIT ?"
    params.append(limit)
    rows = []
    for row in conn.execute(sql, params):
        item = dict(row)
        body = item.get("body") or ""
        item["body"] = body[:body_chars]
        item["truncated"] = len(body) > body_chars
        rows.append(item)
    return rows


def log_query(
    conn: sqlite3.Connection,
    query_text: str,
    fts_match: str | None,
    hit_file_ids: Iterable[int],
    hit_chunk_ids: Iterable[int] | None = None,
    was_useful: bool | None = None,
    refinement: str | None = None,
    template_id: int | None = None,
) -> int:
    ids = list(hit_file_ids)
    chunk_ids = list(hit_chunk_ids or [])
    conn.execute(
        """
        INSERT INTO query_logs(
            query_text, fts_match, hit_file_ids, hit_chunk_ids, hit_count, was_useful, refinement, template_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            query_text,
            fts_match,
            json.dumps(ids),
            json.dumps(chunk_ids),
            len(ids) + len(chunk_ids),
            None if was_useful is None else int(was_useful),
            refinement,
            template_id,
        ),
    )
    if template_id is not None and was_useful is not None:
        update_template_feedback(conn, template_id=template_id, query_text=query_text, was_useful=was_useful)
    conn.commit()
    return int(conn.execute("SELECT last_insert_rowid()").fetchone()[0])


def save_template(
    conn: sqlite3.Connection,
    intent_pattern: str,
    fts_template: str,
    chunk_strategy: str = "heuristic",
    intent_keywords: Iterable[str] | None = None,
) -> int:
    cursor = conn.execute(
        """
        INSERT INTO query_templates(intent_pattern, fts_template, chunk_strategy, intent_keywords, updated_at)
        VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
        """,
        (intent_pattern, fts_template, chunk_strategy, json.dumps(list(intent_keywords or []))),
    )
    conn.commit()
    return int(cursor.lastrowid)


def get_templates(conn: sqlite3.Connection, query: str | None = None, limit: int = 20) -> list[dict[str, Any]]:
    if query:
        rows = conn.execute(
            """
            SELECT qt.*, bm25(query_templates_fts) AS rank
            FROM query_templates_fts JOIN query_templates qt ON qt.id = query_templates_fts.rowid
            WHERE query_templates_fts MATCH ?
            ORDER BY success_rate DESC, useful_count DESC, rank LIMIT ?
            """,
            (query, limit),
        ).fetchall()
    else:
        rows = conn.execute(
            """
            SELECT * FROM query_templates
            ORDER BY success_rate DESC, useful_count DESC, updated_at DESC LIMIT ?
            """,
            (limit,),
        ).fetchall()
    return [dict(row) for row in rows]


def update_template_feedback(
    conn: sqlite3.Connection,
    template_id: int,
    query_text: str,
    was_useful: bool,
) -> None:
    row = conn.execute("SELECT example_queries FROM query_templates WHERE id = ?", (template_id,)).fetchone()
    if row is None:
        return
    examples = json.loads(row["example_queries"] or "[]")
    if query_text not in examples:
        examples = [query_text, *examples][:20]
    total = conn.execute(
        "SELECT count(*) FROM query_logs WHERE template_id = ? AND was_useful IS NOT NULL",
        (template_id,),
    ).fetchone()[0]
    useful = conn.execute(
        "SELECT count(*) FROM query_logs WHERE template_id = ? AND was_useful = 1",
        (template_id,),
    ).fetchone()[0]
    conn.execute(
        """
        UPDATE query_templates
        SET useful_count = ?, success_rate = ?, example_queries = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
        """,
        (useful, useful / total if total else 0.0, json.dumps(examples), template_id),
    )
