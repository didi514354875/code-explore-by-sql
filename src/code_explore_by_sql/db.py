from __future__ import annotations

import json
import math
import re
import sqlite3
import time
from collections import defaultdict
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

        CREATE TABLE IF NOT EXISTS bracket_index (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            file_id INTEGER NOT NULL REFERENCES source_files(id) ON DELETE CASCADE,
            open_line INTEGER NOT NULL,
            close_line INTEGER NOT NULL,
            depth INTEGER NOT NULL,
            block_type TEXT NOT NULL DEFAULT 'unknown',
            block_name TEXT,
            signature TEXT,
            is_complete INTEGER NOT NULL DEFAULT 1,
            extra_fields TEXT
        );

        CREATE INDEX IF NOT EXISTS idx_bracket_file_depth
            ON bracket_index(file_id, depth);
        CREATE INDEX IF NOT EXISTS idx_bracket_file_open
            ON bracket_index(file_id, open_line);

        CREATE TABLE IF NOT EXISTS include_edges (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source_file_id INTEGER NOT NULL REFERENCES source_files(id) ON DELETE CASCADE,
            include_path TEXT NOT NULL,
            target_file_id INTEGER REFERENCES source_files(id),
            line_number INTEGER NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_include_source ON include_edges(source_file_id);
        CREATE INDEX IF NOT EXISTS idx_include_target ON include_edges(target_file_id);
        CREATE INDEX IF NOT EXISTS idx_include_path ON include_edges(include_path);
        """
    )
    conn.commit()

    _migrate_legacy(conn)
    _migrate_add_adopted_file_id(conn)
    _migrate_add_parent_id(conn)
    _migrate_add_symbol_references(conn)
    _migrate_add_extra_blocks(conn)
    _migrate_add_member_types(conn)
    _migrate_add_symbol_ref_confidence(conn)
    _migrate_add_symbol_name_index(conn)
    _ensure_view(conn)

    conn.execute("CREATE INDEX IF NOT EXISTS idx_source_module ON source_files(module_name)")
    conn.commit()


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


def _migrate_add_parent_id(conn: sqlite3.Connection) -> None:
    """Add parent_id column to bracket_index if missing.

    Note: parent_id is a self-reference without FK constraint because SQLite
    self-referencing FKs make DELETE/UPDATE ordering difficult.
    """
    try:
        # Try with FK first (new databases)
        conn.execute("ALTER TABLE bracket_index ADD COLUMN parent_id INTEGER REFERENCES bracket_index(id)")
        conn.commit()
    except sqlite3.OperationalError:
        pass  # Column already exists

    try:
        conn.execute("CREATE INDEX IF NOT EXISTS idx_bracket_parent ON bracket_index(parent_id)")
        conn.commit()
    except sqlite3.OperationalError:
        pass

    # Fix invalid parent_id=0 values (no row has id=0 due to AUTOINCREMENT)
    try:
        conn.execute("UPDATE bracket_index SET parent_id = NULL WHERE parent_id = 0")
        conn.commit()
    except sqlite3.OperationalError:
        pass


def _migrate_add_symbol_references(conn: sqlite3.Connection) -> None:
    """Add symbol_references table if missing."""
    conn.execute("""
        CREATE TABLE IF NOT EXISTS symbol_references (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            symbol_name TEXT NOT NULL,
            symbol_type TEXT,
            symbol_file_id INTEGER REFERENCES source_files(id),
            ref_file_id INTEGER NOT NULL REFERENCES source_files(id) ON DELETE CASCADE,
            ref_block_id INTEGER REFERENCES bracket_index(id),
            ref_line INTEGER
        );
    """)
    conn.execute("CREATE INDEX IF NOT EXISTS idx_symref_symbol ON symbol_references(symbol_name)")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_symref_ref_file ON symbol_references(ref_file_id)")
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_symref_symbol_file "
        "ON symbol_references(symbol_name, symbol_file_id)"
    )
    conn.commit()


def _migrate_add_extra_blocks(conn: sqlite3.Connection) -> None:
    """Add extra_blocks table for non-brace constructs (UE macros, #define, etc.)."""
    try:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS extra_blocks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                file_id INTEGER NOT NULL REFERENCES source_files(id) ON DELETE CASCADE,
                name TEXT NOT NULL,
                block_type TEXT NOT NULL,
                start_line INTEGER NOT NULL,
                end_line INTEGER NOT NULL,
                params TEXT,
                signature TEXT
            )
        """)
        conn.execute("CREATE INDEX IF NOT EXISTS idx_extra_file ON extra_blocks(file_id)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_extra_name ON extra_blocks(name)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_extra_type ON extra_blocks(block_type)")
        conn.commit()
    except sqlite3.OperationalError:
        pass


def _migrate_add_member_types(conn: sqlite3.Connection) -> None:
    """Add member_types table for class-to-class type dependencies."""
    try:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS member_types (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                block_id INTEGER NOT NULL REFERENCES bracket_index(id) ON DELETE CASCADE,
                type_name TEXT NOT NULL,
                line_number INTEGER
            )
        """)
        conn.execute("CREATE INDEX IF NOT EXISTS idx_mtype_block ON member_types(block_id)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_mtype_name ON member_types(type_name)")
        conn.commit()
    except sqlite3.OperationalError:
        pass


def _migrate_add_symbol_ref_confidence(conn: sqlite3.Connection) -> None:
    """Add confidence, context, edge_type columns to symbol_references."""
    for col, ctype, default in [
        ("confidence", "REAL", "0.5"),
        ("context", "TEXT", None),
        ("edge_type", "TEXT", "'call'"),
    ]:
        try:
            if default:
                conn.execute(f"ALTER TABLE symbol_references ADD COLUMN {col} {ctype} NOT NULL DEFAULT {default}")
            else:
                conn.execute(f"ALTER TABLE symbol_references ADD COLUMN {col} {ctype}")
        except sqlite3.OperationalError:
            pass  # column already exists
    conn.commit()


