"""Tests for exec_sql_query passthrough."""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from code_explore_by_sql.db import (
    SourceFile,
    connect,
    exec_sql_query,
    initialize_schema,
    log_query,
    record_feedback,
    upsert_source_file,
)


@pytest.fixture
def db(tmp_path):
    conn = connect(tmp_path / "test.db")
    initialize_schema(conn)
    return conn


def test_basic_select(db):
    fid = upsert_source_file(db, SourceFile(
        file_path="Engine/Test.cpp", module_name="Core",
        raw_content="void Foo() {}",
    ))
    db.commit()

    result = exec_sql_query(db, "SELECT * FROM source_files")
    assert len(result["results"]) == 1
    assert result["results"][0]["file_path"] == "Engine/Test.cpp"
    assert result["meta"]["truncated"] is False


def test_rejects_write(db):
    result = exec_sql_query(db, "DROP TABLE source_files")
    assert "error" in result
    assert result["results"] == []


def test_rejects_insert(db):
    result = exec_sql_query(db, "INSERT INTO source_files(file_path, raw_content) VALUES('x','y')")
    assert "error" in result


def test_row_truncation(db):
    for i in range(250):
        upsert_source_file(db, SourceFile(
            file_path=f"File{i}.cpp", module_name="Test",
            raw_content=f"void F{i}() {{}}",
        ))
    db.commit()

    result = exec_sql_query(db, "SELECT * FROM source_files")
    assert len(result["results"]) == 200
    assert result["meta"]["truncated"] is True


def test_with_cte(db):
    upsert_source_file(db, SourceFile(
        file_path="A.cpp", module_name="M", raw_content="int x;"
    ))
    upsert_source_file(db, SourceFile(
        file_path="B.cpp", module_name="M", raw_content="int y;"
    ))
    db.commit()

    result = exec_sql_query(db, """
        WITH cnt AS (SELECT COUNT(*) AS n FROM source_files)
        SELECT n FROM cnt
    """)
    assert result["results"][0]["n"] == 2


def test_history_enrichment_by_file_id(db):
    fid = upsert_source_file(db, SourceFile(
        file_path="Engine/Lumen.cpp", module_name="Renderer",
        raw_content="void FLumenScene::Render() { TraceLumen(); }",
    ))
    db.commit()

    log_query(db, "Lumen", "Lumen", [fid])
    record_feedback(db, "Engine/Lumen.cpp", was_useful=True)

    result = exec_sql_query(
        db,
        "SELECT id AS file_id, file_path FROM source_files",
        expanded_terms=["Lumen"],
    )
    assert len(result["results"]) == 1
    assert "history_score" in result["results"][0]
    assert result["meta"]["history_enriched"] is True


def test_history_enrichment_by_file_path(db):
    fid = upsert_source_file(db, SourceFile(
        file_path="Engine/Nanite.cpp", module_name="Renderer",
        raw_content="void FNaniteScene::Render() {}",
    ))
    db.commit()

    log_query(db, "Nanite", "Nanite", [fid])
    record_feedback(db, "Engine/Nanite.cpp", was_useful=True)

    result = exec_sql_query(
        db,
        "SELECT file_path FROM source_files",
        expanded_terms=["Nanite"],
    )
    assert "history_score" in result["results"][0]
    assert result["meta"]["history_enriched"] is True


def test_history_no_match(db):
    upsert_source_file(db, SourceFile(
        file_path="Foo.cpp", module_name="X", raw_content="int a;"
    ))
    db.commit()

    result = exec_sql_query(
        db,
        "SELECT id AS file_id, file_path FROM source_files",
        expanded_terms=["NonexistentTerm12345"],
    )
    assert len(result["results"]) == 1
    assert "history_score" not in result["results"][0]
    assert result["meta"]["history_enriched"] is False


def test_sql_error(db):
    result = exec_sql_query(db, "SELECT * FROM nonexistent_table")
    assert "error" in result


def test_query_logged(db):
    upsert_source_file(db, SourceFile(
        file_path="X.cpp", module_name="M", raw_content="int x;"
    ))
    db.commit()

    exec_sql_query(db, "SELECT id AS file_id, file_path FROM source_files")

    log = db.execute("SELECT * FROM query_logs").fetchone()
    assert log is not None
    assert "SELECT" in log["query_text"]
