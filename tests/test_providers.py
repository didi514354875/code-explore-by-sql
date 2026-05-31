"""Tests for provider architecture and reference tracking."""
from __future__ import annotations

import re
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from code_explore_by_sql.providers import get_provider, list_providers
from code_explore_by_sql.providers.base import IncludeDirective
from code_explore_by_sql.sniffers.reference_tracker import (
    ReferenceTrackerConfig,
    track_references_for_file,
    enrich_ref_block_ids,
    prepare_bracket_arrays,
)
from code_explore_by_sql.bracket_scanner import (
    BracketScannerConfig,
    compute_parent_ids,
    scan_brackets,
)

passed = 0
failed = 0


def check(name: str, condition: bool) -> None:
    global passed, failed
    status = "[PASS]" if condition else "[FAIL]"
    print(f"  {status} {name}")
    if condition:
        passed += 1
    else:
        failed += 1


def test_provider_registry():
    print("[Test P1] Provider registry")
    providers = list_providers()
    check("cc provider registered", "cc" in providers)
    check("unreal provider registered", "unreal" in providers)


def test_cc_provider():
    print("[Test P2] CCProvider")
    cc = get_provider("cc")
    check("name is cc", cc.name == "cc")
    check("has .cpp extension", ".cpp" in cc.source_extensions)
    check("has .h extension", ".h" in cc.source_extensions)
    check("skip_line_re is None", cc.skip_line_re() is None)

    # Test include parsing
    lines = [
        '#include <iostream>',
        '#include "myheader.h"',
        'int main() {',
    ]
    directives = cc.parse_include_directives(lines)
    check("found 2 includes", len(directives) == 2)
    if directives:
        check("first include is <iostream>", directives[0].path == "iostream")
        check("first include line is 1", directives[0].line_number == 1)
        check("second include is myheader.h", directives[1].path == "myheader.h")
        check("second include line is 2", directives[1].line_number == 2)


def test_unreal_provider():
    print("[Test P3] UnrealProvider")
    ue = get_provider("unreal")
    check("name is unreal", ue.name == "unreal")
    check("has skip_line_re", ue.skip_line_re() is not None)

    # Test UE macro filtering
    lines = [
        "UCLASS()",
        "GENERATED_BODY()",
        "UPROPERTY(EditAnywhere)",
        "UFUNCTION(BlueprintCallable)",
        "int x = 5;",
    ]
    filtered = ue.filter_lines(lines)
    check("filtered 4 UE macro lines", len(filtered) == 4)
    check("filtered lines are UE macros", all("UCLASS" in l or "GENERATED" in l or "UPROPERTY" in l or "UFUNCTION" in l for l in filtered))

    # Test skip_line_re
    skip_re = ue.skip_line_re()
    check("UCLASS matches skip_re", skip_re is not None and skip_re.search("UCLASS()"))
    check("int x does not match skip_re", skip_re is not None and not skip_re.search("int x = 5;"))


def test_include_directive():
    print("[Test P4] IncludeDirective dataclass")
    inc = IncludeDirective(path="foo.h", line_number=5, directive_type="include")
    check("path is foo.h", inc.path == "foo.h")
    check("line_number is 5", inc.line_number == 5)
    check("directive_type is include", inc.directive_type == "include")


def test_bracket_scanner_config():
    print("[Test P5] BracketScannerConfig")
    config = BracketScannerConfig()
    check("default open_brace is {", config.open_brace == "{")
    check("default close_brace is }", config.close_brace == "}")
    check("default line_comment is //", config.line_comment == "//")
    check("default block_comment_start is /*", config.block_comment_start == "/*")
    check("default block_comment_end is */", config.block_comment_end == "*/")

    # Custom config
    custom = BracketScannerConfig(open_brace="(", close_brace=")")
    check("custom open_brace is (", custom.open_brace == "(")
    check("custom close_brace is )", custom.close_brace == ")")


def test_compute_parent_ids():
    print("[Test P6] compute_parent_ids")
    from code_explore_by_sql.block_model import BracketBlock

    # namespace { class { function { } } }
    blocks = [
        BracketBlock(open_line=1, close_line=10, depth=1, is_complete=True),   # namespace
        BracketBlock(open_line=2, close_line=9, depth=2, is_complete=True),    # class
        BracketBlock(open_line=3, close_line=8, depth=3, is_complete=True),    # function
    ]
    parent_map = compute_parent_ids(blocks)
    check("namespace has no parent", parent_map.get((1, 1)) is None)
    check("class parent is namespace", parent_map.get((2, 2)) == (1, 1))
    check("function parent is class", parent_map.get((3, 3)) == (2, 2))


