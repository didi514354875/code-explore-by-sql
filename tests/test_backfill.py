"""Tests for the backfill_structural_index process."""
import sqlite3
import sys
from io import StringIO
from pathlib import Path
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from code_explore_by_sql.db import (
    SourceFile,
    backfill_structural_index,
    connect,
    initialize_schema,
    upsert_source_file,
)


@pytest.fixture
def test_db(tmp_path):
    """Create a test database with sample source files."""
    db_path = tmp_path / "test_backfill.db"
    conn = connect(db_path)
    initialize_schema(conn)

    # Insert a C++ file with nested structures
    upsert_source_file(
        conn,
        SourceFile(
            file_path="Engine/Source/Runtime/Core/TestClass.cpp",
            module_name="Core",
            raw_content=(
                "#include \"TestClass.h\"\n"
                "namespace MyNamespace {\n"
                "class MyClass {\n"
                "public:\n"
                "    void MyMethod() {\n"
                "        int x = 0;\n"
                "    }\n"
                "    int GetValue() {\n"
                "        return 42;\n"
                "    }\n"
                "};\n"
                "} // namespace MyNamespace\n"
            ),
        ),
    )

    # Insert another file that references the first
    upsert_source_file(
        conn,
        SourceFile(
            file_path="Engine/Source/Runtime/Core/TestUser.cpp",
            module_name="Core",
            raw_content=(
                "#include \"TestClass.h\"\n"
                "void UseMyClass() {\n"
                "    MyClass obj;\n"
                "    obj.MyMethod();\n"
                "    int v = obj.GetValue();\n"
                "}\n"
            ),
        ),
    )

    # Insert a simple file with no braces
    upsert_source_file(
        conn,
        SourceFile(
            file_path="Engine/Source/Runtime/Core/Simple.h",
            module_name="Core",
            raw_content="// Just a comment file\n#define MAX_VALUE 100\n",
        ),
    )

    conn.commit()
    return conn


def test_backfill_runs_successfully(test_db):
    """Test that backfill completes without errors."""
    total = backfill_structural_index(test_db, workers=1, provider_name="cc")
    assert total == 3  # 3 files


def test_backfill_creates_bracket_index(test_db):
    """Test that backfill populates the bracket_index table."""
    backfill_structural_index(test_db, workers=1, provider_name="cc")

    count = test_db.execute("SELECT COUNT(*) as c FROM bracket_index").fetchone()["c"]
    assert count > 0, "bracket_index should have entries"

    # Check that we have the expected block types
    rows = test_db.execute(
        "SELECT block_type, COUNT(*) as cnt FROM bracket_index GROUP BY block_type"
    ).fetchall()
    types = {r["block_type"] for r in rows}
    assert "class" in types or "namespace" in types


def test_backfill_creates_parent_links(test_db):
    """Test that backfill creates parent-child relationships."""
    backfill_structural_index(test_db, workers=1, provider_name="cc")

    parent_count = test_db.execute(
        "SELECT COUNT(*) as c FROM bracket_index WHERE parent_id IS NOT NULL"
    ).fetchone()["c"]
    assert parent_count > 0, "Should have parent-child links"


def test_backfill_creates_symbol_name_index(test_db):
    """Test that backfill populates the symbol_name_index table."""
    backfill_structural_index(test_db, workers=1, provider_name="cc")

    count = test_db.execute("SELECT COUNT(*) as c FROM symbol_name_index").fetchone()["c"]
    assert count > 0, "symbol_name_index should have entries"

    # Check for our known symbols
    names = test_db.execute(
        "SELECT name FROM symbol_name_index"
    ).fetchall()
    name_set = {r["name"] for r in names}
    assert "MyClass" in name_set or "MyMethod" in name_set


def test_backfill_progress_output(test_db, capsys):
    """Test that backfill prints progress information."""
    backfill_structural_index(test_db, workers=1, provider_name="cc")
    captured = capsys.readouterr()

    output = captured.out
    # Check key progress messages
    assert "backfill starting:" in output
    assert "backfill complete:" in output
    assert "bracket scan done:" in output
    assert "parent_id done:" in output
    assert "symbol_references done:" in output
    assert "symbol_name_index done:" in output


def test_backfill_parent_id_batch_output(test_db, capsys):
    """Test that parent_id computation shows batch progress."""
    backfill_structural_index(test_db, workers=1, provider_name="cc")
    captured = capsys.readouterr()

    output = captured.out
    assert "parent_id:" in output
    assert "parent_id batch:" in output or "parent_id done:" in output


def test_backfill_symbol_name_index_details(test_db, capsys):
    """Test that symbol_name_index building shows bracket/extra breakdown."""
    backfill_structural_index(test_db, workers=1, provider_name="cc")
    captured = capsys.readouterr()

    output = captured.out
    assert "from bracket_index" in output
    assert "from extra_blocks" in output


def test_backfill_idempotent(test_db):
    """Test that running backfill twice works (drops and recreates tables)."""
    backfill_structural_index(test_db, workers=1, provider_name="cc")
    first_count = test_db.execute("SELECT COUNT(*) as c FROM bracket_index").fetchone()["c"]

    backfill_structural_index(test_db, workers=1, provider_name="cc")
    second_count = test_db.execute("SELECT COUNT(*) as c FROM bracket_index").fetchone()["c"]

    assert first_count == second_count, "Backfill should be idempotent"


def test_backfill_empty_database(tmp_path):
    """Test backfill with no source files."""
    db_path = tmp_path / "empty.db"
    conn = connect(db_path)
    initialize_schema(conn)
    conn.commit()

    total = backfill_structural_index(conn, workers=1, provider_name="cc")
    assert total == 0


def test_backfill_creates_all_tables(test_db):
    """Test that backfill creates all required tables."""
    backfill_structural_index(test_db, workers=1, provider_name="cc")

    tables = test_db.execute(
        "SELECT name FROM sqlite_master WHERE type='table'"
    ).fetchall()
    table_names = {r["name"] for r in tables}

    expected = {
        "source_files",
        "bracket_index",
        "include_edges",
        "symbol_references",
        "extra_blocks",
        "member_types",
        "symbol_name_index",
    }
    assert expected.issubset(table_names), f"Missing tables: {expected - table_names}"
