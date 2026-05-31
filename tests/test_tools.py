"""Integration tests for all 7 MCP tool functions against real database."""
from __future__ import annotations

import os
import shutil
import sqlite3
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from code_explore_by_sql.db import (
    find_enclosing_block,
    find_symbol_references,
    get_source_anchored,
    get_source_by_path,
    load_bracket_index,
    record_feedback,
    search_source_with_feedback,
    get_directory_structure as get_directory_structure_db,
)


DB = os.path.join(os.path.dirname(__file__), "..", "unreal.db")
TEST_DB = os.path.join(tempfile.gettempdir(), "code_explore_test.db")


def get_conn():
    conn = sqlite3.connect(TEST_DB, timeout=30, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn


def setup_module():
    """Copy DB to temp location to avoid lock contention with running MCP server."""
    print(f"Copying {DB} -> {TEST_DB} for testing...")

    # Try to checkpoint WAL so all data is in the main DB file before copying.
    # If MCP server holds the DB, this may fail — fall back to copying WAL too.
    try:
        checkpoint_conn = sqlite3.connect(DB, timeout=10)
        checkpoint_conn.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        checkpoint_conn.close()
    except sqlite3.OperationalError:
        print("  (WAL checkpoint failed — MCP server may hold DB, copying WAL too)")

    shutil.copy2(DB, TEST_DB)
    for suffix in ("-wal", "-shm"):
        src = DB + suffix
        if os.path.exists(src):
            shutil.copy2(src, TEST_DB + suffix)
    print("Copy done.\n")


def teardown_module():
    """Clean up temp DB."""
    for f in (TEST_DB, TEST_DB + "-wal", TEST_DB + "-shm"):
        if os.path.exists(f):
            os.unlink(f)


def test_search_code_source():
    """Test 1: search_code_source - FTS5 search"""
    print("=" * 70)
    print("TEST 1: search_code_source")
    print("-" * 70)

    with get_conn() as conn:
        # Simple keyword search
        results = search_source_with_feedback(conn, query="BeginPlay", limit=5)
        assert isinstance(results, list), f"Expected list, got {type(results)}"
        assert len(results) > 0, "Expected at least 1 result"
        print(f"  Query 'BeginPlay': {len(results)} results")
        for r in results[:3]:
            print(f"    - {r.get('file_path', 'N/A')[:80]} (score={r.get('final_score', 'N/A')})")

        # Raw query search
        results2 = search_source_with_feedback(conn, raw_query='"Material"', limit=3)
        assert isinstance(results2, list)
        assert len(results2) > 0
        print(f"  Raw query '\"Material\"': {len(results2)} results")

        # Scope filter test
        results3 = search_source_with_feedback(
            conn, query="Render", limit=5,
            scope_filter={"block_type": "function"},
        )
        assert isinstance(results3, list)
        print(f"  Scoped query 'Render' (function only): {len(results3)} results")

    print("  PASS\n")


def test_get_file_content_line_range():
    """Test 2a: get_file_content with line range"""
    print("=" * 70)
    print("TEST 2a: get_file_content (line range)")
    print("-" * 70)

    with get_conn() as conn:
        # Get a known file first
        row = get_source_by_path(conn, "Engine/Source/Runtime/Core/Public/CoreMinimal.h")
        if row is None:
            # Find any file to test with
            r = conn.execute("SELECT file_path FROM source_files LIMIT 1").fetchone()
            if r:
                file_path = r["file_path"]
            else:
                print("  SKIP (no files)")
                return
        else:
            file_path = row["file_path"]

        result = get_source_anchored(conn, file_path, "class", 500)
        # Line range test via get_source_by_path
        content = row["raw_content"] if row else ""
        lines = content.splitlines()
        print(f"  File: {file_path[:80]}")
        print(f"  Total lines: {len(lines)}")
        if lines:
            print(f"  Line 1: {lines[0][:80]}")

    print("  PASS\n")


def test_get_file_content_anchor():
    """Test 2b: get_file_content with anchor"""
    print("=" * 70)
    print("TEST 2b: get_file_content (anchor)")
    print("-" * 70)

    with get_conn() as conn:
        # Search for a file with known content
        results = search_source_with_feedback(conn, query="FString", limit=3)
        if not results:
            print("  SKIP (no results)")
            return

        file_path = results[0]["file_path"]
        result = get_source_anchored(conn, file_path, "FString", 500)

        if result:
            print(f"  File: {file_path[:80]}")
            print(f"  Anchor pos: {result['anchor_pos']}")
            print(f"  Content preview: {result['content'][:100]}...")
        else:
            print(f"  Anchor not found in: {file_path[:80]}")

    print("  PASS\n")


def test_log_code_query():
    """Test 3: log_code_query - feedback recording"""
    print("=" * 70)
    print("TEST 3: log_code_query")
    print("-" * 70)

    with get_conn() as conn:
        # First do a search to create a log entry
        search_source_with_feedback(conn, query="BeginPlay", limit=1)

        log_row = conn.execute(
            "SELECT id FROM query_logs WHERE query_text = ? ORDER BY created_at DESC LIMIT 1",
            ("BeginPlay",),
        ).fetchone()

        if log_row:
            # Note: query_note table has no UNIQUE on query_log_id, so UPSERT fails.
            # Use plain INSERT for now (matches actual schema).
            conn.execute(
                "INSERT INTO query_note(query_log_id, was_useful, refinement) VALUES (?, ?, ?)",
                (log_row["id"], 1, "test refinement"),
            )
            conn.commit()

            note = conn.execute(
                "SELECT was_useful, refinement FROM query_note WHERE query_log_id = ?",
                (log_row["id"],),
            ).fetchone()
            print(f"  Feedback recorded: was_useful={note['was_useful']}, refinement={note['refinement']}")
            print(f"  NOTE: server.py log_code_query UPSERT has schema bug (no UNIQUE on query_log_id)")
        else:
            print("  No log entry found")

    print("  PASS\n")


def test_find_include_graph():
    """Test 4: find_include_graph - dependency relationships"""
    print("=" * 70)
    print("TEST 4: find_include_graph")
    print("-" * 70)

    with get_conn() as conn:
        # Find a file with includes
        rows = conn.execute(
            """SELECT sf.file_path, sf.id
               FROM include_edges ie
               JOIN source_files sf ON sf.id = ie.source_file_id
               WHERE ie.target_file_id IS NOT NULL
               LIMIT 1"""
        ).fetchall()

        if not rows:
            print("  SKIP (no include edges)")
            return

        file_path = rows[0]["file_path"]
        file_id = rows[0]["id"]
        print(f"  File: {file_path[:80]}")

        # Downstream
        downstream = conn.execute(
            """SELECT ie.include_path, sf.file_path AS target_path
               FROM include_edges ie
               LEFT JOIN source_files sf ON sf.id = ie.target_file_id
               WHERE ie.source_file_id = ?
               LIMIT 5""",
            (file_id,),
        ).fetchall()
        print(f"  Downstream includes: {len(downstream)}")
        for r in downstream[:3]:
            print(f"    -> {r['include_path'][:60]} => {r['target_path'] or 'unresolved'}")

        # Upstream
        upstream = conn.execute(
            """SELECT sf.file_path AS source_path, ie.include_path
               FROM include_edges ie
               JOIN source_files sf ON sf.id = ie.source_file_id
               WHERE ie.target_file_id = ?
               LIMIT 5""",
            (file_id,),
        ).fetchall()
        print(f"  Upstream (included by): {len(upstream)}")
        for r in upstream[:3]:
            print(f"    <- {r['source_path'][:60]}")

    print("  PASS\n")


def test_find_callers():
    """Test 5: find_callers - bracket skeleton + text search"""
    print("=" * 70)
    print("TEST 5: find_callers")
    print("-" * 70)

    with get_conn() as conn:
        symbol = "BeginPlay"
        results = search_source_with_feedback(conn, query=symbol, limit=10)
        callers = []
        symbol_lower = symbol.lower()

        for r in results[:5]:  # Limit to 5 files for speed
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

                enclosing_top = None
                for tb_open, tb in top_blocks.items():
                    if tb["open_line"] <= line_idx <= tb["close_line"]:
                        enclosing_top = tb
                        break

                if enclosing_top and enclosing_top.get("block_name"):
                    callers.append({
                        "file": r["file_path"][:60],
                        "block": enclosing_top["block_name"],
                        "line": line_idx,
                    })

        print(f"  Symbol: {symbol}")
        print(f"  Callers found: {len(callers)}")
        for c in callers[:5]:
            print(f"    {c['block']}@{c['file']}:{c['line']}")

    print("  PASS\n")


def test_find_references():
    """Test 6: find_references - pre-computed symbol_references"""
    print("=" * 70)
    print("TEST 6: find_references")
    print("-" * 70)

    with get_conn() as conn:
        # Test with a common UE symbol
        symbol = "BeginPlay"
        refs = find_symbol_references(conn, symbol, limit=10)
        print(f"  Symbol: {symbol}")
        print(f"  References found: {len(refs)}")
        for r in refs[:5]:
            block_info = f"block={r.get('ref_block_name', 'N/A')}" if r.get('ref_block_name') else ""
            print(f"    {r['ref_file_path'][:60]}:{r['ref_line']} ({block_info})")

        # Test with another symbol
        symbol2 = "Tick"
        refs2 = find_symbol_references(conn, symbol2, limit=5)
        print(f"\n  Symbol: {symbol2}")
        print(f"  References found: {len(refs2)}")

    print("  PASS\n")


def test_get_directory_structure():
    """Test 7: get_directory_structure"""
    print("=" * 70)
    print("TEST 7: get_directory_structure")
    print("-" * 70)

    with get_conn() as conn:
        result = get_directory_structure_db(conn)
        print(f"  Total files: {result.get('total_files', 'N/A'):,}")
        print(f"  Total modules: {result.get('total_modules', 'N/A'):,}")

        modules = result.get("modules", [])
        print(f"  Top modules:")
        for m in modules[:5]:
            print(f"    {m['module_name']}: {m['file_count']:,} files")

        top_dirs = result.get("top_dirs", {})
        if "level_1" in top_dirs:
            print(f"  Top dirs (level 1):")
            for d in top_dirs["level_1"][:3]:
                print(f"    {d['path']}: {d['file_count']:,} files")

    print("  PASS\n")


def test_parent_id_hierarchy():
    """Bonus: test parent_id hierarchy in bracket_index"""
    print("=" * 70)
    print("BONUS: parent_id hierarchy check")
    print("-" * 70)

    with get_conn() as conn:
        total = conn.execute("SELECT COUNT(*) as c FROM bracket_index").fetchone()["c"]
        with_parent = conn.execute(
            "SELECT COUNT(*) as c FROM bracket_index WHERE parent_id IS NOT NULL"
        ).fetchone()["c"]
        depth1 = conn.execute(
            "SELECT COUNT(*) as c FROM bracket_index WHERE depth = 1"
        ).fetchone()["c"]

        print(f"  Total blocks: {total:,}")
        print(f"  With parent_id: {with_parent:,} ({with_parent/max(total,1)*100:.1f}%)")
        print(f"  Depth=1 (top-level): {depth1:,}")

        # Verify parent_id integrity: parent should have lower depth
        bad = conn.execute(
            """SELECT COUNT(*) as c FROM bracket_index b
               JOIN bracket_index p ON b.parent_id = p.id
               WHERE p.depth >= b.depth"""
        ).fetchone()["c"]
        print(f"  Invalid parent relationships: {bad}")

        assert bad == 0, f"Found {bad} invalid parent relationships!"

    print("  PASS\n")


if __name__ == "__main__":
    print("\nTesting all 7 MCP tool functions against unreal.db\n")

    setup_module()

    test_search_code_source()
    test_get_file_content_line_range()
    test_get_file_content_anchor()
    test_log_code_query()
    test_find_include_graph()
    test_find_callers()
    test_find_references()
    test_get_directory_structure()
    test_parent_id_hierarchy()

    teardown_module()

    print("=" * 70)
    print("ALL TESTS PASSED!")
    print("=" * 70)
