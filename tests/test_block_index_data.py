"""Integration tests for new block index features: parent_id, symbol_references.

Rebuilds a small sample of files, generates references, and validates the data.
"""
from __future__ import annotations

import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from code_explore_by_sql.db import connect, initialize_schema, rebuild_structural_index
from code_explore_by_sql.sniffers.reference_tracker import (
    ReferenceTrackerConfig,
    track_references_for_file,
    enrich_ref_block_ids,
    prepare_bracket_arrays,
)
from code_explore_by_sql.providers import get_provider

DB_PATH = os.path.join(os.path.dirname(__file__), "..", "unreal.db")

passed = 0
failed = 0


def check(name: str, condition: bool, detail: str = "") -> None:
    global passed, failed
    status = "[PASS]" if condition else "[FAIL]"
    msg = f"  {status} {name}"
    if detail and not condition:
        msg += f" — {detail}"
    print(msg)
    if condition:
        passed += 1
    else:
        failed += 1


# ============================================================================
# Step 1: Rebuild a sample of files with parent_id
# ============================================================================
def test_rebuild_sample():
    """Rebuild structural index for 10 sample files and verify parent_id."""
    print("[Test B1] Rebuild sample files with parent_id")

    conn = connect(DB_PATH)
    initialize_schema(conn)

    # Pick 10 files that have existing bracket data
    sample = conn.execute("""
        SELECT id, file_path, raw_content
        FROM source_files
        WHERE id IN (
            SELECT file_id FROM bracket_index
            GROUP BY file_id
            HAVING COUNT(*) > 5
            LIMIT 10
        )
        ORDER BY id
    """).fetchall()

    check("got 10 sample files", len(sample) == 10, f"got {len(sample)}")

    for row in sample:
        rebuild_structural_index(conn, row["id"], row["raw_content"])
        print(f"  rebuilt: {row['file_path']}")

    conn.commit()
    conn.close()
    return sample


def test_parent_id_populated(sample_files):
    """Verify parent_id is populated for rebuilt files."""
    print("[Test B2] parent_id populated")

    conn = connect(DB_PATH)

    for row in sample_files:
        file_id = row["id"]

        total = conn.execute(
            "SELECT COUNT(*) as c FROM bracket_index WHERE file_id = ?",
            (file_id,),
        ).fetchone()["c"]

        with_parent = conn.execute(
            "SELECT COUNT(*) as c FROM bracket_index WHERE file_id = ? AND parent_id IS NOT NULL",
            (file_id,),
        ).fetchone()["c"]

        root = conn.execute(
            "SELECT COUNT(*) as c FROM bracket_index WHERE file_id = ? AND depth = 1",
            (file_id,),
        ).fetchone()["c"]

        check(
            f"parent_id set for {row['file_path'][:60]}",
            with_parent == total - root,
            f"total={total}, with_parent={with_parent}, roots={root}"
        )

    conn.close()


def test_parent_id_hierarchy(sample_files):
    """Verify parent_id forms a valid tree (no cycles, parent encloses child)."""
    print("[Test B3] parent_id hierarchy validity")

    conn = connect(DB_PATH)

    for row in sample_files[:3]:  # Deep-check first 3
        file_id = row["id"]

        blocks = conn.execute("""
            SELECT id, open_line, close_line, depth, parent_id
            FROM bracket_index WHERE file_id = ?
            ORDER BY open_line
        """, (file_id,)).fetchall()

        id_map = {b["id"]: b for b in blocks}

        for b in blocks:
            if b["parent_id"] is None:
                continue

            parent = id_map.get(b["parent_id"])
            if parent is None:
                check(f"parent exists for block in {row['file_path'][:40]}", False,
                      f"block {b['id']} references missing parent {b['parent_id']}")
                continue

            # Parent must enclose child
            encloses = parent["open_line"] <= b["open_line"] and parent["close_line"] >= b["close_line"]
            check(
                f"parent encloses child in {row['file_path'][:40]}",
                encloses,
                f"parent[{parent['open_line']}-{parent['close_line']}] child[{b['open_line']}-{b['close_line']}]"
            )

            # Parent depth must be one less
            depth_ok = parent["depth"] == b["depth"] - 1
            check(
                f"parent depth is child-1 in {row['file_path'][:40]}",
                depth_ok,
                f"parent_depth={parent['depth']} child_depth={b['depth']}"
            )

    conn.close()