def _migrate_add_symbol_name_index(conn: sqlite3.Connection) -> None:
    """Add symbol_name_index table for unified symbol lookup and fuzzy search."""
    try:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS symbol_name_index (
                name TEXT NOT NULL,
                source_type TEXT NOT NULL,
                source_id INTEGER NOT NULL,
                file_id INTEGER NOT NULL,
                block_type TEXT NOT NULL,
                module_name TEXT,
                qualified_name TEXT,
                member_types TEXT,
                PRIMARY KEY (name, source_type, source_id)
            ) WITHOUT ROWID
        """)
        conn.execute("CREATE INDEX IF NOT EXISTS idx_symname_type ON symbol_name_index(block_type)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_symname_module ON symbol_name_index(module_name)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_symname_qualified ON symbol_name_index(qualified_name)")
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


def _scan_file_content(
    file_id: int, content: str,
    unique_map: dict[str, int], collision_map: dict[str, list[tuple[int, str]]],
    provider_name: str = "unreal",
) -> tuple[int, list[tuple], list[tuple], list[Any], list[tuple]]:
    """Pure-CPU bracket scan + semantic sniff + include parse (no DB access).

    Designed to run in a subprocess.
    Returns (file_id, bracket_rows, include_rows, blocks, extra_block_rows).
    blocks: list of BracketBlock objects for parent_id computation by caller.
    extra_block_rows: non-brace blocks (UE macros, #define macros, etc.)
    """
    import json

    from code_explore_by_sql.bracket_scanner import scan_brackets
    from code_explore_by_sql.providers import get_provider
    from code_explore_by_sql.symbol_sniffer import extract_extra_blocks, sniff_semantic_blocks

    bracket_rows: list[tuple] = []
    include_rows: list[tuple] = []
    extra_block_rows: list[tuple] = []

    lines = content.split("\n")
    provider = get_provider(provider_name)

    # Always parse includes (even if no braces)
    for inc in provider.parse_include_directives(lines):
        target_id = _match_include_path(inc.path, unique_map, collision_map)
        include_rows.append((file_id, inc.path, target_id, inc.line_number))

    # Extract non-brace blocks (UE macros, #define macros, etc.)
    extra_blocks = extract_extra_blocks(lines, provider=provider)
    for eb in extra_blocks:
        extra_block_rows.append((
            file_id, eb.name, eb.block_type, eb.start_line, eb.end_line,
            eb.params, eb.signature,
        ))

    if "{" not in content:
        return (file_id, bracket_rows, include_rows, [], extra_block_rows)

    blocks = scan_brackets(content, lines=lines)

    # Semantic-recursive classification — only classified blocks stored
    sniffed = sniff_semantic_blocks(lines, blocks, provider=provider)

    # Build set of classified block indices for O(1) lookup
    classified_indices = {idx for idx, _info in sniffed}
    sniff_map = {idx: info for idx, info in sniffed}

    # Only store classified blocks (no more "unknown")
    for i, b in enumerate(blocks):
        if i not in classified_indices:
            continue
        info = sniff_map[i]
        extra_json = json.dumps(info.extra_fields) if info.extra_fields else None
        bracket_rows.append((
            file_id, b.open_line, b.close_line, b.depth,
            info.block_type,
            info.block_name,
            (info.signature[:500] if info.signature else None),
            int(b.is_complete),
            extra_json,
        ))

    return (file_id, bracket_rows, include_rows, blocks, extra_block_rows)


_WORKER_UNIQUE_MAP: dict | None = None
_WORKER_COLLISION_MAP: dict | None = None
_WORKER_PROVIDER_NAME: str | None = None


def _scan_file_worker_init(unique_map, collision_map, provider_name):
    """Initialize worker process with shared read-only data."""
    global _WORKER_UNIQUE_MAP, _WORKER_COLLISION_MAP, _WORKER_PROVIDER_NAME
    _WORKER_UNIQUE_MAP = unique_map
    _WORKER_COLLISION_MAP = collision_map
    _WORKER_PROVIDER_NAME = provider_name


def _scan_file_worker(args: tuple) -> tuple:
    """Multiprocessing worker wrapper — uses globally initialized data."""
    file_id, content = args
    return _scan_file_content(file_id, content, _WORKER_UNIQUE_MAP, _WORKER_COLLISION_MAP, _WORKER_PROVIDER_NAME)


def backfill_structural_index(
    conn: sqlite3.Connection, batch_size: int = 500, workers: int = 0,
    provider_name: str = "unreal",
) -> int:
    """Rebuild ALL structural index data for all existing files.

    Includes: bracket_index, include_edges, parent_id, symbol_references.
    This is the complete Phase 2 — a single call produces a fully usable index.

    Uses multiprocessing for CPU-bound scanning when >= 4 cores available.
    On <= 2 core machines, falls back to single-process to avoid memory/IO pressure.
    workers: number of parallel processes. 0 = auto-detect (uses multi only if >= 4 cores).
    provider_name: name of the provider to use for include parsing and line filtering.
    """
    import os

    from code_explore_by_sql.providers import get_provider

    provider = get_provider(provider_name)
    unique_map, collision_map = _build_path_lookup(conn)
    total_files = conn.execute("SELECT COUNT(*) as c FROM source_files").fetchone()["c"]

    cpu_count = os.cpu_count() or 2
    if workers == 0:
        workers = 1 if cpu_count <= 2 else min(cpu_count - 1, 8)

    print(f"  backfill starting: {total_files:,} files, workers={workers}, provider={provider_name}", flush=True)
    t_start = time.time()

    # Clear existing structural data via DROP+RECREATE (faster than DELETE for large tables)
    # Create tables WITHOUT indexes — indexes are built after bulk data is inserted
    conn.execute("PRAGMA foreign_keys=OFF")
    conn.execute("DROP TABLE IF EXISTS bracket_index")
    conn.execute("DROP TABLE IF EXISTS include_edges")
    conn.execute("DROP TABLE IF EXISTS symbol_references")
    conn.execute("DROP TABLE IF EXISTS extra_blocks")
    conn.execute("DROP TABLE IF EXISTS member_types")
    conn.executescript("""
        CREATE TABLE bracket_index (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            file_id INTEGER NOT NULL REFERENCES source_files(id) ON DELETE CASCADE,
            open_line INTEGER NOT NULL,
            close_line INTEGER NOT NULL,
            depth INTEGER NOT NULL,
            block_type TEXT NOT NULL DEFAULT 'unknown',
            block_name TEXT,
            signature TEXT,
            is_complete INTEGER NOT NULL DEFAULT 1,
            parent_id INTEGER REFERENCES bracket_index(id),
            extra_fields TEXT
        );
        CREATE TABLE include_edges (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source_file_id INTEGER NOT NULL REFERENCES source_files(id) ON DELETE CASCADE,
            include_path TEXT NOT NULL,
            target_file_id INTEGER REFERENCES source_files(id),
            line_number INTEGER NOT NULL
        );
        CREATE TABLE symbol_references (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            symbol_name TEXT NOT NULL,
            symbol_type TEXT,
            symbol_file_id INTEGER REFERENCES source_files(id),
            ref_file_id INTEGER NOT NULL REFERENCES source_files(id) ON DELETE CASCADE,
            ref_block_id INTEGER REFERENCES bracket_index(id),
            ref_line INTEGER,
            confidence REAL NOT NULL DEFAULT 0.5,
            context TEXT,
            edge_type TEXT NOT NULL DEFAULT 'call'
        );
        CREATE TABLE extra_blocks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            file_id INTEGER NOT NULL REFERENCES source_files(id) ON DELETE CASCADE,
            name TEXT NOT NULL,
            block_type TEXT NOT NULL,
            start_line INTEGER NOT NULL,
            end_line INTEGER NOT NULL,
            params TEXT,
            signature TEXT
        );
        CREATE TABLE member_types (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            block_id INTEGER NOT NULL REFERENCES bracket_index(id) ON DELETE CASCADE,
            type_name TEXT NOT NULL,
            line_number INTEGER
        );
    """)
    conn.execute("PRAGMA foreign_keys=ON")
    conn.commit()

    total = 0
    _BRACKET_SQL = (
        "INSERT INTO bracket_index "
        "(file_id, open_line, close_line, depth, block_type, "
        "block_name, signature, is_complete, extra_fields) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
    )
    _INCLUDE_SQL = (
        "INSERT INTO include_edges "
        "(source_file_id, include_path, target_file_id, line_number) "
        "VALUES (?, ?, ?, ?)"
    )
    _EXTRA_SQL = (
        "INSERT INTO extra_blocks "
        "(file_id, name, block_type, start_line, end_line, params, signature) "
        "VALUES (?, ?, ?, ?, ?, ?, ?)"
    )

    # Collect (file_id, blocks) for parent_id + symbol_references post-processing
    file_blocks: dict[int, list] = {}

    t_phase1 = time.time()

    if workers <= 1:
        # Single-process: load files in batches to limit memory
        last_id = 0
        while True:
            rows = conn.execute(
                "SELECT id, raw_content FROM source_files WHERE id > ? ORDER BY id LIMIT ?",
                (last_id, batch_size),
            ).fetchall()
            if not rows:
                break
            for row in rows:
                file_id, bracket_rows, include_rows, blocks, extra_block_rows = _scan_file_content(
                    row["id"], row["raw_content"], unique_map, collision_map, provider_name,
                )
                if bracket_rows:
                    conn.executemany(_BRACKET_SQL, bracket_rows)
                if include_rows:
                    conn.executemany(_INCLUDE_SQL, include_rows)
                if extra_block_rows:
                    conn.executemany(_EXTRA_SQL, extra_block_rows)
                if blocks:
                    file_blocks[file_id] = blocks
                total += 1
            conn.commit()
            last_id = rows[-1]["id"]
            elapsed = time.time() - t_phase1
            rate = total / elapsed if elapsed > 0 else 0
            eta = (total_files - total) / rate if rate > 0 else 0
            print(f"  bracket scan: {total}/{total_files} ({total/total_files*100:.0f}%) "
                  f"{rate:.0f} files/s ETA {eta:.0f}s", flush=True)
    else:
        # Multi-process: load files in batches, scan in parallel, write in main process
        from multiprocessing import Pool

        with Pool(
            processes=workers,
            initializer=_scan_file_worker_init,
            initargs=(unique_map, collision_map, provider_name),
        ) as pool:
            last_id = 0
            while True:
                rows = conn.execute(
                    "SELECT id, raw_content FROM source_files WHERE id > ? ORDER BY id LIMIT ?",
                    (last_id, batch_size),
                ).fetchall()
                if not rows:
                    break

                task_args = [
                    (row["id"], row["raw_content"])
                    for row in rows
                ]
                results = pool.map(_scan_file_worker, task_args)

                for file_id, bracket_rows, include_rows, blocks, extra_block_rows in results:
                    if bracket_rows:
                        conn.executemany(_BRACKET_SQL, bracket_rows)
                    if include_rows:
                        conn.executemany(_INCLUDE_SQL, include_rows)
                    if extra_block_rows:
                        conn.executemany(_EXTRA_SQL, extra_block_rows)
                    if blocks:
                        file_blocks[file_id] = blocks
                    total += 1

                conn.commit()
                last_id = rows[-1]["id"]
                elapsed = time.time() - t_phase1
                rate = total / elapsed if elapsed > 0 else 0
                eta = (total_files - total) / rate if rate > 0 else 0
                print(f"  bracket scan: {total}/{total_files} ({total/total_files*100:.0f}%) "
                      f"{rate:.0f} files/s ETA {eta:.0f}s", flush=True)

    # --- Phase 2b: Compute parent_id for all files ---
    elapsed_phase1 = time.time() - t_phase1
    block_count = conn.execute("SELECT COUNT(*) as c FROM bracket_index").fetchone()["c"]
    print(f"  bracket scan done: {total_files:,} files, {block_count:,} blocks in {elapsed_phase1:.1f}s", flush=True)

    # Build bracket_index indexes needed by subsequent phases
    t_idx = time.time()
    conn.executescript("""
        CREATE INDEX idx_bracket_file_depth ON bracket_index(file_id, depth);
        CREATE INDEX idx_bracket_file_open ON bracket_index(file_id, open_line);
    """)
    conn.commit()
    print(f"  bracket indexes built in {time.time() - t_idx:.1f}s", flush=True)

    reference_file_ids = sorted(file_blocks.keys())
    print(f"  parent_id: computing for {len(file_blocks):,} files...", flush=True)
    t_phase2b = time.time()
    _backfill_parent_ids(conn, file_blocks)
    del file_blocks
    elapsed_phase2b = time.time() - t_phase2b
    conn.execute("CREATE INDEX idx_bracket_parent ON bracket_index(parent_id)")
    conn.commit()
    parent_count = conn.execute("SELECT COUNT(*) as c FROM bracket_index WHERE parent_id IS NOT NULL").fetchone()["c"]
    print(f"  parent_id done: {parent_count:,} links in {elapsed_phase2b:.1f}s", flush=True)

    # Build include_edges indexes (small table, fast)
    conn.executescript("""
        CREATE INDEX idx_include_source ON include_edges(source_file_id);
        CREATE INDEX idx_include_target ON include_edges(target_file_id);
        CREATE INDEX idx_include_path ON include_edges(include_path);
        CREATE INDEX idx_extra_file ON extra_blocks(file_id);
        CREATE INDEX idx_extra_name ON extra_blocks(name);
        CREATE INDEX idx_extra_type ON extra_blocks(block_type);
    """)
    conn.commit()
    extra_count = conn.execute("SELECT COUNT(*) as c FROM extra_blocks").fetchone()["c"]
    print(f"  extra_blocks: {extra_count:,} non-brace blocks", flush=True)

    # --- Phase 2c: Generate symbol_references ---
    print("  symbol_references: collecting trackable symbols...", flush=True)
    t_phase2c = time.time()
    _backfill_symbol_references(conn, provider, workers=workers, file_ids=reference_file_ids)
    elapsed_phase2c = time.time() - t_phase2c
    ref_count = conn.execute("SELECT COUNT(*) as c FROM symbol_references").fetchone()["c"]
    print(f"  symbol_references done: {ref_count:,} refs in {elapsed_phase2c:.1f}s", flush=True)

    elapsed_total = time.time() - t_start
    print(f"  backfill complete: {elapsed_total:.1f}s total "
          f"(scan {elapsed_phase1:.0f}s + parent {elapsed_phase2b:.0f}s + refs {elapsed_phase2c:.0f}s)", flush=True)

    # Build symbol_references indexes after bulk insert (much faster than incremental maintenance)
    t_idx = time.time()
    conn.executescript("""
        CREATE INDEX idx_symref_symbol ON symbol_references(symbol_name);
        CREATE INDEX idx_symref_ref_file ON symbol_references(ref_file_id);
        CREATE INDEX idx_symref_symbol_file ON symbol_references(symbol_name, symbol_file_id);
    """)
    conn.commit()
    print(f"  symbol_references indexes built in {time.time() - t_idx:.1f}s", flush=True)

    # --- Phase 2d: Build symbol_name_index (unified symbol table) ---
    print("  symbol_name_index: building unified symbol table...", flush=True)
    t_phase2d = time.time()
    _build_symbol_name_index(conn)
    elapsed_phase2d = time.time() - t_phase2d
    sym_count = conn.execute("SELECT COUNT(*) as c FROM symbol_name_index").fetchone()["c"]
    print(f"  symbol_name_index done: {sym_count:,} symbols in {elapsed_phase2d:.1f}s", flush=True)

    return total


def _backfill_parent_ids(
    conn: sqlite3.Connection, file_blocks: dict[int, list],
) -> None:
    """Compute and backfill parent_id for all bracket blocks.

    file_blocks: file_id -> list of BracketBlock objects (with depth, open_line, close_line).

    Processes in batches by file_id to limit peak memory usage.
    """
    from code_explore_by_sql.bracket_scanner import compute_parent_ids

    file_ids = sorted(file_blocks.keys())
    batch_size = 1000
    total_batches = (len(file_ids) + batch_size - 1) // batch_size
    total_updates = 0

    print(f"    parent_id: {len(file_ids):,} files in {total_batches} batches", flush=True)

    for i in range(0, len(file_ids), batch_size):
        batch_file_ids = file_ids[i:i + batch_size]
        placeholders = ",".join("?" * len(batch_file_ids))
        batch_updates: list[tuple] = []

        # Load only this batch of files' bracket rows
        batch_rows = conn.execute(
            f"SELECT id, file_id, open_line, depth FROM bracket_index "
            f"WHERE file_id IN ({placeholders}) ORDER BY file_id, open_line",
            batch_file_ids,
        ).fetchall()

        db_by_file: dict[int, list] = defaultdict(list)
        for r in batch_rows:
            db_by_file[r["file_id"]].append(r)

        for file_id in batch_file_ids:
            blocks = file_blocks.get(file_id)
            if not blocks:
                continue
            parent_map = compute_parent_ids(blocks)
            if not parent_map:
                continue

            db_rows = db_by_file.get(file_id)
            if not db_rows:
                continue

            id_lookup: dict[tuple[int, int], int] = {
                (r["open_line"], r["depth"]): r["id"] for r in db_rows
            }

            for b in blocks:
                key = (b.open_line, b.depth)
                child_id = id_lookup.get(key)
                if child_id is None:
                    continue
                parent_key = parent_map.get(key)
                if parent_key is not None:
                    parent_id = id_lookup.get(parent_key)
                    batch_updates.append((parent_id, child_id))

        if batch_updates:
            conn.executemany(
                "UPDATE bracket_index SET parent_id = ? WHERE id = ?",
                batch_updates,
            )
            conn.commit()
            total_updates += len(batch_updates)

        processed = min(i + batch_size, len(file_ids))
        print(f"    parent_id batch: {processed}/{len(file_ids)} ({processed/len(file_ids)*100:.0f}%) "
              f"{total_updates:,} links so far", flush=True)

    if total_updates:
        print(f"    parent_id: {total_updates:,} updates committed", flush=True)


def _backfill_symbol_references(
    conn: sqlite3.Connection,
    provider: Any,
    workers: int = 1,
    file_ids: list[int] | None = None,
) -> None:
    """Generate symbol_references from all indexed files.

    provider: provider instance for skip_line_re.
    workers: number of parallel processes for CPU-bound reference scanning.
    file_ids: optional list of file IDs to scan. If omitted, derived from bracket_index.
    """
    from code_explore_by_sql.sniffers.reference_tracker import (
        ReferenceTrackerConfig,
        enrich_ref_block_ids,
        prepare_bracket_arrays,
        track_references_for_file,
    )

    config = ReferenceTrackerConfig()
    skip_line_re_fn = getattr(provider, "skip_line_re", None)
    skip_line_re = skip_line_re_fn() if skip_line_re_fn else None
    skip_names_fn = getattr(provider, "skip_symbol_names", None)
    skip_names = skip_names_fn() if skip_names_fn else frozenset()

    # Step 1: Collect all named symbols (any depth) and pre-filter once
    rows = conn.execute(
        "SELECT id, file_id, block_name, block_type, open_line, close_line "
        "FROM bracket_index WHERE block_name IS NOT NULL "
        "AND block_type NOT IN ('unknown', 'control_flow')"
    ).fetchall()

    symbol_def_counts: dict[str, int] = defaultdict(int)
    for r in rows:
        name = r["block_name"]
        if name and len(name) >= config.min_name_length and name not in config.skip_keywords:
            symbol_def_counts[name] += 1

    # Pre-filter AND pre-build target_symbols dict (name -> lightweight tuples) ONCE
    target_symbols: dict[str, list[tuple[str, int, int]]] = {}
    for r in rows:
        name = r["block_name"]
        if not name or len(name) < config.min_name_length:
            continue
        if name in config.skip_keywords:
            continue
        if symbol_def_counts[name] > config.max_definition_count:
            continue
        target_symbols.setdefault(name, []).append((
            r["block_type"],
            r["file_id"],
            r["open_line"],
        ))

    if not target_symbols:
        print("    references: no trackable symbols found, skipping", flush=True)
        return

    # Pre-build check_set once
    check_set: set[str] = set(target_symbols)
    total_sym_defs = sum(len(v) for v in target_symbols.values())
    print(f"    references: {len(rows):,} raw symbols -> {len(target_symbols):,} unique names "
          f"({total_sym_defs:,} defs after filter)", flush=True)

    # Step 2: For each file, scan for references to filtered symbols
    _REF_SQL = (
        "INSERT INTO symbol_references "
        "(symbol_name, symbol_type, symbol_file_id, "
        "ref_file_id, ref_block_id, ref_line) "
        "VALUES (?, ?, ?, ?, ?, ?)"
    )
    total_refs = 0

    if file_ids is None:
        file_ids = [
            r["file_id"] for r in conn.execute(
                "SELECT DISTINCT file_id FROM bracket_index ORDER BY file_id"
            ).fetchall()
        ]
    else:
        file_ids = sorted(file_ids)
    offset = 0
    batch_size = 1000
    t_refs = time.time()

    if workers <= 1:
        # Single-process path
        while offset < len(file_ids):
            batch_ids = file_ids[offset:offset + batch_size]
            id_list = ",".join(str(fid) for fid in batch_ids)

            # Batch load file contents + bracket data (with block_type for filtering)
            content_rows = conn.execute(
                f"SELECT id, raw_content FROM source_files WHERE id IN ({id_list})"
            ).fetchall()
            bracket_rows = conn.execute(
                f"SELECT id, file_id, open_line, close_line, depth, block_type "
                f"FROM bracket_index WHERE file_id IN ({id_list}) ORDER BY open_line"
            ).fetchall()
            brackets_by_file: dict[int, list[dict]] = defaultdict(list)
            for br in bracket_rows:
                brackets_by_file[br["file_id"]].append(dict(br))
            for row in content_rows:
                fid = row["id"]
                lines = row["raw_content"].split("\n")
                bd = brackets_by_file.get(fid, [])

                refs = track_references_for_file(
                    lines, fid, target_symbols,
                    skip_line_re=skip_line_re, check_set=check_set,
                    skip_names=skip_names, bracket_data=bd,
                )
                if refs:
                    bracket_arrays = prepare_bracket_arrays(bd)
                    enriched = enrich_ref_block_ids(
                        refs, bracket_arrays)
                    conn.executemany(_REF_SQL, enriched)
                    total_refs += len(enriched)

            conn.commit()
            offset += len(batch_ids)
            elapsed = time.time() - t_refs
            rate = offset / elapsed if elapsed > 0 else 0
            eta = (len(file_ids) - offset) / rate if rate > 0 else 0
            print(f"    references: {offset}/{len(file_ids)} ({offset/len(file_ids)*100:.0f}%) "
                  f"{total_refs:,} refs, {rate:.0f} files/s ETA {eta:.0f}s", flush=True)
    else:
        # Multi-process path: CPU work in workers, DB writes in main process
        from multiprocessing import Pool

        with Pool(
            processes=workers,
            initializer=_ref_worker_init,
            initargs=(target_symbols, skip_line_re, check_set, skip_names),
        ) as pool:
            commit_interval = 2000
            done = 0
            since_commit = 0
            for i in range(0, len(file_ids), batch_size):
                batch_ids = file_ids[i:i + batch_size]
                id_list = ",".join(str(fid) for fid in batch_ids)

                content_rows = conn.execute(
                    f"SELECT id, raw_content FROM source_files WHERE id IN ({id_list})"
                ).fetchall()
                bracket_rows = conn.execute(
                    f"SELECT id, file_id, open_line, close_line, depth, block_type "
                    f"FROM bracket_index WHERE file_id IN ({id_list}) ORDER BY open_line"
                ).fetchall()
                brackets_by_file_mp: dict[int, list[dict]] = defaultdict(list)
                for br in bracket_rows:
                    brackets_by_file_mp[br["file_id"]].append(dict(br))
                arrays_by_file_mp: dict[int, tuple] = {
                    fid: prepare_bracket_arrays(bd)
                    for fid, bd in brackets_by_file_mp.items()
                }
                batch_tasks = [
                    (
                        row["raw_content"].split("\n"),
                        row["id"],
                        arrays_by_file_mp.get(row["id"], ([], [], [], [])),
                        brackets_by_file_mp.get(row["id"], []),
                    )
                    for row in content_rows
                ]

                for ref_rows in pool.imap_unordered(_ref_scan_worker, batch_tasks, chunksize=64):
                    if ref_rows:
                        conn.executemany(_REF_SQL, ref_rows)
                        total_refs += len(ref_rows)
                    done += 1
                    since_commit += 1
                    if since_commit >= commit_interval:
                        conn.commit()
                        since_commit = 0
                        elapsed = time.time() - t_refs
                        rate = done / elapsed if elapsed > 0 else 0
                        eta = ((len(file_ids) - done) / rate) if rate > 0 else 0
                        print(f"    references: {done}/{len(file_ids)} ({done/len(file_ids)*100:.0f}%) "
                              f"{total_refs:,} refs, {rate:.0f} files/s ETA {eta:.0f}s", flush=True)
                conn.commit()
                elapsed = time.time() - t_refs
                rate = done / elapsed if elapsed > 0 else 0
                eta = ((len(file_ids) - done) / rate) if rate > 0 else 0
                print(f"    references: {done}/{len(file_ids)} ({done/len(file_ids)*100:.0f}%) "
                      f"{total_refs:,} refs, {rate:.0f} files/s ETA {eta:.0f}s", flush=True)
            conn.commit()
            elapsed = time.time() - t_refs
            rate = done / elapsed if elapsed > 0 else 0
            print(f"    references: {done}/{len(file_ids)} ({done/len(file_ids)*100:.0f}%) "
                  f"{total_refs:,} refs, {rate:.0f} files/s ETA 0s", flush=True)


# Global state for worker processes (set by _ref_worker_init)
_WORKER_TARGET_SYMBOLS: dict | None = None
_WORKER_SKIP_LINE_RE: re.Pattern | None = None
_WORKER_CHECK_SET: set | None = None
_WORKER_SKIP_NAMES: frozenset | None = None


def _build_symbol_name_index(conn: sqlite3.Connection) -> None:
    """Build symbol_name_index from bracket_index and extra_blocks.

    This creates a unified symbol table where Block = Symbol.
    Populates qualified_name for methods (ClassName::MethodName).
    Extracts member_types from extra_fields JSON for class/struct blocks.
    """
    # Clear existing data
    conn.execute("DELETE FROM symbol_name_index")
    print("    symbol_name_index: clearing existing data", flush=True)

    # Insert from bracket_index (brace-delimited blocks)
    # Build qualified names for methods by joining with parent class
    t_bracket = time.time()
    before = conn.total_changes
    conn.execute("""
        INSERT INTO symbol_name_index
            (name, source_type, source_id, file_id, block_type, module_name, qualified_name, member_types)
        SELECT
            b.block_name,
            'bracket',
            b.id,
            b.file_id,
            b.block_type,
            s.module_name,
            CASE
                WHEN b.block_type = 'method' AND p.block_type IN ('class', 'struct') AND p.block_name IS NOT NULL
                THEN p.block_name || '::' || b.block_name
                ELSE b.block_name
            END,
            b.extra_fields
        FROM bracket_index b
        JOIN source_files s ON s.id = b.file_id
        LEFT JOIN bracket_index p ON p.id = b.parent_id
        WHERE b.block_name IS NOT NULL
          AND b.block_type NOT IN ('unknown', 'control_flow')
    """)
    bracket_count = conn.total_changes - before
    print(f"    symbol_name_index: {bracket_count:,} from bracket_index in {time.time() - t_bracket:.1f}s", flush=True)

    # Insert from extra_blocks (non-brace blocks: UE macros, #define, etc.)
    t_extra = time.time()
    before = conn.total_changes
    conn.execute("""
        INSERT INTO symbol_name_index
            (name, source_type, source_id, file_id, block_type, module_name, qualified_name, member_types)
        SELECT
            e.name,
            'extra',
            e.id,
            e.file_id,
            e.block_type,
            s.module_name,
            e.name,
            NULL
        FROM extra_blocks e
        JOIN source_files s ON s.id = e.file_id
    """)
    extra_count = conn.total_changes - before
    print(f"    symbol_name_index: {extra_count:,} from extra_blocks in {time.time() - t_extra:.1f}s", flush=True)

    conn.commit()


def _fuzzy_resolve_symbol(
    conn: sqlite3.Connection,
    query: str,
    limit: int = 5,
) -> dict:
    """Resolve a potentially fuzzy query to ranked symbol candidates.

    Returns dict with:
    - 'exact': list of exact matches
    - 'expanded': expanded query string (if UE prefix normalization applied)
    - 'suggestions': list of close matches (if no exact/expanded found)
    """
    import difflib

    # 1. Exact match in symbol_name_index
    exact = conn.execute(
        "SELECT name, block_type, module_name, qualified_name, COUNT(*) as def_count "
        "FROM symbol_name_index WHERE name = ? "
        "GROUP BY name ORDER BY def_count DESC LIMIT ?",
        (query, limit),
    ).fetchall()
    if exact:
        return {'exact': [dict(r) for r in exact], 'expanded': None, 'suggestions': []}

    # 2. UE prefix normalization: Actor -> AActor, UActor, FActor, EActor, IActor
    UE_PREFIXES = ('A', 'U', 'F', 'E', 'I', 'T')
    for prefix in UE_PREFIXES:
        candidate = prefix + query
        found = conn.execute(
            "SELECT name, block_type, module_name, qualified_name, COUNT(*) as def_count "
            "FROM symbol_name_index WHERE name = ? "
            "GROUP BY name ORDER BY def_count DESC LIMIT ?",
            (candidate, limit),
        ).fetchall()
        if found:
            return {
                'exact': [dict(r) for r in found],
                'expanded': candidate,
                'suggestions': [],
            }

    # 3. Partial match via LIKE (case-insensitive substring)
    partial = conn.execute(
        "SELECT name, block_type, module_name, qualified_name, COUNT(*) as def_count "
        "FROM symbol_name_index WHERE name LIKE ? "
        "GROUP BY name ORDER BY def_count DESC LIMIT ?",
        (f"%{query}%", limit),
    ).fetchall()
    if partial:
        return {
            'exact': [dict(r) for r in partial],
            'expanded': None,
            'suggestions': [],
        }

    # 4. difflib.get_close_matches against top symbol names
    all_names = [
        r["name"] for r in conn.execute(
            "SELECT DISTINCT name FROM symbol_name_index ORDER BY name LIMIT 5000"
        ).fetchall()
    ]
    close = difflib.get_close_matches(query, all_names, n=limit, cutoff=0.6)
    if close:
        return {'exact': [], 'expanded': None, 'suggestions': close}

    return {'exact': [], 'expanded': None, 'suggestions': []}


def _ref_worker_init(
    target_symbols: dict[str, list[tuple[str, int, int]]],
    skip_line_re: re.Pattern | None,
    check_set: set[str],
    skip_names: frozenset[str] | None = None,
) -> None:
    """Initialize worker process with shared read-only data (once per worker)."""
    global _WORKER_TARGET_SYMBOLS, _WORKER_SKIP_LINE_RE, _WORKER_CHECK_SET, _WORKER_SKIP_NAMES
    _WORKER_TARGET_SYMBOLS = target_symbols
    _WORKER_SKIP_LINE_RE = skip_line_re
    _WORKER_CHECK_SET = check_set
    _WORKER_SKIP_NAMES = skip_names or frozenset()


def _ref_scan_worker(args: tuple) -> list[tuple]:
    """Worker function for parallel reference scanning."""
    from code_explore_by_sql.sniffers.reference_tracker import (
        enrich_ref_block_ids,
        track_references_for_file,
    )

    lines, fid, bracket_arrays, bracket_data = args

    refs = track_references_for_file(
        lines, fid, _WORKER_TARGET_SYMBOLS,
        skip_line_re=_WORKER_SKIP_LINE_RE,
        check_set=_WORKER_CHECK_SET,
        skip_names=_WORKER_SKIP_NAMES,
        bracket_data=bracket_data,
    )
    if not refs:
        return []
    return enrich_ref_block_ids(refs, bracket_arrays)


def upsert_source_file(
    conn: sqlite3.Connection, source: SourceFile, *, skip_structural: bool = False
) -> int:
    # Check if content changed for incremental structural index update
    old = conn.execute(
        "SELECT id, content_hash FROM source_files WHERE file_path = ?",
        (source.file_path,),
    ).fetchone()
    old_hash = old["content_hash"] if old else None
    needs_structural_reindex = old is not None and old_hash != source.content_hash

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
    file_id = int(row["id"])

    if not skip_structural and (needs_structural_reindex or old is None):
        rebuild_structural_index(conn, file_id, source.raw_content)

    return file_id


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
            id,
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


# ---------------------------------------------------------------------------
# Structural index: bracket skeleton + include edges
# ---------------------------------------------------------------------------


def _build_path_lookup(conn: sqlite3.Connection) -> tuple[dict[str, int], dict[str, list[tuple[int, str]]]]:
    """Pre-build lookups from file basename → file_id for O(1) include matching.

    Returns (unique_map, collision_map):
      unique_map: basename → file_id (for basenames appearing in exactly one file)
      collision_map: basename → [(file_id, file_path), ...] (for ambiguous basenames)
    """
    temp: dict[str, list[tuple[int, str]]] = {}
    for row in conn.execute("SELECT id, file_path FROM source_files"):
        fid = row["id"]
        fpath = row["file_path"]
        basename = fpath.split("/")[-1]
        temp.setdefault(basename, []).append((fid, fpath))

    unique_map: dict[str, int] = {}
    collision_map: dict[str, list[tuple[int, str]]] = {}
    for basename, entries in temp.items():
        if len(entries) == 1:
            unique_map[basename] = entries[0][0]
        else:
            collision_map[basename] = entries
    return unique_map, collision_map


def _match_include_path(
    inc_path: str,
    unique_map: dict[str, int],
    collision_map: dict[str, list[tuple[int, str]]],
) -> int | None:
    """Match an include path to an indexed file.

    O(1) for unique basenames, O(k) where k ≈ 1-5 for ambiguous basenames.
    """
    basename = inc_path.split("/")[-1]

    if basename in unique_map:
        return unique_map[basename]

    if basename not in collision_map:
        return None

    for fid, fpath in collision_map[basename]:
        if fpath.endswith(inc_path) or fpath.endswith("/" + inc_path):
            return fid

    return None


def rebuild_structural_index(
    conn: sqlite3.Connection,
    file_id: int,
    content: str,
    *,
    skip_delete: bool = False,
    unique_map: dict[str, int] | None = None,
    collision_map: dict[str, list[tuple[int, str]]] | None = None,
    auto_commit: bool = True,
    provider_name: str = "unreal",
) -> None:
    """Build bracket_index and include_edges for a single file.

    skip_delete: skip DELETE for new files (backfill optimization).
    unique_map/collision_map: pre-built include lookups (avoids per-include LIKE queries).
    auto_commit: if False, caller is responsible for committing (batch optimization).
    provider_name: name of the provider to use for include parsing and line filtering.
    """
    import json

    from code_explore_by_sql.bracket_scanner import compute_parent_ids, scan_brackets
    from code_explore_by_sql.providers import get_provider
    from code_explore_by_sql.symbol_sniffer import extract_extra_blocks, sniff_semantic_blocks

    provider = get_provider(provider_name)

    if not skip_delete:
        # Temporarily disable FK checks for self-referencing parent_id
        conn.execute("PRAGMA foreign_keys=OFF")
        conn.execute("DELETE FROM bracket_index WHERE file_id = ?", (file_id,))
        conn.execute("DELETE FROM include_edges WHERE source_file_id = ?", (file_id,))
        conn.execute("DELETE FROM extra_blocks WHERE file_id = ?", (file_id,))
        conn.execute("PRAGMA foreign_keys=ON")

    # Fast path: files with no braces — only parse includes and extra blocks
    has_braces = "{" in content

    lines = content.split("\n")

    # Always extract non-brace blocks and includes
    extra_blocks = extract_extra_blocks(lines, provider=provider)
    for eb in extra_blocks:
        conn.execute(
            "INSERT INTO extra_blocks (file_id, name, block_type, start_line, end_line, params, signature) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            (file_id, eb.name, eb.block_type, eb.start_line, eb.end_line, eb.params, eb.signature),
        )
    _build_include_edges(conn, file_id, lines, unique_map, collision_map, provider)

    if not has_braces:
        if auto_commit:
            conn.commit()
        return

    blocks = scan_brackets(content, lines=lines)

    # Compute parent_id for each block
    parent_map = compute_parent_ids(blocks) if blocks else {}

    # Semantic-recursive classification
    sniffed = sniff_semantic_blocks(lines, blocks, provider=provider)
    classified_indices = {idx for idx, _info in sniffed}
    sniff_map = {idx: info for idx, info in sniffed}

    # Insert classified blocks only
    rows = []
    for i, b in enumerate(blocks):
        if i not in classified_indices:
            continue
        info = sniff_map[i]
        extra_json = json.dumps(info.extra_fields) if info.extra_fields else None
        rows.append((
            file_id, b.open_line, b.close_line, b.depth,
            info.block_type, info.block_name,
            (info.signature[:500] if info.signature else None),
            int(b.is_complete), extra_json,
        ))

    if rows:
        conn.executemany(
            """
            INSERT INTO bracket_index
                (file_id, open_line, close_line, depth, block_type, block_name, signature, is_complete, extra_fields)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            rows,
        )

    # Backfill parent_id
    inserted = conn.execute(
        "SELECT id, open_line, depth FROM bracket_index WHERE file_id = ? ORDER BY open_line",
        (file_id,),
    ).fetchall()
    id_lookup: dict[tuple[int, int], int] = {}
    for r in inserted:
        id_lookup[(r["open_line"], r["depth"])] = r["id"]

    updates: list[tuple] = []
    for b in blocks:
        key = (b.open_line, b.depth)
        child_id = id_lookup.get(key)
        if child_id is None:
            continue
        parent_key = parent_map.get(key)
        if parent_key is not None:
            parent_id = id_lookup.get(parent_key)
            updates.append((parent_id, child_id))
    if updates:
        conn.executemany(
            "UPDATE bracket_index SET parent_id = ? WHERE id = ?",
            updates,
        )

    # Rebuild symbol_references for this file
    _rebuild_file_symbol_references(conn, file_id, lines, provider)

    if auto_commit:
        conn.commit()


