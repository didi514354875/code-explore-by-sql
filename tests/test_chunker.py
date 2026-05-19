from unreal_source_mcp.chunker import extract_chunks


def test_extract_member_function_skips_braces_in_strings_and_comments():
    source = r'''
void FThing::Run(int32 Count)
{
    FString Text = TEXT("}");
    // }
    if (Count > 0)
    {
        DoWork();
    }
}
'''.strip()

    chunks = extract_chunks(source, symbol="Run")

    assert len(chunks) == 1
    assert chunks[0].symbol_name == "FThing::Run"
    assert chunks[0].start_line == 1
    assert chunks[0].end_line == 9


def test_extract_class_and_macro():
    source = """
#define UE_TEST_MACRO(X) \\
    X + 1

UCLASS()
class ENGINE_API UDemoObject : public UObject
{
public:
    GENERATED_BODY()
};
""".strip()

    chunks = extract_chunks(source)
    names = {chunk.symbol_name for chunk in chunks}

    assert "UE_TEST_MACRO" in names
    assert "UDemoObject" in names