# ============================================================================
# Step 2: Generate symbol references
# ============================================================================
def test_generate_references(sample_files):
    """Generate symbol_references for sample files."""
    print("[Test B4] Generate symbol references")

    conn = connect(DB_PATH)

    # Clear old references for sample files before inserting new ones
    sample_ids = [row["id"] for row in sample_files]
    placeholders = ",".join("?" * len(sample_files))
    conn.execute(f"""
        DELETE FROM symbol_references WHERE ref_file_id IN ({placeholders})
    """, sample_ids)
    conn.commit()

    # Collect all named symbols from sample files
    all_symbols: dict[str, list[dict]] = {}
    for row in sample_files:
        file_id = row["id"]
        symbols = conn.execute("""
            SELECT id as block_id, block_type as type, block_name as name,
                   open_line, close_line, file_id
            FROM bracket_index
            WHERE file_id = ? AND block_name IS NOT NULL AND block_type != 'unknown'
        """, (file_id,)).fetchall()
        for s in symbols:
            d = dict(s)
            all_symbols.setdefault(d["name"], []).append(d)

    total_symbols = sum(len(v) for v in all_symbols.values())
    check("found named symbols", total_symbols > 0, f"found {total_symbols}")

    # Track references for each sample file
    provider = get_provider("unreal")
    skip_re = provider.skip_line_re()

    total_refs = 0
    for row in sample_files:
        file_id = row["id"]
        lines = row["raw_content"].split("\n")

        refs = track_references_for_file(lines, file_id, all_symbols,
                                         skip_line_re=skip_re)

        # Get bracket data for enrichment
        bracket_rows = conn.execute("""
            SELECT id, open_line, close_line, depth
            FROM bracket_index WHERE file_id = ? ORDER BY open_line
        """, (file_id,)).fetchall()
        bracket_data = [dict(b) for b in bracket_rows]
        bracket_arrays = prepare_bracket_arrays(bracket_data)

        enriched = enrich_ref_block_ids(refs, bracket_arrays)

        # Insert into DB
        for ref in enriched:
            conn.execute("""
                INSERT INTO symbol_references
                    (symbol_name, symbol_type, symbol_file_id, ref_file_id, ref_block_id, ref_line)
                VALUES (?, ?, ?, ?, ?, ?)
            """, (ref[0], ref[1], ref[2], ref[3], ref[4], ref[5]))

        total_refs += len(enriched)
        print(f"  {row['file_path'][:60]}: {len(enriched)} refs")

    conn.commit()

    check("generated references", total_refs > 0, f"total={total_refs}")

    # Verify DB count
    db_count = conn.execute("SELECT COUNT(*) as c FROM symbol_references").fetchone()["c"]
    check("DB count matches", db_count == total_refs, f"db={db_count} expected={total_refs}")

    # Check enrichment rate
    with_block = conn.execute(
        "SELECT COUNT(*) as c FROM symbol_references WHERE ref_block_id IS NOT NULL"
    ).fetchone()["c"]
    if total_refs > 0:
        pct = with_block / total_refs * 100
        # UE code has many macro/preprocessor regions without enclosing blocks,
        # so 30% is a reasonable minimum enrichment rate
        check("enrichment rate >= 30%", pct >= 30, f"{pct:.0f}% ({with_block}/{total_refs})")

    conn.close()