def _rebuild_file_symbol_references(
    conn: sqlite3.Connection,
    file_id: int,
    lines: list[str],
    provider: Any,
) -> None:
    """Rebuild symbol_references for a single file (incremental update path)."""
    from code_explore_by_sql.sniffers.reference_tracker import (
        ReferenceTrackerConfig,
        enrich_ref_block_ids,
        prepare_bracket_arrays,
        track_references_for_file,
    )

    config = ReferenceTrackerConfig()

    # Delete old references for this file before any early return. This prevents
    # stale rows when a file is changed to remove all references or all symbols.
    conn.execute("DELETE FROM symbol_references WHERE ref_file_id = ?", (file_id,))

    # Collect the same symbol universe as full backfill: all named, classified
    # symbols at any depth. Keeping this in sync with _backfill_symbol_references
    # avoids full-backfill vs incremental-update reference drift.
    symbol_rows = conn.execute(
        "SELECT id, file_id, block_name, block_type, open_line, close_line "
        "FROM bracket_index WHERE block_name IS NOT NULL "
        "AND block_type NOT IN ('unknown', 'control_flow')"
    ).fetchall()

    symbol_def_counts: dict[str, int] = {}
    for r in symbol_rows:
        name = r["block_name"]
        if name and len(name) >= config.min_name_length and name not in config.skip_keywords:
            symbol_def_counts[name] = symbol_def_counts.get(name, 0) + 1

    target_symbols: dict[str, list[tuple[str, int, int]]] = {}
    for r in symbol_rows:
        name = r["block_name"]
        if not name or len(name) < config.min_name_length:
            continue
        if name in config.skip_keywords:
            continue
        if symbol_def_counts.get(name, 0) > config.max_definition_count:
            continue
        target_symbols.setdefault(name, []).append((
            r["block_type"], r["file_id"], r["open_line"],
        ))

    if not target_symbols:
        return

    check_set = set(target_symbols)
    skip_line_re_fn = getattr(provider, "skip_line_re", None)
    skip_line_re = skip_line_re_fn() if skip_line_re_fn else None
    skip_names_fn = getattr(provider, "skip_symbol_names", None)
    skip_names = skip_names_fn() if skip_names_fn else frozenset()

    bracket_rows = conn.execute(
        "SELECT id, open_line, close_line, depth, block_type "
        "FROM bracket_index WHERE file_id = ? ORDER BY open_line", (file_id,),
    ).fetchall()
    bracket_data = [dict(b) for b in bracket_rows]

    refs = track_references_for_file(lines, file_id, target_symbols,
                                     skip_line_re=skip_line_re, check_set=check_set,
                                     skip_names=skip_names, bracket_data=bracket_data)
    if not refs:
        return

    bracket_arrays = prepare_bracket_arrays(bracket_data)
    enriched = enrich_ref_block_ids(refs, bracket_arrays)

    conn.executemany(
        "INSERT INTO symbol_references "
        "(symbol_name, symbol_type, symbol_file_id, ref_file_id, ref_block_id, ref_line) "
        "VALUES (?, ?, ?, ?, ?, ?)",
        enriched,
    )


