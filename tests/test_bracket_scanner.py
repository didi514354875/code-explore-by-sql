"""Comprehensive correctness tests for bracket_scanner and symbol_sniffer."""

from __future__ import annotations

import sys

from unreal_source_mcp.bracket_scanner import scan_brackets, BracketBlock
from unreal_source_mcp.symbol_sniffer import sniff_block, sniff_blocks_for_file, BlockInfo

PASS = 0
FAIL = 0


def check(name: str, condition: bool, detail: str = ""):
    global PASS, FAIL
    if condition:
        PASS += 1
        print(f"  [PASS] {name}")
    else:
        FAIL += 1
        print(f"  [FAIL] {name} — {detail}")


# ========================================================================
# Bracket Scanner Tests
# ========================================================================
print("=" * 60)
print("BRACKET SCANNER TESTS")
print("=" * 60)

# --- Test 1: Basic function ---
print("\n[Test 1] Basic function")
code = """\
void foo() {
    int x = 1;
}
"""
blocks = scan_brackets(code)
check("one block found", len(blocks) == 1, f"got {len(blocks)}")
if blocks:
    check("depth=1", blocks[0].depth == 1, f"depth={blocks[0].depth}")
    check("open_line=1", blocks[0].open_line == 1, f"open={blocks[0].open_line}")
    check("close_line=3", blocks[0].close_line == 3, f"close={blocks[0].close_line}")
    check("is_complete", blocks[0].is_complete)

# --- Test 2: Nested braces ---
print("\n[Test 2] Nested braces")
code = """\
void foo() {
    if (true) {
        for (int i = 0; i < 10; i++) {
            bar();
        }
    }
}
"""
blocks = scan_brackets(code)
check("3 blocks found (depths 1,2,3)", len(blocks) == 3, f"got {len(blocks)}")
depths = sorted([b.depth for b in blocks])
check("depths are [1,2,3]", depths == [1, 2, 3], f"got {depths}")

# --- Test 3: Line comment immunity ---
print("\n[Test 3] Line comment immunity")
code = """\
void foo() {
    // { fake brace }
    int x = 1;
}
"""
blocks = scan_brackets(code)
check("1 block (comment braces ignored)", len(blocks) == 1, f"got {len(blocks)}")

# --- Test 4: Block comment immunity ---
print("\n[Test 4] Block comment immunity (single line)")
code = """\
void foo() {
    /* { fake } */
    int x = 1;
}
"""
blocks = scan_brackets(code)
check("1 block (block comment braces ignored)", len(blocks) == 1, f"got {len(blocks)}")

# --- Test 5: Multi-line block comment ---
print("\n[Test 5] Multi-line block comment")
code = """\
void foo() {
    /* this comment spans
       multiple lines and has { braces }
       and more { } braces */
    int x = 1;
}
"""
blocks = scan_brackets(code)
check("1 block (multi-line comment braces ignored)", len(blocks) == 1, f"got {len(blocks)}")

# --- Test 6: String literal immunity ---
print("\n[Test 6] String literal immunity")
code = '''\
void foo() {
    char* s = "some { text } here";
    int x = 1;
}
'''
blocks = scan_brackets(code)
check("1 block (string braces ignored)", len(blocks) == 1, f"got {len(blocks)}")

# --- Test 7: Escaped quote in string ---
print("\n[Test 7] Escaped quote in string")
code = '''\
void foo() {
    char* s = "text \\" { brace } \\" end";
    int x = 1;
}
'''
blocks = scan_brackets(code)
check("1 block (escaped quotes handled)", len(blocks) == 1, f"got {len(blocks)}")

# --- Test 8: Character literal immunity ---
print("\n[Test 8] Character literal immunity")
code = """\
void foo() {
    char c = '{';
    char d = '}';
    int x = 1;
}
"""
blocks = scan_brackets(code)
check("1 block (char literal braces ignored)", len(blocks) == 1, f"got {len(blocks)}")

# --- Test 9: Raw string immunity ---
print("\n[Test 9] Raw string immunity")
code = '''\
void foo() {
    const char* s = R"delim(raw { string } with braces)delim";
    int x = 1;
}
'''
blocks = scan_brackets(code)
check("1 block (raw string braces ignored)", len(blocks) == 1, f"got {len(blocks)}")

# --- Test 10: Unclosed brace ---
print("\n[Test 10] Unclosed brace")
code = """\
void foo() {
    if (true) {
        bar();
"""
blocks = scan_brackets(code)
check("2 blocks (both incomplete)", len(blocks) == 2, f"got {len(blocks)}")
incomplete = [b for b in blocks if not b.is_complete]
check("both are incomplete", len(incomplete) == 2, f"got {len(incomplete)}")

