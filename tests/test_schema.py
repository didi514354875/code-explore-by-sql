from unreal_source_mcp.db import (
    SourceFile,
    connect,
    get_templates,
    initialize_schema,
    log_query,
    save_template,
    search_source,
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
