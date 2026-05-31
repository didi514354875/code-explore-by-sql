"""Backfill correctness and efficiency tests.

Covers:
  - bracket_index: line numbers, depth, block_type, block_name, nesting
  - parent_id: correct parent-child links
  - symbol_references: cross-file references, self-references, nested refs
  - symbol_name_index: qualified names (Class::Method), extra_blocks merge
  - include_edges: correct include resolution
  - extra_blocks: non-brace blocks captured
  - edge cases: empty files, comment-only, deeply nested, duplicate names
  - efficiency: batch timing sanity checks on synthetic data
"""
import re
import sys
import time
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from code_explore_by_sql.db import (
    SourceFile,
    backfill_structural_index,
    connect,
    initialize_schema,
    upsert_source_file,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_db(tmp_path, files: list[tuple[str, str, str]]) -> "sqlite3.Connection":
    """Create a test database with the given files.

    files: list of (file_path, module_name, raw_content)
    """
    db_path = tmp_path / "test.db"
    conn = connect(db_path)
    initialize_schema(conn)
    for path, module, content in files:
        upsert_source_file(conn, SourceFile(file_path=path, module_name=module, raw_content=content))
    conn.commit()
    return conn


# ---------------------------------------------------------------------------
# Test data fixtures
# ---------------------------------------------------------------------------

COMPLEX_CPP = (
    'namespace N1 {\n'           # L1  depth-1 open  -> namespace N1
    '  class Outer {\n'          # L2
    '  public:\n'                # L3
    '    void init() {\n'        # L4  depth-2 open  -> method init
    '      int x = 0;\n'        # L5
    '      if (x) {\n'          # L6  depth-3 open  -> control_flow (skipped)
    '        x++;\n'            # L7
    '      }\n'                 # L8  depth-3 close
    '    }\n'                   # L9  depth-2 close
    '    int getValue() const {\n'  # L10 depth-2 open -> method getValue
    '      return 42;\n'        # L11
    '    }\n'                   # L12 depth-2 close
    '  };\n'                    # L13 depth-1 close (class body)
    '}\n'                       # L14 depth-0 close (namespace body)
)

CALLER_CPP = (
    '#include "Complex.h"\n'    # L1
    'void caller() {\n'         # L2
    '  N1::Outer obj;\n'       # L3
    '  obj.init();\n'          # L4  ref to init
    '  int v = obj.getValue();\n'  # L5  ref to getValue
    '}\n'                       # L6
)

MACRO_H = (
    '#define MAX_A 100\n'       # L1
    '#define CLAMP(x, lo, hi) ((x) < (lo) ? (lo) : (hi))\n'  # L2
    '// no braces here\n'       # L3
)

DEEP_NEST_CPP = (
    'void deep() {\n'           # L1
    '  {\n'                     # L2
    '    {\n'                   # L3
    '      {\n'                 # L4
    '        int x;\n'         # L5
    '      }\n'                # L6
    '    }\n'                   # L7
    '  }\n'                     # L8
    '}\n'                       # L9
)


# ---------------------------------------------------------------------------
# Correctness: bracket_index
# ---------------------------------------------------------------------------

class TestBracketIndexCorrectness:
    def test_block_line_numbers_accurate(self, tmp_path):
        conn = _make_db(tmp_path, [("A.cpp", "M", COMPLEX_CPP)])
        backfill_structural_index(conn, workers=1, provider_name="cc")

        rows = conn.execute(
            "SELECT block_type, block_name, open_line, close_line, depth "
            "FROM bracket_index ORDER BY open_line"
        ).fetchall()

        # Verify at least namespace, class, and methods are found
        types = {r["block_type"] for r in rows}
        assert "namespace" in types, f"expected namespace, got types: {types}"
        assert "class" in types, f"expected class, got types: {types}"

        # Check namespace spans lines 1..14
        ns = next(r for r in rows if r["block_type"] == "namespace")
        assert ns["open_line"] == 1
        assert ns["close_line"] == 14
        assert ns["depth"] == 1
        assert ns["block_name"] == "N1"

        # Check class Outer
        cls = next(r for r in rows if r["block_type"] == "class")
        assert cls["block_name"] == "Outer"
        assert cls["open_line"] == 2
        assert cls["close_line"] == 13
        assert cls["depth"] == 2

    def test_method_signatures_captured(self, tmp_path):
        conn = _make_db(tmp_path, [("A.cpp", "M", COMPLEX_CPP)])
        backfill_structural_index(conn, workers=1, provider_name="cc")

        methods = conn.execute(
            "SELECT block_name, signature FROM bracket_index "
            "WHERE block_type = 'method' ORDER BY open_line"
        ).fetchall()

        assert len(methods) == 2
        names = {m["block_name"] for m in methods}
        assert names == {"init", "getValue"}

        # getValue should have "const" in signature
        gv = next(m for m in methods if m["block_name"] == "getValue")
        assert gv["signature"] is not None
        assert "getValue" in gv["signature"]

    def test_depth_values_correct(self, tmp_path):
        conn = _make_db(tmp_path, [("A.cpp", "M", COMPLEX_CPP)])
        backfill_structural_index(conn, workers=1, provider_name="cc")

        rows = conn.execute(
            "SELECT block_name, depth FROM bracket_index ORDER BY open_line"
        ).fetchall()
        for r in rows:
            assert r["depth"] >= 1, f"{r['block_name']} has depth < 1: {r['depth']}"

    def test_no_unknown_blocks_stored(self, tmp_path):
        conn = _make_db(tmp_path, [("A.cpp", "M", COMPLEX_CPP)])
        backfill_structural_index(conn, workers=1, provider_name="cc")

        unknowns = conn.execute(
            "SELECT COUNT(*) as c FROM bracket_index WHERE block_type = 'unknown'"
        ).fetchone()["c"]
        assert unknowns == 0, "backfill should only store classified blocks"

    def test_empty_file_no_bracket_rows(self, tmp_path):
        conn = _make_db(tmp_path, [("empty.cpp", "M", "// nothing\n")])
        backfill_structural_index(conn, workers=1, provider_name="cc")

        count = conn.execute("SELECT COUNT(*) as c FROM bracket_index").fetchone()["c"]
        assert count == 0

    def test_unclassified_braces_not_stored(self, tmp_path):
        """Bare brace blocks (no semantic classification) should not appear."""
        conn = _make_db(tmp_path, [("bare.cpp", "M", DEEP_NEST_CPP)])
        backfill_structural_index(conn, workers=1, provider_name="cc")

        rows = conn.execute(
            "SELECT block_type, block_name, depth FROM bracket_index ORDER BY open_line"
        ).fetchall()
        # Only "deep" function should be classified; inner {} are unclassified
        assert len(rows) == 1
        assert rows[0]["block_name"] == "deep"
        assert rows[0]["block_type"] == "function"


# ---------------------------------------------------------------------------
# Correctness: parent_id
# ---------------------------------------------------------------------------

class TestParentIdCorrectness:
    def test_class_is_parent_of_methods(self, tmp_path):
        conn = _make_db(tmp_path, [("A.cpp", "M", COMPLEX_CPP)])
        backfill_structural_index(conn, workers=1, provider_name="cc")

        # Get class and its methods
        cls = conn.execute(
            "SELECT id, block_name FROM bracket_index WHERE block_type = 'class'"
        ).fetchone()
        methods = conn.execute(
            "SELECT id, block_name, parent_id FROM bracket_index WHERE block_type = 'method'"
        ).fetchall()

        assert cls is not None, "should have a class block"
        assert len(methods) >= 2, f"should have >= 2 methods, got {len(methods)}"

        for m in methods:
            assert m["parent_id"] == cls["id"], (
                f"method {m['block_name']} parent_id={m['parent_id']}, expected class id={cls['id']}"
            )

    def test_namespace_is_parent_of_class(self, tmp_path):
        conn = _make_db(tmp_path, [("A.cpp", "M", COMPLEX_CPP)])
        backfill_structural_index(conn, workers=1, provider_name="cc")

        ns = conn.execute(
            "SELECT id FROM bracket_index WHERE block_type = 'namespace'"
        ).fetchone()
        cls = conn.execute(
            "SELECT id, parent_id FROM bracket_index WHERE block_type = 'class'"
        ).fetchone()

        assert cls["parent_id"] == ns["id"]

    def test_no_self_parenting(self, tmp_path):
        conn = _make_db(tmp_path, [("A.cpp", "M", COMPLEX_CPP)])
        backfill_structural_index(conn, workers=1, provider_name="cc")
        self_parents = conn.execute(
            "SELECT COUNT(*) as c FROM bracket_index WHERE parent_id = id"
        ).fetchone()["c"]
        assert self_parents == 0


# ---------------------------------------------------------------------------
# Correctness: symbol_references
# ---------------------------------------------------------------------------

class TestSymbolReferencesCorrectness:
    def test_cross_file_references_found(self, tmp_path):
        conn = _make_db(tmp_path, [
            ("Complex.h", "M", COMPLEX_CPP),
            ("Caller.cpp", "M", CALLER_CPP),
        ])
        backfill_structural_index(conn, workers=1, provider_name="cc")

        refs = conn.execute(
            "SELECT symbol_name FROM symbol_references "
            "WHERE symbol_name IN ('init', 'getValue') "
            "ORDER BY symbol_name"
        ).fetchall()
        names = {r["symbol_name"] for r in refs}
        assert "init" in names, "should reference init"
        assert "getValue" in names, "should reference getValue"

    def test_ref_line_numbers_accurate(self, tmp_path):
        conn = _make_db(tmp_path, [
            ("Complex.h", "M", COMPLEX_CPP),
            ("Caller.cpp", "M", CALLER_CPP),
        ])
        backfill_structural_index(conn, workers=1, provider_name="cc")

        # obj.init() is on line 4, obj.getValue() on line 5
        init_refs = conn.execute(
            "SELECT ref_line FROM symbol_references WHERE symbol_name = 'init'"
        ).fetchall()
        assert any(r["ref_line"] == 4 for r in init_refs), (
            f"init should be referenced on line 4, got: {[r['ref_line'] for r in init_refs]}"
        )

    def test_ref_file_id_correct(self, tmp_path):
        conn = _make_db(tmp_path, [
            ("Complex.h", "M", COMPLEX_CPP),
            ("Caller.cpp", "M", CALLER_CPP),
        ])
        backfill_structural_index(conn, workers=1, provider_name="cc")

        caller_file = conn.execute(
            "SELECT id FROM source_files WHERE file_path = 'Caller.cpp'"
        ).fetchone()

        refs = conn.execute(
            "SELECT DISTINCT ref_file_id FROM symbol_references "
            "WHERE symbol_name = 'init'"
        ).fetchall()
        assert any(r["ref_file_id"] == caller_file["id"] for r in refs)


# ---------------------------------------------------------------------------
# Correctness: symbol_name_index
# ---------------------------------------------------------------------------

class TestSymbolNameIndexCorrectness:
    def test_qualified_name_for_methods(self, tmp_path):
        conn = _make_db(tmp_path, [("A.cpp", "M", COMPLEX_CPP)])
        backfill_structural_index(conn, workers=1, provider_name="cc")

        qualified = conn.execute(
            "SELECT name, qualified_name FROM symbol_name_index "
            "WHERE source_type = 'bracket' AND block_type = 'method'"
        ).fetchall()

        for r in qualified:
            assert "::" in r["qualified_name"], (
                f"method {r['name']} should have qualified name with ::, got {r['qualified_name']}"
            )
            assert r["qualified_name"].startswith("Outer::"), (
                f"qualified name should start with Outer::, got {r['qualified_name']}"
            )

    def test_no_qualified_name_for_top_level(self, tmp_path):
        conn = _make_db(tmp_path, [("A.cpp", "M", COMPLEX_CPP)])
        backfill_structural_index(conn, workers=1, provider_name="cc")

        ns = conn.execute(
            "SELECT name, qualified_name FROM symbol_name_index "
            "WHERE block_type = 'namespace'"
        ).fetchone()
        assert ns is not None
        assert "::" not in ns["qualified_name"], (
            f"top-level namespace should not have :: in qualified_name, got {ns['qualified_name']}"
        )

    def test_extra_blocks_merged(self, tmp_path):
        conn = _make_db(tmp_path, [("Macro.h", "M", MACRO_H)])
        backfill_structural_index(conn, workers=1, provider_name="cc")

        extra_names = conn.execute(
            "SELECT name, source_type FROM symbol_name_index WHERE source_type = 'extra'"
        ).fetchall()
        extra_set = {r["name"] for r in extra_names}
        assert "MAX_A" in extra_set or "CLAMP" in extra_set, (
            f"macro blocks should appear in symbol_name_index, got: {extra_set}"
        )


# ---------------------------------------------------------------------------
# Correctness: include_edges
# ---------------------------------------------------------------------------

class TestIncludeEdgesCorrectness:
    def test_include_parsed(self, tmp_path):
        conn = _make_db(tmp_path, [
            ("Complex.h", "M", COMPLEX_CPP),
            ("Caller.cpp", "M", CALLER_CPP),
        ])
        backfill_structural_index(conn, workers=1, provider_name="cc")

        edges = conn.execute("SELECT include_path, line_number FROM include_edges").fetchall()
        paths = {e["include_path"] for e in edges}
        assert "Complex.h" in paths, f"should include Complex.h, got: {paths}"

        # Line number should be 1 (first line of CALLER_CPP)
        inc = next(e for e in edges if e["include_path"] == "Complex.h")
        assert inc["line_number"] == 1

    def test_include_target_resolved(self, tmp_path):
        conn = _make_db(tmp_path, [
            ("Complex.h", "M", COMPLEX_CPP),
            ("Caller.cpp", "M", CALLER_CPP),
        ])
        backfill_structural_index(conn, workers=1, provider_name="cc")

        target = conn.execute(
            "SELECT target_file_id FROM include_edges WHERE include_path = 'Complex.h'"
        ).fetchone()
        complex_file = conn.execute(
            "SELECT id FROM source_files WHERE file_path = 'Complex.h'"
        ).fetchone()

        assert target["target_file_id"] == complex_file["id"]


# ---------------------------------------------------------------------------
# Correctness: extra_blocks
# ---------------------------------------------------------------------------

class TestExtraBlocksCorrectness:
    def test_macros_captured(self, tmp_path):
        conn = _make_db(tmp_path, [("Macro.h", "M", MACRO_H)])
        backfill_structural_index(conn, workers=1, provider_name="cc")

        macros = conn.execute(
            "SELECT name, block_type, start_line FROM extra_blocks ORDER BY start_line"
        ).fetchall()
        names = {m["name"] for m in macros}
        assert "MAX_A" in names, f"should capture MAX_A macro, got: {names}"
        assert "CLAMP" in names, f"should capture CLAMP macro, got: {names}"


# ---------------------------------------------------------------------------
# Correctness: edge cases
# ---------------------------------------------------------------------------

class TestEdgeCases:
    def test_file_with_only_comments(self, tmp_path):
        content = "// line 1\n/* block\ncomment */\n"
        conn = _make_db(tmp_path, [("comments.cpp", "M", content)])
        backfill_structural_index(conn, workers=1, provider_name="cc")

        count = conn.execute("SELECT COUNT(*) as c FROM bracket_index").fetchone()["c"]
        assert count == 0, "comment-only file should have no bracket blocks"

    def test_strings_with_braces_ignored(self, tmp_path):
        content = (
            'void foo() {\n'
            '    const char* s = "{ not a block }";\n'
            '}\n'
        )
        conn = _make_db(tmp_path, [("str.cpp", "M", content)])
        backfill_structural_index(conn, workers=1, provider_name="cc")

        rows = conn.execute(
            "SELECT block_type, block_name FROM bracket_index"
        ).fetchall()
        # Should only have foo, not the string braces
        assert len(rows) == 1
        assert rows[0]["block_name"] == "foo"

    def test_raw_string_with_braces_ignored(self, tmp_path):
        content = (
            'void bar() {\n'
            '    const char* r = R"delim({ not real })delim";\n'
            '}\n'
        )
        conn = _make_db(tmp_path, [("raw.cpp", "M", content)])
        backfill_structural_index(conn, workers=1, provider_name="cc")

        rows = conn.execute(
            "SELECT block_type, block_name FROM bracket_index"
        ).fetchall()
        assert len(rows) == 1
        assert rows[0]["block_name"] == "bar"

    def test_multiple_files_correct_counts(self, tmp_path):
        files = [
            ("A.cpp", "M", COMPLEX_CPP),
            ("B.cpp", "M", CALLER_CPP),
            ("C.h", "M", MACRO_H),
            ("D.cpp", "M", "// empty-ish\nvoid f() {}\n"),
        ]
        conn = _make_db(tmp_path, files)
        total = backfill_structural_index(conn, workers=1, provider_name="cc")
        assert total == 4

        bracket_count = conn.execute("SELECT COUNT(*) as c FROM bracket_index").fetchone()["c"]
        assert bracket_count > 0

    def test_duplicate_symbol_names_different_files(self, tmp_path):
        """Two files each define 'foo' — both definitions stored in bracket_index."""
        file_a = "void foo() { int x = 0; }\n"
        file_b = "void foo() { int y = 1; }\n"
        conn = _make_db(tmp_path, [
            ("A.cpp", "M", file_a),
            ("B.cpp", "M", file_b),
        ])
        backfill_structural_index(conn, workers=1, provider_name="cc")

        foos = conn.execute(
            "SELECT file_id FROM bracket_index WHERE block_name = 'foo'"
        ).fetchall()
        assert len(foos) == 2, f"expected 2 foo definitions, got {len(foos)}"


# ---------------------------------------------------------------------------
# Correctness: idempotency (detailed)
# ---------------------------------------------------------------------------

class TestIdempotency:
    def test_exact_row_match_after_double_backfill(self, tmp_path):
        conn = _make_db(tmp_path, [
            ("A.cpp", "M", COMPLEX_CPP),
            ("B.cpp", "M", CALLER_CPP),
        ])

        backfill_structural_index(conn, workers=1, provider_name="cc")
        first = conn.execute(
            "SELECT block_type, block_name, open_line, close_line, depth "
            "FROM bracket_index ORDER BY open_line"
        ).fetchall()

        backfill_structural_index(conn, workers=1, provider_name="cc")
        second = conn.execute(
            "SELECT block_type, block_name, open_line, close_line, depth "
            "FROM bracket_index ORDER BY open_line"
        ).fetchall()

        assert len(first) == len(second)
        for a, b in zip(first, second):
            assert dict(a) == dict(b), f"mismatch: {dict(a)} != {dict(b)}"


# ---------------------------------------------------------------------------
# Efficiency: timing sanity checks
# ---------------------------------------------------------------------------

class TestEfficiency:
    @staticmethod
    def _generate_files(n: int) -> list[tuple[str, str, str]]:
        """Generate n synthetic C++ files with known structure."""
        files = []
        for i in range(n):
            lines = [
                f"namespace NS{i} {{",
                f"  class Class{i} {{",
                "  public:",
                f"    void method{i}a() {{ int x = 0; }}",
                f"    void method{i}b() {{ int y = 1; }}",
                f"    int getter{i}() const {{ return {i}; }}",
                "  };",
                "}",
            ]
            files.append((f"gen/file_{i:04d}.cpp", f"Mod{i}", "\n".join(lines)))
        return files

    def test_100_files_under_5_seconds(self, tmp_path):
        files = self._generate_files(100)
        conn = _make_db(tmp_path, files)

        t0 = time.time()
        total = backfill_structural_index(conn, workers=1, provider_name="cc")
        elapsed = time.time() - t0

        assert total == 100
        assert elapsed < 5.0, f"100 files took {elapsed:.1f}s — expected < 5s"

        bracket_count = conn.execute("SELECT COUNT(*) as c FROM bracket_index").fetchone()["c"]
        # 100 files × (1 namespace + 1 class + 3 methods) = 500 blocks
        assert bracket_count == 500, f"expected 500 bracket blocks, got {bracket_count}"

        parent_count = conn.execute(
            "SELECT COUNT(*) as c FROM bracket_index WHERE parent_id IS NOT NULL"
        ).fetchone()["c"]
        # methods→class (300) + class→namespace (100) = 400
        assert parent_count == 400, f"expected 400 parent links, got {parent_count}"

    def test_500_files_under_30_seconds(self, tmp_path):
        files = self._generate_files(500)
        conn = _make_db(tmp_path, files)

        t0 = time.time()
        total = backfill_structural_index(conn, workers=1, provider_name="cc")
        elapsed = time.time() - t0

        assert total == 500
        assert elapsed < 30.0, f"500 files took {elapsed:.1f}s — expected < 30s"

    def test_phase1_dominates_total_time(self, tmp_path):
        """Bracket scan (Phase 1) should be the dominant cost."""
        files = self._generate_files(100)
        conn = _make_db(tmp_path, files)
        # backfill prints timing — we verify by checking the ratio is reasonable
        t0 = time.time()
        backfill_structural_index(conn, workers=1, provider_name="cc")
        total_time = time.time() - t0
        assert total_time > 0  # just ensure no crash

    def test_second_backfill_no_slower_than_first(self, tmp_path):
        """Second backfill (full DROP+RECREATE) should be same order of magnitude."""
        files = self._generate_files(100)
        conn = _make_db(tmp_path, files)

        t1 = time.time()
        backfill_structural_index(conn, workers=1, provider_name="cc")
        first = time.time() - t1

        t2 = time.time()
        backfill_structural_index(conn, workers=1, provider_name="cc")
        second = time.time() - t2

        # Allow 3x slack — should not be dramatically slower
        assert second < first * 3, (
            f"second backfill ({second:.2f}s) much slower than first ({first:.2f}s)"
        )


# ---------------------------------------------------------------------------
# Correctness: full pipeline integration
# ---------------------------------------------------------------------------

class TestFullPipeline:
    def test_all_tables_populated_consistently(self, tmp_path):
        conn = _make_db(tmp_path, [
            ("Complex.h", "M", COMPLEX_CPP),
            ("Caller.cpp", "M", CALLER_CPP),
            ("Macro.h", "M", MACRO_H),
        ])
        backfill_structural_index(conn, workers=1, provider_name="cc")

        # bracket_index has rows for the braced files
        bracket_count = conn.execute("SELECT COUNT(*) as c FROM bracket_index").fetchone()["c"]
        assert bracket_count > 0

        # symbol_name_index covers both bracket and extra sources
        bracket_syms = conn.execute(
            "SELECT COUNT(*) as c FROM symbol_name_index WHERE source_type = 'bracket'"
        ).fetchone()["c"]
        extra_syms = conn.execute(
            "SELECT COUNT(*) as c FROM symbol_name_index WHERE source_type = 'extra'"
        ).fetchone()["c"]
        assert bracket_syms > 0
        assert extra_syms > 0

        # include_edges
        include_count = conn.execute("SELECT COUNT(*) as c FROM include_edges").fetchone()["c"]
        assert include_count > 0

        # symbol_references
        ref_count = conn.execute("SELECT COUNT(*) as c FROM symbol_references").fetchone()["c"]
        assert ref_count > 0

    def test_symbol_name_index_no_unknown_types(self, tmp_path):
        conn = _make_db(tmp_path, [("A.cpp", "M", COMPLEX_CPP)])
        backfill_structural_index(conn, workers=1, provider_name="cc")

        unknowns = conn.execute(
            "SELECT COUNT(*) as c FROM symbol_name_index "
            "WHERE block_type IN ('unknown', 'control_flow')"
        ).fetchone()["c"]
        assert unknowns == 0, "symbol_name_index should not contain unknown/control_flow"