# --- Test 11: Extra closing brace ---
print("\n[Test 11] Extra closing brace")
code = """\
void foo() {
    int x = 1;
}
}
"""
blocks = scan_brackets(code)
check("1 complete block", len(blocks) == 1, f"got {len(blocks)}")
check("block is complete", blocks[0].is_complete)

# --- Test 12: Multiple top-level blocks ---
print("\n[Test 12] Multiple top-level blocks")
code = """\
namespace A {
    void f1() {}
    void f2() {}
}

namespace B {
    void f3() {}
}
"""
blocks = scan_brackets(code)
check("5 blocks total (2 namespaces + 3 functions)", len(blocks) == 5, f"got {len(blocks)}")
top = [b for b in blocks if b.depth == 1]
check("2 top-level blocks (namespaces)", len(top) == 2, f"got {len(top)}")

# --- Test 13: Class with methods ---
print("\n[Test 13] Class with methods (typical UE pattern)")
code = """\
UCLASS()
class MYMODULE_API UMyClass : public UObject
{
    GENERATED_BODY()
public:
    UFUNCTION()
    void MyFunc() {
        if (true) {
            DoSomething();
        }
    }

    UPROPERTY()
    float MyFloat;
};
"""
blocks = scan_brackets(code)
check("3 blocks", len(blocks) == 3, f"got {len(blocks)}")
check("class is depth=1", blocks[2].depth == 1)
check("function is depth=2", blocks[1].depth == 2)
check("if-block is depth=3", blocks[0].depth == 3)

# --- Test 14: Empty file ---
print("\n[Test 14] Empty file")
blocks = scan_brackets("")
check("0 blocks for empty file", len(blocks) == 0, f"got {len(blocks)}")

# --- Test 15: No braces ---
print("\n[Test 15] No braces")
code = """\
#include <iostream>
// just comments
int x = 42;
"""
blocks = scan_brackets(code)
check("0 blocks", len(blocks) == 0, f"got {len(blocks)}")

# --- Test 16: Preprocessor with continuation ---
print("\n[Test 16] Preprocessor continuation lines")
code = """\
#define MACRO { \\
    int x; \\
}

void foo() {
    MACRO
}
"""
blocks = scan_brackets(code)
check("2 blocks (macro brace + foo brace)", len(blocks) == 2, f"got {len(blocks)}")

# --- Test 17: Template brackets are NOT tracked ---
print("\n[Test 17] Template < > not tracked as braces")
code = """\
void foo() {
    std::vector<int> v;
    std::map<int, float> m;
}
"""
blocks = scan_brackets(code)
check("1 block (angle brackets ignored)", len(blocks) == 1, f"got {len(blocks)}")


# ========================================================================
# Symbol Sniffer Tests
# ========================================================================
print("\n" + "=" * 60)
print("SYMBOL SNIFFER TESTS")
print("=" * 60)

# --- Test S1: Namespace ---
print("\n[Test S1] Namespace")
info = sniff_block(["namespace MyEngine"], 1, ["namespace MyEngine", "{"])
check("type=namespace", info.block_type == "namespace", f"got {info.block_type}")
check("name=MyEngine", info.block_name == "MyEngine", f"got {info.block_name}")

# --- Test S2: Simple class ---
print("\n[Test S2] Simple class")
info = sniff_block(["class MyClass : public Base"], 1, ["class MyClass : public Base", "{"])
check("type=class", info.block_type == "class", f"got {info.block_type}")
check("name=MyClass", info.block_name == "MyClass", f"got {info.block_name}")

# --- Test S3: UE class with macros ---
print("\n[Test S3] UE class with macros")
info = sniff_block(
    ["UCLASS()", "class MYMODULE_API UMyClass : public UObject"],
    2,
    ["UCLASS()", "class MYMODULE_API UMyClass : public UObject", "{"],
)
check("type=class", info.block_type == "class", f"got {info.block_type}")
check("name=UMyClass", info.block_name == "UMyClass", f"got {info.block_name}")

# --- Test S4: Struct ---
print("\n[Test S4] Struct")
info = sniff_block(["struct FMeshData"], 1, ["struct FMeshData", "{"])
check("type=class (struct→class)", info.block_type == "class", f"got {info.block_type}")
check("name=FMeshData", info.block_name == "FMeshData", f"got {info.block_name}")

