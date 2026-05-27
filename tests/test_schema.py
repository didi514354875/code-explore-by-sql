from unreal_source_mcp.db import (
    SOURCE_EXTENSIONS,
    SourceFile,
    connect,
    initialize_schema,
    log_query,
    prune_stale_data,
    record_feedback,
    search_source,
    search_source_raw,
    search_source_with_feedback,
    upsert_source_file,
)


def test_schema_indexes_and_searches_source(tmp_path):
    db_path = tmp_path / "source.db"
    conn = connect(db_path)
    initialize_schema(conn)
    upsert_source_file(
        conn,
        SourceFile(
            file_path="Engine/Source/Runtime/Core/Test.cpp",
            module_name="Core",
            raw_content="void FThing::Run() { UE_LOG(LogTemp, Warning, TEXT(\"hello\")); }",
        ),
    )
    conn.commit()

    rows = search_source(conn, "FThing", module="Core", limit=10)

    assert rows
    assert rows[0]["file_path"].endswith("Test.cpp")


def test_trigram_matches_code_symbols(tmp_path):
    db_path = tmp_path / "source.db"
    conn = connect(db_path)
    initialize_schema(conn)
    upsert_source_file(
        conn,
        SourceFile(
            file_path="Engine/Source/Runtime/Renderer/GBuffer.cpp",
            module_name="Renderer",
            raw_content="FGBufferData GetGBuffer(int Index) { return GBuffer[Index]; }",
        ),
    )
    conn.commit()

    rows = search_source(conn, "GetGBuffer", limit=10)
    assert rows
    assert rows[0]["file_path"].endswith("GBuffer.cpp")

    rows = search_source(conn, "FGBufferData", limit=10)
    assert rows


def test_trigram_matches_dotted_symbols(tmp_path):
    db_path = tmp_path / "source.db"
    conn = connect(db_path)
    initialize_schema(conn)
    upsert_source_file(
        conn,
        SourceFile(
            file_path="Engine/Source/Runtime/Shader/Material.usf",
            module_name="Shader",
            raw_content="float Roughness = Material.Roughness * 0.5;",
        ),
    )
    conn.commit()

    rows = search_source(conn, "Material.Roughness", limit=10)
    assert rows


def test_log_query_and_feedback_loop(tmp_path):
    db_path = tmp_path / "source.db"
    conn = connect(db_path)
    initialize_schema(conn)
    upsert_source_file(
        conn,
        SourceFile(
            file_path="Engine/Source/Runtime/Core/Actor.cpp",
            module_name="Core",
            raw_content="void AActor::BeginPlay() { Super::BeginPlay(); }",
        ),
    )
    conn.commit()

    log_id = log_query(conn, "BeginPlay", "BeginPlay", [1])
    assert log_id > 0

    row = conn.execute("SELECT * FROM query_logs WHERE id = ?", (log_id,)).fetchone()
    assert row["query_text"] == "BeginPlay"
    assert row["hit_count"] == 1

    result = record_feedback(conn, "Engine/Source/Runtime/Core/Actor.cpp", was_useful=True)
    assert result is True

    note = conn.execute("SELECT * FROM query_note WHERE query_log_id = ?", (log_id,)).fetchone()
    assert note is not None
    assert note["was_useful"] == 1


def test_record_feedback_no_recent_query(tmp_path):
    db_path = tmp_path / "source.db"
    conn = connect(db_path)
    initialize_schema(conn)
    upsert_source_file(
        conn,
        SourceFile(
            file_path="Engine/Source/Runtime/Core/Orphan.cpp",
            module_name="Core",
            raw_content="void Orphan() {}",
        ),
    )
    conn.commit()

    result = record_feedback(conn, "Engine/Source/Runtime/Core/Orphan.cpp")
    assert result is False


def test_search_with_feedback_logs_query(tmp_path):
    db_path = tmp_path / "source.db"
    conn = connect(db_path)
    initialize_schema(conn)
    upsert_source_file(
        conn,
        SourceFile(
            file_path="Engine/Source/Runtime/Renderer/Lumen.cpp",
            module_name="Renderer",
            raw_content="void FLumenScene::Render() { TraceLumen(); }",
        ),
    )
    conn.commit()

    rows = search_source_with_feedback(conn, query="Lumen")
    assert len(rows) == 1
    assert rows[0]["source"] == "fts"

    log = conn.execute("SELECT * FROM query_logs ORDER BY id DESC LIMIT 1").fetchone()
    assert log["query_text"] == "Lumen"


def test_search_with_feedback_uses_history(tmp_path):
    db_path = tmp_path / "source.db"
    conn = connect(db_path)
    initialize_schema(conn)
    fid = upsert_source_file(
        conn,
        SourceFile(
            file_path="Engine/Source/Runtime/Renderer/Lumen.cpp",
            module_name="Renderer",
            raw_content="void FLumenScene::Render() { TraceLumen(); }",
        ),
    )
    conn.commit()

    # First search: no history, full FTS5
    rows = search_source_with_feedback(conn, query="Lumen")
    assert len(rows) == 1
    assert rows[0]["source"] == "fts"

    # Record feedback (adopted file)
    record_feedback(conn, "Engine/Source/Runtime/Renderer/Lumen.cpp", was_useful=True)

    # Second search: history-first, candidate set from hit_file_ids
    rows = search_source_with_feedback(conn, query="Lumen")
    assert len(rows) == 1
    assert rows[0]["source"] == "history_refined"


