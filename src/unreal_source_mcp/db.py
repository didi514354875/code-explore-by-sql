from __future__ import annotations

import json
import math
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

        CREATE TABLE IF NOT EXISTS bracket_index (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            file_id INTEGER NOT NULL REFERENCES source_files(id) ON DELETE CASCADE,
            open_line INTEGER NOT NULL,
            close_line INTEGER NOT NULL,
            depth INTEGER NOT NULL,
            block_type TEXT NOT NULL DEFAULT 'unknown',
            block_name TEXT,
            signature TEXT,
            is_complete INTEGER NOT NULL DEFAULT 1
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


def _scan_file_content(
    file_id: int, content: str,
    unique_map: dict[str, int], collision_map: dict[str, list[tuple[int, str]]],
) -> tuple[int, list[tuple], list[tuple]]:
    """Pure-CPU bracket scan + symbol sniff + include parse (no DB access).

    Designed to run in a subprocess. Returns (file_id, bracket_rows, include_rows).
    """
    from unreal_source_mcp.bracket_scanner import scan_brackets
    from unreal_source_mcp.symbol_sniffer import sniff_blocks_for_file

    bracket_rows: list[tuple] = []
    include_rows: list[tuple] = []

    lines = content.split("\n")

    if "{" not in content:
        # No braces — only parse includes
        for i, line in enumerate(lines, start=1):
            if "include" not in line or "#" not in line:
                continue
            stripped = line.lstrip()
            if not stripped.startswith("#include"):
                continue
            m = _INCLUDE_RE.match(stripped)
            if m:
                inc_path = m.group(1)
                target_id = _match_include_path(inc_path, unique_map, collision_map)
                include_rows.append((file_id, inc_path, target_id, i))
        return (file_id, bracket_rows, include_rows)

    blocks = scan_brackets(content, lines=lines)

    # Sniff top-level blocks
    top_blocks = [(b.open_line - 1, b.close_line - 1) for b in blocks if b.depth == 1]
    sniffed = sniff_blocks_for_file(lines, top_blocks)
    sniff_map = {open_0: info for open_0, info in sniffed}

    for b in blocks:
        open_0 = b.open_line - 1
        info = sniff_map.get(open_0)
        bracket_rows.append((
            file_id, b.open_line, b.close_line, b.depth,
            info.block_type if info else "unknown",
            info.block_name if info else None,
            (info.signature[:500] if info and info.signature else None),
            int(b.is_complete),
        ))

    # Parse includes
    for i, line in enumerate(lines, start=1):
        if "include" not in line or "#" not in line:
            continue
        stripped = line.lstrip()
        if not stripped.startswith("#include"):
            continue
        m = _INCLUDE_RE.match(stripped)
        if m:
            inc_path = m.group(1)
            target_id = _match_include_path(inc_path, unique_map, collision_map)
            include_rows.append((file_id, inc_path, target_id, i))

    return (file_id, bracket_rows, include_rows)


def _scan_file_worker(args: tuple) -> tuple:
    """Multiprocessing worker wrapper — unpacks args tuple."""
    file_id, content, unique_map, collision_map = args
    return _scan_file_content(file_id, content, unique_map, collision_map)


def backfill_structural_index(
    conn: sqlite3.Connection, batch_size: int = 500, workers: int = 0,
) -> int:
    """Rebuild bracket_index and include_edges for all existing files.

    Uses multiprocessing for CPU-bound scanning when >= 4 cores available.
    On <= 2 core machines, falls back to single-process to avoid memory/IO pressure.
    workers: number of parallel processes. 0 = auto-detect (uses multi only if >= 4 cores).
    """
    import os

    unique_map, collision_map = _build_path_lookup(conn)
    total_files = conn.execute("SELECT COUNT(*) as c FROM source_files").fetchone()["c"]

    cpu_count = os.cpu_count() or 2
    if workers == 0:
        workers = 1 if cpu_count <= 2 else min(cpu_count - 1, 8)

    # Clear existing structural data
    conn.execute("DELETE FROM bracket_index")
    conn.execute("DELETE FROM include_edges")
    conn.commit()

    total = 0
    _BRACKET_SQL = "INSERT INTO bracket_index (file_id, open_line, close_line, depth, block_type, block_name, signature, is_complete) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
    _INCLUDE_SQL = "INSERT INTO include_edges (source_file_id, include_path, target_file_id, line_number) VALUES (?, ?, ?, ?)"

    if workers <= 1:
        # Single-process: load files in batches to limit memory
        offset = 0
        while True:
            rows = conn.execute(
                "SELECT id, raw_content FROM source_files ORDER BY id LIMIT ? OFFSET ?",
                (batch_size, offset),
            ).fetchall()
            if not rows:
                break
            for row in rows:
                file_id, bracket_rows, include_rows = _scan_file_content(
                    row["id"], row["raw_content"], unique_map, collision_map,
                )
                if bracket_rows:
                    conn.executemany(_BRACKET_SQL, bracket_rows)
                if include_rows:
                    conn.executemany(_INCLUDE_SQL, include_rows)
                total += 1
            conn.commit()
            offset += batch_size
            print(f"  backfill: {total}/{total_files} ({total/total_files*100:.0f}%)", flush=True)
    else:
        # Multi-process: load files in batches, scan in parallel, write in main process
        from multiprocessing import Pool

        with Pool(processes=workers) as pool:
            offset = 0
            while True:
                rows = conn.execute(
                    "SELECT id, raw_content FROM source_files ORDER BY id LIMIT ? OFFSET ?",
                    (batch_size, offset),
                ).fetchall()
                if not rows:
                    break

                # Build args for this batch only (limits memory)
                task_args = [
                    (row["id"], row["raw_content"], unique_map, collision_map)
                    for row in rows
                ]
                results = pool.map(_scan_file_worker, task_args)

                for file_id, bracket_rows, include_rows in results:
                    if bracket_rows:
                        conn.executemany(_BRACKET_SQL, bracket_rows)
                    if include_rows:
                        conn.executemany(_INCLUDE_SQL, include_rows)
                    total += 1

                conn.commit()
                offset += batch_size
                print(f"  backfill: {total}/{total_files} ({total/total_files*100:.0f}%)", flush=True)

    return total


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

_INCLUDE_RE = re.compile(r'#\s*include\s+[<"]([^>"]+)[>"]')


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
) -> None:
    """Build bracket_index and include_edges for a single file.

    skip_delete: skip DELETE for new files (backfill optimization).
    unique_map/collision_map: pre-built include lookups (avoids per-include LIKE queries).
    auto_commit: if False, caller is responsible for committing (batch optimization).
    """
    from unreal_source_mcp.bracket_scanner import scan_brackets
    from unreal_source_mcp.symbol_sniffer import sniff_blocks_for_file

    if not skip_delete:
        conn.execute("DELETE FROM bracket_index WHERE file_id = ?", (file_id,))
        conn.execute("DELETE FROM include_edges WHERE source_file_id = ?", (file_id,))

    # Fast path: files with no braces — only parse includes, skip scanning
    has_braces = "{" in content

    lines = content.split("\n")

    if not has_braces:
        # Only parse #include directives, skip bracket scanning and sniffing
        _build_include_edges(conn, file_id, lines, unique_map, collision_map)
        if auto_commit:
            conn.commit()
        return

    blocks = scan_brackets(content, lines=lines)

    # Sniff top-level blocks (depth=1) for type/name
    top_blocks = [
        (b.open_line - 1, b.close_line - 1)  # convert to 0-based
        for b in blocks
        if b.depth == 1
    ]
    sniffed = sniff_blocks_for_file(lines, top_blocks)
    sniff_map = {open_0: info for open_0, info in sniffed}

    # Insert bracket blocks
    rows = []
    for b in blocks:
        open_0 = b.open_line - 1
        info = sniff_map.get(open_0)
        rows.append(
            (
                file_id,
                b.open_line,
                b.close_line,
                b.depth,
                info.block_type if info else "unknown",
                info.block_name if info else None,
                (info.signature[:500] if info and info.signature else None),
                int(b.is_complete),
            )
        )

    if rows:
        conn.executemany(
            """
            INSERT INTO bracket_index
                (file_id, open_line, close_line, depth, block_type, block_name, signature, is_complete)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            rows,
        )

    # Parse #include directives and build edges
    _build_include_edges(conn, file_id, lines, unique_map, collision_map)

    if auto_commit:
        conn.commit()


def _build_include_edges(
    conn: sqlite3.Connection,
    file_id: int,
    lines: list[str],
    unique_map: dict[str, int] | None,
    collision_map: dict[str, list[tuple[int, str]]] | None,
) -> None:
    """Parse #include directives from lines and insert into include_edges."""
    include_rows: list[tuple] = []
    for i, line in enumerate(lines, start=1):
        if "include" not in line or "#" not in line:
            continue
        stripped = line.lstrip()
        if not stripped.startswith("#include"):
            continue
        m = _INCLUDE_RE.match(stripped)
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

    if auto_commit:
        conn.commit()


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
    # Trigram tokenizer's snippet() returns full lines around matches which can be
    # very large. We truncate to 300 chars to keep responses compact for LLM consumption.
    rowids = [str(r["fts_rowid"]) for r in ranked]
    rank_map = {r["fts_rowid"]: r["rank"] for r in ranked}

    results = []
    for row in conn.execute(
        "SELECT sf.id, sf.file_path, sf.module_name, "
        "substr(snippet(source_files_fts, 2, '...', '...', ' … ', 6), 1, 300) AS snippet "
        "FROM source_files_fts JOIN source_files sf ON sf.id = source_files_fts.rowid "
        f"WHERE source_files_fts.rowid IN ({','.join(rowids)})"
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


def _cluster_results(
    conn: sqlite3.Connection, fts_results: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    """Cluster FTS results by enclosing code block using bracket skeleton.

    Multiple hits in the same top-level block are merged into one result
    with hit_count and the best snippet.
    """
    if not fts_results:
        return []

    # Batch-load bracket indices for all involved files
    file_ids = list({r["id"] for r in fts_results})
    bracket_cache: dict[int, list[dict[str, Any]]] = {}
    for fid in file_ids:
        bracket_cache[fid] = load_bracket_index(conn, fid, depth=1)

    # Group results by enclosing block
    from collections import defaultdict

    clusters: dict[tuple[int, int], list[dict[str, Any]]] = defaultdict(list)

    for r in fts_results:
        # Extract line number from snippet position (approximate)
        # We use the file content to find actual match lines
        brackets = bracket_cache.get(r["id"], [])
        # For now, cluster by file since we don't have exact line numbers from FTS5
        # We use the bracket data to find the first matching block
        # This is a simplification — full implementation would need match positions
        key = (r["id"], 0)  # file-level clustering as baseline
        if brackets:
            key = (r["id"], brackets[0]["open_line"])
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
    all_results = _search_fts(conn, fts_query, module, limit=limit * 5)

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

    # Step 4: Optional scope filtering using bracket_index
    if scope_filter:
        _apply_scope_filter(conn, all_results, scope_filter)

    results = all_results[:limit]

    # Step 5: Optional clustering
    if cluster and results:
        results = _cluster_results(conn, results)
        results.sort(key=lambda r: -r.get("final_score", r["rank"]))

    log_query(conn, query_text, fts_query, [r["id"] for r in results[:limit]])
    return results


def _apply_scope_filter(
    conn: sqlite3.Connection,
    results: list[dict[str, Any]],
    scope_filter: dict[str, str],
) -> None:
    """Remove results whose enclosing block doesn't match scope_filter."""
    allowed_types = set()
    if "block_type" in scope_filter:
        allowed_types.add(scope_filter["block_type"])

    target_name = scope_filter.get("block_name", "").lower()

    to_remove = []
    for i, r in enumerate(results):
        brackets = load_bracket_index(conn, r["id"], depth=1)
        if not brackets:
            # No structural data — keep if no strict filtering
            if allowed_types:
                to_remove.append(i)
            continue

        # Check if any top-level block in this file matches the scope
        matched = False
        for b in brackets:
            if allowed_types and b["block_type"] not in allowed_types:
                continue
            if target_name and (b.get("block_name") or "").lower() != target_name:
                continue
            matched = True
            break

        if not matched:
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