def _build_include_edges(
    conn: sqlite3.Connection,
    file_id: int,
    lines: list[str],
    unique_map: dict[str, int] | None,
    collision_map: dict[str, list[tuple[int, str]]] | None,
    provider: Any = None,
) -> None:
    """Parse #include directives from lines and insert into include_edges.

    provider: if given, uses provider.parse_include_directives(lines) for parsing.
              if None, falls back to hardcoded C/C++ #include regex (backward compat).
    """
    include_rows: list[tuple] = []

    if provider is not None:
        for inc in provider.parse_include_directives(lines):
            if unique_map is not None and collision_map is not None:
                target_id = _match_include_path(inc.path, unique_map, collision_map)
            else:
                target = conn.execute(
                    "SELECT id FROM source_files WHERE file_path LIKE ? LIMIT 1",
                    (f"%{inc.path}",),
                ).fetchone()
                target_id = int(target["id"]) if target else None
            include_rows.append((file_id, inc.path, target_id, inc.line_number))
    else:
        # Fallback: hardcoded C/C++ #include parsing (backward compat)
        _fallback_include_re = re.compile(r'#\s*include\s+[<"]([^>"]+)[>"]')
        for i, line in enumerate(lines, start=1):
            if "include" not in line or "#" not in line:
                continue
            stripped = line.lstrip()
            if not stripped.startswith("#include"):
                continue
            m = _fallback_include_re.match(stripped)
            if not m:
                continue
            inc_path = m.group(1)
            if unique_map is not None and collision_map is not None:
                target_id = _match_include_path(inc_path, unique_map, collision_map)
            else:
                target = conn.execute(
                    "SELECT id FROM source_files WHERE file_path LIKE ? LIMIT 1",
                    (f"%{inc_path}",),
                ).fetchone()
                target_id = int(target["id"]) if target else None
            include_rows.append((file_id, inc_path, target_id, i))

    if include_rows:
        conn.executemany(
            """
            INSERT INTO include_edges (source_file_id, include_path, target_file_id, line_number)
            VALUES (?, ?, ?, ?)
            """,
            include_rows,
        )