def test_reference_queries(sample_files):
    """Test querying symbol_references."""
    print("[Test B5] Reference query validation")

    conn = connect(DB_PATH)

    # Get a symbol that has references
    sample_ids = [row["id"] for row in sample_files]
    symbols_with_refs = conn.execute("""
        SELECT DISTINCT sr.symbol_name, sr.symbol_type, sr.symbol_file_id
        FROM symbol_references sr
        WHERE sr.ref_file_id IN ({})
        AND sr.ref_file_id != sr.symbol_file_id
        LIMIT 5
    """.format(",".join("?" * len(sample_ids))), sample_ids).fetchall()

    for sym in symbols_with_refs:
        name = sym["symbol_name"]
        if not name or len(name) < 3:
            continue

        # Count cross-file references
        cross_refs = conn.execute("""
            SELECT sr.ref_file_id, sf.file_path, COUNT(*) as cnt
            FROM symbol_references sr
            JOIN source_files sf ON sf.id = sr.ref_file_id
            WHERE sr.symbol_name = ? AND sr.symbol_file_id = ?
            AND sr.ref_file_id != sr.symbol_file_id
            GROUP BY sr.ref_file_id
            ORDER BY cnt DESC
            LIMIT 5
        """, (name, sym["symbol_file_id"])).fetchall()

        check(
            f"cross-file refs for {name}",
            len(cross_refs) > 0,
            f"found {len(cross_refs)} files"
        )

    # Test: references with block context
    refs_with_block = conn.execute("""
        SELECT sr.symbol_name, sr.ref_line, bi.block_type, bi.block_name
        FROM symbol_references sr
        JOIN bracket_index bi ON sr.ref_block_id = bi.id
        WHERE sr.ref_file_id IN ({})
        LIMIT 10
    """.format(",".join("?" * len(sample_ids))), sample_ids).fetchall()

    check("refs have block context", len(refs_with_block) > 0,
          f"found {len(refs_with_block)} refs with block context")

    conn.close()


# ============================================================================
# Step 3: Test block depth distribution
# ============================================================================
def test_depth_distribution(sample_files):
    """Check block depth distribution and parent_id consistency."""
    print("[Test B6] Depth distribution")

    conn = connect(DB_PATH)

    for row in sample_files[:3]:
        file_id = row["id"]

        depth_counts = conn.execute("""
            SELECT depth, COUNT(*) as cnt
            FROM bracket_index WHERE file_id = ?
            GROUP BY depth ORDER BY depth
        """, (file_id,)).fetchall()

        depths = {r["depth"]: r["cnt"] for r in depth_counts}
        print(f"  {row['file_path'][:60]}: depth dist = {depths}")

        # Depth 1 blocks should all have parent_id = NULL
        root_null = conn.execute("""
            SELECT COUNT(*) as c FROM bracket_index
            WHERE file_id = ? AND depth = 1 AND parent_id IS NULL
        """, (file_id,)).fetchone()["c"]
        depth1_total = depths.get(1, 0)

        check(f"all depth-1 blocks are roots in {row['file_path'][:40]}",
              root_null == depth1_total, f"null_roots={root_null} depth1={depth1_total}")

        # Depth 2+ blocks should all have parent_id set
        non_root_with_parent = conn.execute("""
            SELECT COUNT(*) as c FROM bracket_index
            WHERE file_id = ? AND depth > 1 AND parent_id IS NOT NULL
        """, (file_id,)).fetchone()["c"]
        depth2plus = sum(v for k, v in depths.items() if k > 1)

        check(f"all depth-2+ blocks have parent in {row['file_path'][:40]}",
              non_root_with_parent == depth2plus,
              f"with_parent={non_root_with_parent} depth2plus={depth2plus}")

    conn.close()


if __name__ == "__main__":
    print("=" * 60)
    print("BLOCK INDEX DATA INTEGRATION TESTS")
    print(f"Database: {DB_PATH}")
    print("=" * 60)

    sample_files = test_rebuild_sample()
    test_parent_id_populated(sample_files)
    test_parent_id_hierarchy(sample_files)
    test_generate_references(sample_files)
    test_reference_queries(sample_files)
    test_depth_distribution(sample_files)

    print("=" * 60)
    print(f"RESULTS: {passed}/{passed+failed} passed, {failed} failed")
    print("=" * 60)
    sys.exit(1 if failed else 0)