# --- Test S5: Enum ---
print("\n[Test S5] Enum class")
info = sniff_block(["enum class ELightType"], 1, ["enum class ELightType", "{"])
check("type=enum", info.block_type == "enum", f"got {info.block_type}")
check("name=ELightType", info.block_name == "ELightType", f"got {info.block_name}")

# --- Test S6: Plain enum ---
print("\n[Test S6] Plain enum")
info = sniff_block(["enum EMyEnum"], 1, ["enum EMyEnum", "{"])
check("type=enum", info.block_type == "enum", f"got {info.block_type}")
check("name=EMyEnum", info.block_name == "EMyEnum", f"got {info.block_name}")

# --- Test S7: Function ---
print("\n[Test S7] Function")
info = sniff_block(
    ["void FRenderer::Render(const FScene* Scene)"],
    1,
    ["void FRenderer::Render(const FScene* Scene)", "{"],
)
check("type=function", info.block_type == "function", f"got {info.block_type}")
check("name=FRenderer::Render", info.block_name == "FRenderer::Render", f"got {info.block_name}")

# --- Test S8: Control flow ---
print("\n[Test S8] Control flow (if)")
info = sniff_block(["if (bIsEnabled)"], 1, ["if (bIsEnabled)", "{"])
check("type=control_flow", info.block_type == "control_flow", f"got {info.block_type}")

# --- Test S9: Control flow (for) ---
print("\n[Test S9] Control flow (for)")
info = sniff_block(["for (int i = 0; i < Count; i++)"], 1, ["for (int i = 0; i < Count; i++)", "{"])
check("type=control_flow", info.block_type == "control_flow", f"got {info.block_type}")

# --- Test S10: Macro define ---
print("\n[Test S10] #define macro")
info = sniff_block(["#define IMPLEMENT_MODULE(ModuleClass, ModuleName)"], 1, ["#define IMPLEMENT_MODULE(ModuleClass, ModuleName)", "{"])
check("type=macro", info.block_type == "macro", f"got {info.block_type}")

# --- Test S11: UE macro skip (GENERATED_BODY) ---
print("\n[Test S11] UE macro lines skipped")
info = sniff_block(
    ["GENERATED_BODY()", "void MyFunction()"],
    2,
    ["GENERATED_BODY()", "void MyFunction()", "{"],
)
check("type=function (skips GENERATED_BODY)", info.block_type == "function", f"got {info.block_type}")
check("name=MyFunction", info.block_name == "MyFunction", f"got {info.block_name}")

# --- Test S12: Multi-line function signature ---
print("\n[Test S12] Multi-line function signature")
info = sniff_block(
    ["void FDeferredShadingRenderer::Render(",
     "    FRHICommandListImmediate& RHICmdList,",
     "    const FViewInfo& View)"],
    3,
    ["void FDeferredShadingRenderer::Render(",
     "    FRHICommandListImmediate& RHICmdList,",
     "    const FViewInfo& View)",
     "{"],
)
check("type=function", info.block_type == "function", f"got {info.block_type}")
check("name=FDeferredShadingRenderer::Render", info.block_name == "FDeferredShadingRenderer::Render", f"got {info.block_name}")

# --- Test S13: Unknown block ---
print("\n[Test S13] Unknown block")
info = sniff_block(["int x = 42;"], 1, ["int x = 42;", "{"])
check("type=unknown", info.block_type == "unknown", f"got {info.block_type}")

# --- Test S14: sniff_blocks_for_file integration ---
print("\n[Test S14] Full file sniff_blocks_for_file")
lines = """\
#include "Test.h"

namespace MyNS {

class FMyClass {
    void Foo() {
        if (true) {
            bar();
        }
    }
};

enum class EMyEnum {
    Value1,
    Value2
};

}  // namespace MyNS
""".split("\n")

from unreal_source_mcp.bracket_scanner import scan_brackets

blocks = scan_brackets("\n".join(lines))
top_blocks = [(b.open_line - 1, b.close_line - 1) for b in blocks if b.depth == 1]
sniffed = sniff_blocks_for_file(lines, top_blocks)

check("1 top-level block sniffed (namespace wraps class+enum)", len(sniffed) == 1, f"got {len(sniffed)}")
if sniffed:
    types = [info.block_type for _, info in sniffed]
    names = [info.block_name for _, info in sniffed]
    check("type is [namespace]", types == ["namespace"], f"got {types}")
    check("name is [MyNS]", names == ["MyNS"], f"got {names}")


# ========================================================================
# Summary
# ========================================================================
print("\n" + "=" * 60)
total = PASS + FAIL
print(f"RESULTS: {PASS}/{total} passed, {FAIL} failed")
print("=" * 60)

if FAIL > 0:
    sys.exit(1)