def load_bracket_index(
    conn: sqlite3.Connection, file_id: int, depth: int | None = None
) -> list[dict[str, Any]]:
    """Load bracket index entries for a file, optionally filtered by depth."""
    if depth is not None:
        rows = conn.execute(
            """
            SELECT open_line, close_line, depth, block_type, block_name, signature, is_complete
            FROM bracket_index
            WHERE file_id = ? AND depth = ?
            ORDER BY open_line
            """,
            (file_id, depth),
        )
    else:
        rows = conn.execute(
            """
            SELECT open_line, close_line, depth, block_type, block_name, signature, is_complete
            FROM bracket_index
            WHERE file_id = ?
            ORDER BY open_line
            """,
            (file_id,),
        )
    return [dict(r) for r in rows]


def find_enclosing_block(
    bracket_data: list[dict[str, Any]], line_number: int, max_depth: int | None = None
) -> dict[str, Any] | None:
    """Find the innermost enclosing block for a given line number.

    bracket_data must be sorted by open_line ascending.
    Uses binary search for efficiency.
    """
    import bisect

    opens = [b["open_line"] for b in bracket_data]
    # Find rightmost block whose open_line <= line_number
    idx = bisect.bisect_right(opens, line_number) - 1

    # Walk backwards to find the tightest enclosing block
    best = None
    while idx >= 0:
        b = bracket_data[idx]
        if max_depth is not None and b["depth"] > max_depth:
            idx -= 1
            continue
        if b["open_line"] <= line_number <= b["close_line"]:
            if best is None or b["depth"] > best["depth"]:
                best = b
        idx -= 1
    return best