def test_snippet_extraction(tmp_path):
    db_path = tmp_path / "source.db"
    conn = connect(db_path)
    initialize_schema(conn)
    upsert_source_file(
        conn,
        SourceFile(
            file_path="Engine/Source/Runtime/Core/LargeFile.cpp",
            module_name="Core",
            raw_content=(
                "\n".join(f"// line {i}" for i in range(100))
                + "\nvoid TargetFunction() { return; }\n"
                + "\n".join(f"// line {i}" for i in range(100))
            ),
        ),
    )
    conn.commit()

    rows = search_source(conn, "TargetFunction", limit=10)
    assert rows
    assert "TargetFunction" in rows[0]["snippet"]


def test_shader_extensions():
    for ext in (".usf", ".ush", ".hlsl"):
        assert ext in SOURCE_EXTENSIONS


def _seed_two_files(conn):
    upsert_source_file(
        conn,
        SourceFile(
            file_path="Engine/Source/Runtime/A/FileA.cpp",
            module_name="A",
            raw_content="void FThing::Run() { /* alpha */ }",
        ),
    )
    upsert_source_file(
        conn,
        SourceFile(
            file_path="Engine/Source/Runtime/B/FileB.cpp",
            module_name="B",
            raw_content="void FOther::Go() { /* alpha beta */ }",
        ),
    )
    conn.commit()


def test_raw_query_and(tmp_path):
    db_path = tmp_path / "source.db"
    conn = connect(db_path)
    initialize_schema(conn)
    _seed_two_files(conn)

    rows = search_source_raw(conn, '"FThing" AND "alpha"')
    assert len(rows) == 1
    assert "FileA" in rows[0]["file_path"]

    rows = search_source_raw(conn, '"FThing" AND "beta"')
    assert len(rows) == 0


def test_raw_query_or(tmp_path):
    db_path = tmp_path / "source.db"
    conn = connect(db_path)
    initialize_schema(conn)
    _seed_two_files(conn)

    rows = search_source_raw(conn, '"FThing" OR "FOther"')
    assert len(rows) == 2


def test_raw_query_not(tmp_path):
    db_path = tmp_path / "source.db"
    conn = connect(db_path)
    initialize_schema(conn)
    _seed_two_files(conn)

    rows = search_source_raw(conn, '"alpha" NOT "beta"')
    assert len(rows) == 1
    assert "FileA" in rows[0]["file_path"]


def test_raw_query_column_filter(tmp_path):
    db_path = tmp_path / "source.db"
    conn = connect(db_path)
    initialize_schema(conn)
    _seed_two_files(conn)

    rows = search_source_raw(conn, 'file_path : "FileA"')
    assert len(rows) == 1
    assert "FileA" in rows[0]["file_path"]


def test_raw_query_invalid_syntax(tmp_path):
    import sqlite3

    db_path = tmp_path / "source.db"
    conn = connect(db_path)
    initialize_schema(conn)

    try:
        search_source_raw(conn, "!!! invalid !!!")
        raise AssertionError("Should have raised")
    except sqlite3.OperationalError:
        pass


def test_prune_stale_data(tmp_path):
    db_path = tmp_path / "source.db"
    conn = connect(db_path)
    initialize_schema(conn)

    log_query(conn, "old_query", "old_query", [])

    conn.execute(
        "UPDATE query_logs SET created_at = datetime('now', '-61 days') WHERE query_text = 'old_query'"
    )
    conn.commit()

    result = prune_stale_data(conn)
    assert result["logs_deleted"] == 1

    remaining = conn.execute("SELECT count(*) FROM query_logs").fetchone()[0]
    assert remaining == 0


def test_prune_keeps_noted_logs(tmp_path):
    db_path = tmp_path / "source.db"
    conn = connect(db_path)
    initialize_schema(conn)

    fid = upsert_source_file(
        conn,
        SourceFile(
            file_path="Engine/Source/Runtime/Core/Keep.cpp",
            module_name="Core",
            raw_content="void Keep() {}",
        ),
    )
    conn.commit()

    log_id = log_query(conn, "keep_query", "keep_query", [fid])
    conn.execute(
        "UPDATE query_logs SET created_at = datetime('now', '-61 days') WHERE id = ?",
        (log_id,),
    )
    conn.execute(
        "INSERT INTO query_note(query_log_id, was_useful) VALUES (?, 1)", (log_id,)
    )
    conn.commit()

    result = prune_stale_data(conn)
    assert result["logs_deleted"] == 0

    remaining = conn.execute("SELECT count(*) FROM query_logs").fetchone()[0]
    assert remaining == 1


def test_query_log_view(tmp_path):
    db_path = tmp_path / "source.db"
    conn = connect(db_path)
    initialize_schema(conn)
    fid = upsert_source_file(
        conn,
        SourceFile(
            file_path="Engine/Source/Runtime/Core/View.cpp",
            module_name="Core",
            raw_content="void View() {}",
        ),
    )
    conn.commit()

    log_id = log_query(conn, "View", "View", [fid])
    record_feedback(conn, "Engine/Source/Runtime/Core/View.cpp", was_useful=True)

    rows = conn.execute("SELECT * FROM query_log_view WHERE log_id = ?", (log_id,)).fetchall()
    assert len(rows) == 1
    assert rows[0]["was_useful"] == 1