def test_compute_parent_ids_multiple_siblings():
    print("[Test P7] compute_parent_ids with siblings")
    from code_explore_by_sql.block_model import BracketBlock

    # namespace { func_a { } func_b { } }
    blocks = [
        BracketBlock(open_line=1, close_line=10, depth=1, is_complete=True),   # namespace
        BracketBlock(open_line=2, close_line=4, depth=2, is_complete=True),    # func_a
        BracketBlock(open_line=5, close_line=8, depth=2, is_complete=True),    # func_b
    ]
    parent_map = compute_parent_ids(blocks)
    check("namespace has no parent", parent_map.get((1, 1)) is None)
    check("func_a parent is namespace", parent_map.get((2, 2)) == (1, 1))
    check("func_b parent is namespace", parent_map.get((5, 2)) == (1, 1))


def test_reference_tracker_config():
    print("[Test P8] ReferenceTrackerConfig")
    config = ReferenceTrackerConfig()
    check("default max_definition_count is 20", config.max_definition_count == 20)
    check("default min_name_length is 3", config.min_name_length == 3)
    check("int is in skip_keywords", "int" in config.skip_keywords)
    check("class is in skip_keywords", "class" in config.skip_keywords)


def test_track_references_for_file():
    print("[Test P9] track_references_for_file")
    content = "class Foo {\npublic:\n    void bar();\n};\n\nvoid baz() {\n    Foo* f = new Foo();\n    f->bar();\n}\n"
    lines = content.split("\n")
    symbols = [
        {
            "name": "Foo",
            "type": "class",
            "file_id": 1,
            "block_id": 1,
            "open_line": 1,
            "close_line": 4,
        },
        {
            "name": "bar",
            "type": "function",
            "file_id": 1,
            "block_id": 2,
            "open_line": 3,
            "close_line": 3,
        },
    ]
    # Build target_symbols dict (name -> [sym_dict, ...])
    target_symbols: dict = {}
    for sym in symbols:
        target_symbols.setdefault(sym["name"], []).append(sym)

    refs = track_references_for_file(lines, 1, target_symbols)
    # refs are tuples: (sym_name, sym_type, sym_file_id, ref_file_id, ref_block_id, ref_line)
    foo_refs = [r for r in refs if r[0] == "Foo"]
    bar_refs = [r for r in refs if r[0] == "bar"]

    check("found Foo references", len(foo_refs) > 0)
    check("found bar references", len(bar_refs) > 0)
    # Foo appears on line 7 (Foo* f = new Foo();)
    foo_lines = {r[5] for r in foo_refs}
    check("Foo ref on line 7", 7 in foo_lines)
    # bar appears on line 3 (definition, should be skipped) and line 8 (f->bar();)
    bar_lines = {r[5] for r in bar_refs}
    check("bar ref on line 8 (not def line 3)", 8 in bar_lines and 3 not in bar_lines)


def test_enrich_ref_block_ids():
    print("[Test P10] enrich_ref_block_ids")

    # refs are tuples: (sym_name, sym_type, sym_file_id, ref_file_id, ref_block_id, ref_line)
    refs = [
        ("Foo", "class", 1, 1, None, 5),
        ("Foo", "class", 1, 1, None, 15),
    ]
    bracket_data = [
        {"id": 100, "open_line": 1, "close_line": 20, "depth": 1},
        {"id": 101, "open_line": 3, "close_line": 10, "depth": 2},
        {"id": 102, "open_line": 12, "close_line": 18, "depth": 2},
    ]
    bracket_arrays = prepare_bracket_arrays(bracket_data)
    enriched = enrich_ref_block_ids(refs, bracket_arrays)
    check("enriched 2 refs", len(enriched) == 2)
    check("ref at line 5 -> block 101", enriched[0][4] == 101)
    check("ref at line 15 -> block 102", enriched[1][4] == 102)


if __name__ == "__main__":
    print("=" * 60)
    print("PROVIDER + REFERENCE TRACKER + PARENT_ID TESTS")
    print("=" * 60)

    test_provider_registry()
    test_cc_provider()
    test_unreal_provider()
    test_include_directive()
    test_bracket_scanner_config()
    test_compute_parent_ids()
    test_compute_parent_ids_multiple_siblings()
    test_reference_tracker_config()
    test_track_references_for_file()
    test_enrich_ref_block_ids()

    print("=" * 60)
    print(f"RESULTS: {passed}/{passed+failed} passed, {failed} failed")
    print("=" * 60)
    sys.exit(1 if failed else 0)