def find_block_for_line(
    conn: sqlite3.Connection,
    file_id: int,
    line: int,
) -> dict[str, Any] | None:
    """Find the deepest bracket block containing the given line."""
    rows = conn.execute(
        """SELECT block_type, block_name, open_line, close_line, signature, depth
           FROM bracket_index
           WHERE file_id = ? AND open_line <= ? AND close_line >= ?
           ORDER BY depth DESC LIMIT 1""",
        (file_id, line, line),
    ).fetchall()
    if rows:
        r = rows[0]
        return {
            "block_type": r["block_type"],
            "block_name": r["block_name"],
            "block_range": f"{r['open_line']}-{r['close_line']}",
            "signature": r["signature"],
        }
    return None


def find_symbol_references(
    conn: sqlite3.Connection,
    symbol_name: str,
    limit: int = 100,
    *,
    scope: str | None = None,
    skip_self_definition: bool = True,
) -> list[dict[str, Any]]:
    """Find references to a symbol from the symbol_references table.

    Returns pre-computed references with file paths and enclosing block info.
    scope: optional module name to filter reference files.
    skip_self_definition: if True, skip rows where the reference is on the
        symbol's own definition line (same file, line near the block open_line).
    """
    params: list[Any] = [symbol_name]
    scope_clause = ""
    if scope:
        scope_clause = " AND ref_file.module_name = ?"
        params.append(scope)

    rows = conn.execute(
        f"""
        SELECT
            sr.symbol_name,
            sr.symbol_type,
            sr.symbol_file_id,
            def_file.file_path AS symbol_file_path,
            sr.ref_file_id,
            ref_file.file_path AS ref_file_path,
            ref_file.module_name AS ref_module_name,
            sr.ref_block_id,
            sr.ref_line,
            br.block_type AS ref_block_type,
            br.block_name AS ref_block_name,
            br.signature AS ref_block_signature,
            br.open_line AS ref_block_open,
            br.close_line AS ref_block_close
        FROM symbol_references sr
        JOIN source_files def_file ON def_file.id = sr.symbol_file_id
        JOIN source_files ref_file ON ref_file.id = sr.ref_file_id
        LEFT JOIN bracket_index br ON br.id = sr.ref_block_id
        WHERE sr.symbol_name = ?{scope_clause}
        ORDER BY sr.ref_file_id, sr.ref_line
        LIMIT ?
        """,
        params + [limit],
    ).fetchall()

    results = [dict(r) for r in rows]

    if skip_self_definition:
        filtered = []
        for r in results:
            if (r["symbol_file_id"] == r["ref_file_id"]
                    and r["ref_block_name"]
                    and r["symbol_name"].lower() in (r["ref_block_name"] or "").lower()
                    and r["ref_block_open"]
                    and abs(r["ref_line"] - r["ref_block_open"]) <= 2):
                continue
            filtered.append(r)
        results = filtered

    return results


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
    """Three-step FTS5 search with deferred snippet and efficient module filter.

    Step 1: bm25 + ORDER BY + LIMIT to get top-N rowids (fast, ~300ms).
    Step 2: If module filter, JOIN against source_files to prune (avoids subquery).
    Step 3: Compute snippet() only for the final top-N rows.

    On 84K files with high-frequency terms, this is 5-8x faster than computing
    snippet for all 10K+ matching rows. With module filter, avoids the slow
    subquery that caused 33s+ queries (now ~80ms).
    """
    # Over-fetch to have headroom for module filtering
    fetch_limit = limit * 5 if module else limit

    # Step 1: Get top rowids with bm25 ranking (no snippet — the expensive part)
    ranked = [dict(r) for r in conn.execute(
        "SELECT source_files_fts.rowid AS fts_rowid, bm25(source_files_fts) AS rank "
        "FROM source_files_fts "
        "WHERE source_files_fts MATCH ? "
        "ORDER BY rank LIMIT ?",
        (fts_query, fetch_limit),
    )]
    if not ranked:
        return []

    # Step 2: Module filter via JOIN on candidate rowids (not subquery)
    if module:
        ids_str = ",".join(str(r["fts_rowid"]) for r in ranked)
        valid_rows = conn.execute(
            f"SELECT id FROM source_files WHERE id IN ({ids_str}) AND module_name = ?",
            (module,),
        ).fetchall()
        valid_ids = {r["id"] for r in valid_rows}
        ranked = [r for r in ranked if r["fts_rowid"] in valid_ids][:limit]
        if not ranked:
            return []

    # Step 3: Fetch file metadata + compact snippets only for the final candidates
    # Use num_tokens=15 so snippets include enough context for precise block attribution.
    # Truncate to 300 chars to keep responses compact for LLM consumption.
    rowids = [str(r["fts_rowid"]) for r in ranked]
    rank_map = {r["fts_rowid"]: r["rank"] for r in ranked}

    results = []
    for row in conn.execute(
        "SELECT sf.id, sf.file_path, sf.module_name, "
        "substr(snippet(source_files_fts, 2, '...', '...', ' … ', 15), 1, 300) AS snippet "
        "FROM source_files_fts JOIN source_files sf ON sf.id = source_files_fts.rowid "
        f"WHERE source_files_fts MATCH ? AND source_files_fts.rowid IN ({','.join(rowids)})",
        (fts_query,),
    ):
        d = dict(row)
        d["rank"] = rank_map.get(d["id"], 0)
        results.append(d)

    # Re-sort by rank (IN clause doesn't preserve order)
    results.sort(key=lambda r: r["rank"])
    return results


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


