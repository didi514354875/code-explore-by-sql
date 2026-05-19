from unreal_source_mcp.benchmark import benchmark_query, summarize_reports
from unreal_source_mcp.chunker import extract_chunks
from unreal_source_mcp.db import (
    SourceFile,
    connect,
    get_cached_chunks,
    get_templates,
    initialize_schema,
    log_query,
    replace_chunks_for_file,
    save_template,
    search_chunks,
    search_source,
    upsert_source_file,
)


def test_schema_indexes_and_searches_source(tmp_path):
    db_path = tmp_path / "source.db"
    conn = connect(db_path)
    initialize_schema(conn)
    file_id = upsert_source_file(
        conn,
        SourceFile(
            file_path="Engine/Source/Runtime/Core/Test.cpp",
            module_name="Core",
            raw_content="void FThing::Run() { UE_LOG(LogTemp, Warning, TEXT(\"hello\")); }",
        ),
    )
    conn.commit()

    rows = search_source(conn, "FThing Run", module="Core", limit=10)

    assert file_id > 0
    assert rows
    assert rows[0]["file_path"].endswith("Test.cpp")


def test_cached_chunks_are_searchable(tmp_path):
    db_path = tmp_path / "source.db"
    conn = connect(db_path)
    initialize_schema(conn)
    file_id = upsert_source_file(
        conn,
        SourceFile(
            file_path="Engine/Source/Runtime/Core/Test.cpp",
            module_name="Core",
            raw_content="""
void FThing::Run()
{
    UE_LOG(LogTemp, Warning, TEXT("hello"));
}
""".strip(),
        ),
    )

    count = replace_chunks_for_file(conn, file_id, extract_chunks("void FThing::Run() { DoWork(); }"))
    conn.commit()

    cached = get_cached_chunks(conn, file_id, symbol="Run", limit=10)
    rows = search_chunks(conn, "FThing Run", module="Core", limit=10, body_chars=12)

    assert count == 1
    assert cached[0]["symbol_name"] == "FThing::Run"
    assert rows[0]["file_path"].endswith("Test.cpp")
    assert rows[0]["truncated"] is True


def test_template_feedback_updates_stats(tmp_path):
    db_path = tmp_path / "source.db"
    conn = connect(db_path)
    initialize_schema(conn)

    template_id = save_template(
        conn,
        intent_pattern="find lifecycle function",
        fts_template="BeginPlay Tick",
        intent_keywords=["lifecycle", "actor"],
    )
    log_query(conn, "where is actor BeginPlay", "BeginPlay", [], was_useful=True, template_id=template_id)

    templates = get_templates(conn, "lifecycle", limit=10)

    assert templates[0]["id"] == template_id
    assert templates[0]["useful_count"] == 1
    assert templates[0]["success_rate"] == 1.0


def test_benchmark_reports_token_advantage(tmp_path):
    db_path = tmp_path / "source.db"
    conn = connect(db_path)
    initialize_schema(conn)
    file_id = upsert_source_file(
        conn,
        SourceFile(
            file_path="Engine/Source/Runtime/Core/Test.cpp",
            module_name="Core",
            raw_content="""
void FThing::Run()
{
    UE_LOG(LogTemp, Warning, TEXT("hello"));
    DoWork();
    DoWork();
    DoWork();
}
""".strip(),
        ),
    )
    raw_content = conn.execute("SELECT raw_content FROM source_files").fetchone()[0]
    replace_chunks_for_file(conn, file_id, extract_chunks(raw_content))
    conn.commit()

    report = benchmark_query(conn, query="FThing Run", module="Core", limit=5, body_chars=40)
    summary = summarize_reports([report])

    assert report["file_hits"] >= 1
    assert report["chunk_hits"] >= 1
    assert report["full_file_estimated_tokens"] >= report["chunk_body_estimated_tokens"]
    assert summary["file_to_chunk_token_ratio"] is not None
    assert summary["file_to_chunk_token_ratio"] >= 1.0