def _get_history_signals(
    conn: sqlite3.Connection, search_terms: list[str], top_k: int = 20
) -> dict[int, float]:
    """Get history-derived ranking signals for files (NOT a filter).

    Returns dict mapping file_id → weighted score based on past feedback,
    with exponential time decay (30-day half-life).
    """
    if not search_terms:
        return {}
    terms = [t for t in search_terms if len(t) >= 3]
    if not terms:
        return {}

    fts_or = " OR ".join(f'"{t}"' for t in terms)

    rows = conn.execute(
        """
        SELECT ql.id, ql.hit_file_ids, ql.hit_count, ql.created_at,
               SUM(CASE WHEN qn.was_useful = 1 THEN 3.0 ELSE 0 END) AS useful_score,
               SUM(CASE WHEN qn.was_useful = 0 THEN -5.0 ELSE 0 END) AS not_useful_score
        FROM query_logs_fts qft
                JOIN query_logs ql ON ql.id = qft.rowid
                LEFT JOIN query_note qn ON qn.query_log_id = ql.id
        WHERE qft.query_logs_fts MATCH ?
        GROUP BY ql.id
        ORDER BY (
            COALESCE(SUM(CASE WHEN qn.was_useful = 1 THEN 3.0 ELSE 0 END), 0)
            + COALESCE(SUM(CASE WHEN qn.was_useful = 0 THEN -5.0 ELSE 0 END), 0)
            + CASE WHEN ql.hit_count BETWEEN 1 AND 50 THEN 1 ELSE 0 END
        ) * exp(-0.023 * (julianday('now') - julianday(ql.created_at))) DESC
        LIMIT ?
        """,
        (fts_or, top_k),
    ).fetchall()

    # Aggregate scores per file across matched queries
    file_scores: dict[int, float] = {}
    for row in rows:
        days_age = (
            conn.execute("SELECT julianday('now') - julianday(?)", (row["created_at"],)).fetchone()[0]
            or 0
        )
        time_decay = math.exp(-0.023 * days_age)
        feedback = (row["useful_score"] or 0) + (row["not_useful_score"] or 0)
        query_score = (feedback + (1 if 1 <= (row["hit_count"] or 0) <= 50 else 0)) * time_decay

        for fid in json.loads(row["hit_file_ids"]):
            file_scores[fid] = file_scores.get(fid, 0) + query_score

    return file_scores


def _snippet_to_line_numbers(
    content: str, snippet: str, marker: str = "...", separator: str = " … "
) -> list[int]:
    """Extract hit line numbers from an FTS5 snippet by matching fragments back into raw_content.

    FTS5 snippet() returns raw text fragments from the indexed column.
    By stripping match markers and searching in raw_content, we recover
    the character offset of each fragment and convert to 1-based line numbers.

    Lines <5 (file header / copyright / first include) are filtered out as
    they're never inside a meaningful code block.
    """
    lines: list[int] = []
    fragments = snippet.split(separator)
    for frag in fragments:
        clean = frag.replace(marker, "")
        if len(clean.strip()) < 5:
            continue
        pos = content.find(clean)
        line = -1
        if pos >= 0:
            line = content[:pos].count("\n") + 1
        else:
            # substr truncation fallback: match with leading portion
            trunc = clean[: max(1, int(len(clean) * 0.8))]
            pos2 = content.find(trunc)
            if pos2 >= 0:
                line = content[:pos2].count("\n") + 1
        if line >= 5:
            lines.append(line)
    return lines


def _locate_hit_block(
    conn: sqlite3.Connection,
    result: dict[str, Any],
    *,
    bracket_cache: dict[int, list[dict[str, Any]]] | None = None,
    content_cache: dict[int, str] | None = None,
) -> dict[str, Any] | None:
    """Locate the enclosing bracket block for an FTS hit.

    Shared by _cluster_results and _apply_scope_filter.
    Returns the depth=1 bracket block dict, or None.
    """
    import bisect as _bisect

    fid = result["id"]
    brackets = (bracket_cache or {}).get(fid)
    if brackets is None:
        brackets = load_bracket_index(conn, fid, depth=1)

    content = (content_cache or {}).get(fid)
    if content is None:
        row = conn.execute(
            "SELECT raw_content FROM source_files WHERE id = ?", (fid,)
        ).fetchone()
        content = row["raw_content"] if row else None

    if not content or not brackets:
        return None

    hit_lines = _snippet_to_line_numbers(content, result["snippet"])
    if not hit_lines:
        return None

    block = find_enclosing_block(brackets, hit_lines[0], max_depth=1)
    if block is None:
        opens = [b["open_line"] for b in brackets]
        idx = _bisect.bisect_right(opens, hit_lines[0])
        if idx < len(brackets) and brackets[idx]["open_line"] - hit_lines[0] <= 20:
            block = brackets[idx]
    return block


def _cluster_results(
    conn: sqlite3.Connection, fts_results: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    """Cluster FTS results by enclosing code block using bracket skeleton.

    Uses _locate_hit_block to find the precise enclosing block
    for each hit, then merges hits in the same block into one result.
    """
    if not fts_results:
        return []

    from collections import defaultdict

    file_ids = list({r["id"] for r in fts_results})

    # Batch-load raw_content and bracket indices
    id_list = ",".join(str(fid) for fid in file_ids)
    content_map: dict[int, str] = {}
    for row in conn.execute(
        f"SELECT id, raw_content FROM source_files WHERE id IN ({id_list})"
    ):
        content_map[row["id"]] = row["raw_content"]

    bracket_cache: dict[int, list[dict[str, Any]]] = {}
    for fid in file_ids:
        bracket_cache[fid] = load_bracket_index(conn, fid, depth=1)

    # Group results by enclosing block
    clusters: dict[tuple[int, int], list[dict[str, Any]]] = defaultdict(list)

    for r in fts_results:
        block = _locate_hit_block(
            conn, r, bracket_cache=bracket_cache, content_cache=content_map
        )
        key = (r["id"], block["open_line"]) if block else (r["id"], 0)
        clusters[key].append(r)

    # Build clustered results
    clustered = []
    for (fid, block_start), hits in clusters.items():
        best_hit = min(hits, key=lambda h: h["rank"])
        brackets = bracket_cache.get(fid, [])
        block = None
        for b in brackets:
            if b["open_line"] == block_start:
                block = b
                break

        entry = {
            "id": fid,
            "file_path": best_hit["file_path"],
            "module_name": best_hit["module_name"],
            "rank": best_hit["rank"],
            "final_score": best_hit.get("final_score", best_hit["rank"]),
            "snippet": best_hit["snippet"],
            "hit_count": len(hits),
            "source": best_hit.get("source", "fts"),
        }
        if block:
            entry["cluster"] = {
                "block_type": block["block_type"],
                "block_name": block["block_name"],
                "open_line": block["open_line"],
                "close_line": block["close_line"],
            }
        clustered.append(entry)

    return clustered


def search_source_with_feedback(
    conn: sqlite3.Connection,
    *,
    query: str | None = None,
    raw_query: str | None = None,
    expanded_terms: list[str] | None = None,
    module: str | None = None,
    limit: int = 20,
    cluster: bool = False,
    scope_filter: dict[str, str] | None = None,
) -> list[dict[str, Any]]:
    """Search with history-as-ranking-signal and optional bracket clustering.

    Always performs full FTS5 search. History signals adjust ranking but
    never filter out results (prevents confirmation bias).

    cluster: if True, merge hits in the same code block into one result.
    scope_filter: optional dict with block_type and/or block_name to narrow scope.
    """
    query_text = raw_query or query
    if not query_text:
        return []
    fts_query = raw_query if raw_query else _fts5_escape(query)
    terms = _extract_search_terms(query_text)

    if expanded_terms:
        seen = {t.lower() for t in terms}
        for t in expanded_terms:
            if len(t) >= 3 and t.lower() not in seen:
                seen.add(t.lower())
                terms.append(t)

    # Step 1: Full FTS5 search with expanded limit for ranking headroom
    overfetch = limit * 10 if scope_filter else limit * 5
    all_results = _search_fts(conn, fts_query, module, limit=overfetch)

    # Step 2: History signals (ranking only, not filtering)
    history_scores = _get_history_signals(conn, terms)

    # Step 3: Composite scoring
    for r in all_results:
        base_score = max(0, min(10, -r["rank"] / 2))
        hist_bonus = max(-3, min(5, history_scores.get(r["id"], 0)))
        discovery = 1.0 if r["id"] not in history_scores and base_score > 3 else 0
        r["final_score"] = base_score + hist_bonus + discovery
        r["source"] = "history_refined" if r["id"] in history_scores else "fts"

    all_results.sort(key=lambda r: -r["final_score"])

    # Step 4: Optional scope filtering using bracket_index (hit-level)
    if scope_filter:
        _apply_scope_filter(conn, all_results, scope_filter)

    results = all_results[:limit]

    # Step 4.5: Enrich results with enclosing block metadata
    if results:
        _enrich_with_block_info(conn, results)

    # Step 5: Optional clustering
    if cluster and results:
        results = _cluster_results(conn, results)
        results.sort(key=lambda r: -r.get("final_score", r["rank"]))

    log_query(conn, query_text, fts_query, [r["id"] for r in results[:limit]])
    return results


def _enrich_with_block_info(
    conn: sqlite3.Connection,
    results: list[dict[str, Any]],
) -> None:
    """Add block_type, block_name, block_range to each search result."""
    if not results:
        return

    file_ids = list({r["id"] for r in results})
    bracket_cache: dict[int, list[dict[str, Any]]] = {}
    content_cache: dict[int, str] = {}

    for fid in file_ids:
        bracket_cache[fid] = load_bracket_index(conn, fid, depth=1)

    id_list = ",".join(str(fid) for fid in file_ids)
    for row in conn.execute(
        f"SELECT id, raw_content FROM source_files WHERE id IN ({id_list})"
    ):
        content_cache[row["id"]] = row["raw_content"]

    for r in results:
        block = _locate_hit_block(
            conn, r, bracket_cache=bracket_cache, content_cache=content_cache
        )
        if block:
            r["block_type"] = block["block_type"]
            r["block_name"] = block.get("block_name")
            r["block_range"] = f"{block['open_line']}-{block['close_line']}"


def _apply_scope_filter(
    conn: sqlite3.Connection,
    results: list[dict[str, Any]],
    scope_filter: dict[str, str],
) -> None:
    """Remove results whose enclosing block doesn't match scope_filter.

    Uses _locate_hit_block for hit-level matching: only filters out results
    whose FTS hit falls inside a non-matching block, rather than checking
    if the file contains any matching block (file-level).
    """
    allowed_types = set()
    if "block_type" in scope_filter:
        allowed_types.add(scope_filter["block_type"])

    target_name = scope_filter.get("block_name", "").lower()

    to_remove = []
    for i, r in enumerate(results):
        block = _locate_hit_block(conn, r)
        if block:
            type_ok = (not allowed_types) or (block["block_type"] in allowed_types)
            name_ok = (not target_name) or ((block.get("block_name") or "").lower() == target_name)
            if not (type_ok and name_ok):
                to_remove.append(i)
        else:
            # No block info — remove if type filtering is active
            if allowed_types:
                to_remove.append(i)

    for i in reversed(to_remove):
        results.pop(i)


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


# ---------------------------------------------------------------------------
# Raw SQL passthrough
# ---------------------------------------------------------------------------

_MAX_SQL_ROWS = 200
_SELECT_ONLY_RE = re.compile(r"^\s*(?:SELECT|WITH)\s", re.IGNORECASE | re.DOTALL)


def exec_sql_query(
    conn: sqlite3.Connection,
    sql: str,
    expanded_terms: list[str] | None = None,
    max_rows: int = _MAX_SQL_ROWS,
) -> dict[str, Any]:
    """Execute a read-only SQL query with optional history enrichment.

    Returns ``{"results": [...], "meta": {row_count, truncated, history_enriched}}``.
    Only SELECT / WITH statements are allowed.  Results capped at *max_rows*.
    """
    if not _SELECT_ONLY_RE.match(sql.strip()):
        return {"error": "Only SELECT / WITH queries are allowed", "results": [], "meta": {}}

    conn.execute("PRAGMA query_only=ON")
    try:
        cursor = conn.execute(sql)
        rows = cursor.fetchmany(max_rows + 1)
        truncated = len(rows) > max_rows
        if truncated:
            rows = rows[:max_rows]
        results: list[dict[str, Any]] = [dict(r) for r in rows]
    except Exception as exc:
        return {"error": f"SQL error: {exc}", "results": [], "meta": {}}
    finally:
        conn.execute("PRAGMA query_only=OFF")

    # --- history enrichment ---------------------------------------------------
    history_enriched = False
    if expanded_terms and results:
        terms = list(expanded_terms)
        for t in _extract_search_terms(sql):
            if t not in terms:
                terms.append(t)
        terms = list(dict.fromkeys(t for t in terms if len(t) >= 3))

        history_scores = _get_history_signals(conn, terms)
        if history_scores:
            has_file_id = any("file_id" in r for r in results)
            has_file_path = any("file_path" in r for r in results)

            if has_file_id:
                for r in results:
                    fid = r.get("file_id")
                    if fid and fid in history_scores:
                        r["history_score"] = round(history_scores[fid], 3)
                        history_enriched = True
            elif has_file_path:
                paths = list({r["file_path"] for r in results if r.get("file_path")})
                if paths:
                    ph = ",".join("?" * len(paths))
                    path_map = dict(
                        conn.execute(
                            f"SELECT file_path, id FROM source_files WHERE file_path IN ({ph})",
                            paths,
                        ).fetchall()
                    )
                    for r in results:
                        fid = path_map.get(r.get("file_path"))
                        if fid and fid in history_scores:
                            r["history_score"] = round(history_scores[fid], 3)
                            history_enriched = True

    # --- log query ------------------------------------------------------------
    hit_file_ids: list[int] = []
    for r in results:
        fid = r.get("file_id") or r.get("id")
        if isinstance(fid, int):
            hit_file_ids.append(fid)
    log_query(conn, sql[:500], None, hit_file_ids)

    return {
        "results": results,
        "meta": {
            "row_count": len(results),
            "truncated": truncated,
            "history_enriched": history_enriched,
        },
    }


def get_directory_structure(conn: sqlite3.Connection) -> dict[str, Any]:
    """Return a compact directory structure summary from the indexed database.

    Returns:
      - total_files: total number of indexed files.
      - total_modules: total number of distinct modules.
      - modules: list of {module_name, file_count} — top 30 by file_count DESC.
        module_name is None for files that couldn't be classified.
      - top_dirs: dict with level_1 and level_2 keys, each a list of
        {path, file_count} capped at 50 entries.
    """
    total = conn.execute("SELECT COUNT(*) AS c FROM source_files").fetchone()["c"]

    # Module breakdown — top 30
    modules = [
        dict(r)
        for r in conn.execute(
            "SELECT module_name, COUNT(*) AS file_count "
            "FROM source_files GROUP BY module_name ORDER BY file_count DESC LIMIT 30"
        ).fetchall()
    ]

    total_modules = conn.execute(
        "SELECT COUNT(DISTINCT module_name) AS c FROM source_files"
    ).fetchone()["c"]

    # Level 1: first path component
    level_1 = [
        dict(r)
        for r in conn.execute(
            "SELECT "
            "  CASE WHEN instr(file_path, '/') = 0 THEN file_path "
            "       ELSE substr(file_path, 1, instr(file_path, '/') - 1) "
            "  END AS path, "
            "  COUNT(*) AS file_count "
            "FROM source_files GROUP BY path ORDER BY file_count DESC LIMIT 50"
        ).fetchall()
    ]

    # Level 2: first two path components
    level_2 = [
        dict(r)
        for r in conn.execute(
            "WITH parts AS ("
            "  SELECT file_path,"
            "    CASE WHEN instr(file_path, '/') = 0 THEN file_path"
            "         ELSE substr(file_path, 1, instr(file_path, '/') - 1)"
            "    END AS p1,"
            "    substr(file_path, instr(file_path, '/') + 1) AS rest"
            "  FROM source_files"
            ")"
            "SELECT"
            "  CASE"
            "    WHEN instr(rest, '/') = 0 THEN p1 || '/' || rest"
            "    ELSE p1 || '/' || substr(rest, 1, instr(rest, '/') - 1)"
            "  END AS path,"
            "  COUNT(*) AS file_count"
            " FROM parts GROUP BY path ORDER BY file_count DESC LIMIT 50"
        ).fetchall()
    ]

    return {
        "total_files": total,
        "total_modules": total_modules,
        "modules": modules,
        "top_dirs": {
            "level_1": level_1,
            "level_2": level_2,
        },
    }


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
