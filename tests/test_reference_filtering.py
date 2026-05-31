"""Tests for block-type-aware reference filtering in reference_tracker."""
import re
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from code_explore_by_sql.sniffers.reference_tracker import (
    _is_structural_reference,
    _extract_type_refs_from_class_body,
    track_references_for_file,
)


# ---------------------------------------------------------------------------
# _is_structural_reference tests
# ---------------------------------------------------------------------------

class TestIsStructuralReference:
    def test_function_call(self):
        line = "  foo(arg);"
        # "foo" starts at 2, ends at 5
        assert _is_structural_reference(line, 2, 5) is True  # followed by (

    def test_template_usage(self):
        line = "  TArray<int> arr;"
        # "TArray" starts at 2, ends at 8 (line[8] = '<')
        assert _is_structural_reference(line, 2, 8) is True  # followed by <

    def test_member_access_dot(self):
        line = "  obj.method()"
        # "method" starts at 6, ends at 12
        assert _is_structural_reference(line, 6, 12) is True  # preceded by .

    def test_member_access_arrow(self):
        line = "  ptr->method()"
        # "method" starts at 7, ends at 13
        assert _is_structural_reference(line, 7, 13) is True  # preceded by ->

    def test_namespace_qualifier(self):
        line = "  NS::Foo x;"
        # "Foo" starts at 6, ends at 9
        assert _is_structural_reference(line, 6, 9) is True  # preceded by ::

    def test_qualified_after(self):
        line = "  Foo::Bar x;"
        # "Foo" starts at 2, ends at 5
        assert _is_structural_reference(line, 2, 5) is True  # followed by ::

    def test_new_expression(self):
        line = "  new Foo();"
        # "Foo" starts at 6, ends at 9
        assert _is_structural_reference(line, 6, 9) is True  # preceded by "new "

    def test_pointer_type(self):
        line = "  Foo* ptr;"
        # "Foo" starts at 2, ends at 5
        assert _is_structural_reference(line, 2, 5) is True  # followed by *

    def test_reference_type(self):
        line = "  Foo& ref;"
        # "Foo" starts at 2, ends at 5
        assert _is_structural_reference(line, 2, 5) is True  # followed by &

    def test_bare_identifier(self):
        line = "  int x = value;"
        # "value" starts at 9, ends at 14
        assert _is_structural_reference(line, 9, 14) is False  # bare, no structural context

    def test_standalone_name(self):
        line = "  name = something;"
        # "name" at 2:6
        assert _is_structural_reference(line, 2, 6) is False

    def test_at_end_of_line(self):
        line = "  return set;"
        # "set" at 9:12
        assert _is_structural_reference(line, 9, 12) is False


# ---------------------------------------------------------------------------
# _extract_type_refs_from_class_body tests
# ---------------------------------------------------------------------------

class TestExtractTypeRefsFromClassBody:
    def test_extracts_member_types(self):
        lines = [
            "class Foo {",       # 0 -> open_line=1
            "  FVector pos;",    # 1
            "  UObject* obj;",   # 2
            "  int x;",          # 3
            "};",                # 4 -> close_line=5
        ]
        check_set = {"FVector", "UObject"}
        result = _extract_type_refs_from_class_body(lines, 0, 4, check_set)
        assert "FVector" in result
        assert "UObject" in result

    def test_skips_non_matching_types(self):
        lines = [
            "{",
            "  int x;",
            "  float y;",
            "}",
        ]
        check_set = {"FVector"}
        result = _extract_type_refs_from_class_body(lines, 0, 3, check_set)
        assert result == []

    def test_skips_comments_and_access_specifiers(self):
        lines = [
            "{",
            "public:",
            "  // FVector comment;",
            "  FVector pos;",
            "}",
        ]
        check_set = {"FVector"}
        result = _extract_type_refs_from_class_body(lines, 0, 4, check_set)
        assert result == ["FVector"]


# ---------------------------------------------------------------------------
# Block-type-aware filtering tests
# ---------------------------------------------------------------------------

class TestBlockTypeFiltering:
    def _make_bracket_data(self, blocks):
        """Helper: create bracket_data from (open_line, close_line, depth, block_type) tuples."""
        return [
            {"open_line": ol, "close_line": cl, "depth": d, "block_type": bt, "id": i + 1}
            for i, (ol, cl, d, bt) in enumerate(blocks)
        ]

    def test_file_level_refs_skipped(self):
        """Lines outside any block should not produce references."""
        lines = [
            '#include "foo.h"',   # L1 - file level
            "TArray arr;",        # L2 - file level
            "void foo() {",       # L3 - file level
            "  TArray<int> x;",   # L4 - inside function
            "}",                  # L5
        ]
        target_symbols = {"TArray": [("class", 99, 1)]}
        bracket_data = self._make_bracket_data([
            (4, 5, 1, "function"),  # function body { at L4..L5 — actually { is on L3
        ])
        # Fix: function opens at line containing {, which is L3, closes L5
        bracket_data = self._make_bracket_data([
            (3, 5, 1, "function"),
        ])
        refs = track_references_for_file(
            lines, 1, target_symbols,
            bracket_data=bracket_data,
        )
        # TArray on L2 (file level) should be skipped
        # TArray on L4 (inside function) should be kept
        ref_lines = [r[5] for r in refs]
        assert 2 not in ref_lines, "file-level ref should be skipped"
        assert 4 in ref_lines, "function-level ref should be kept"

    def test_namespace_refs_skipped(self):
        """Lines inside a namespace but outside any function should be skipped."""
        lines = [
            "namespace NS {",     # L1
            "  using FVector;",   # L2 - inside namespace, not function
            "  void foo() {",     # L3
            "    FVector v;",     # L4 - inside function
            "  }",                # L5
            "}",                  # L6
        ]
        target_symbols = {"FVector": [("class", 99, 1)]}
        bracket_data = self._make_bracket_data([
            (1, 6, 1, "namespace"),
            (3, 5, 2, "function"),
        ])
        refs = track_references_for_file(
            lines, 1, target_symbols,
            bracket_data=bracket_data,
        )
        ref_lines = [r[5] for r in refs]
        assert 2 not in ref_lines, "namespace-level ref should be skipped"
        assert 4 in ref_lines, "function-level ref should be kept"

    def test_class_body_uses_type_deps(self):
        """Class body should produce type-dependency refs, not all-identifier refs."""
        lines = [
            "class Foo {",       # L1
            "  FVector pos;",    # L2 - member type
            "  set(val);",       # L3 - not a member type, should be skipped
            "  UWorld* world;",  # L4 - member type
            "};",                # L5
        ]
        target_symbols = {
            "FVector": [("class", 99, 1)],
            "set": [("method", 99, 10)],
            "UWorld": [("class", 99, 20)],
        }
        bracket_data = self._make_bracket_data([
            (1, 5, 1, "class"),
        ])
        refs = track_references_for_file(
            lines, 1, target_symbols,
            bracket_data=bracket_data,
        )
        ref_names = {r[0] for r in refs}
        assert "FVector" in ref_names, "member type FVector should be referenced"
        assert "UWorld" in ref_names, "member type UWorld should be referenced"
        assert "set" not in ref_names, "set() call inside class body should not be tracked"

    def test_skip_names_filter(self):
        """Noise words should only produce structural references."""
        lines = [
            "void foo() {",       # L1
            "  set(value);",      # L2 - 'set' is a call (structural), 'value' is bare
            "  obj.set(x);",      # L3 - 'set' is member access (structural)
            "}",                  # L4
        ]
        target_symbols = {
            "set": [("method", 99, 10)],
            "value": [("method", 99, 20)],
        }
        bracket_data = self._make_bracket_data([
            (1, 4, 1, "function"),
        ])
        skip_names = frozenset({"set", "value"})
        refs = track_references_for_file(
            lines, 1, target_symbols,
            skip_names=skip_names,
            bracket_data=bracket_data,
        )
        ref_lines = {r[5] for r in refs}
        # "set" on L2: "set(" is structural (followed by '(') -> kept
        # "value" on L2: bare identifier, in skip_names -> skipped
        # "set" on L3: ".set" is structural (preceded by '.') -> kept
        assert 2 in ref_lines, "set(value) - set() call should be structural"
        assert 3 in ref_lines, "obj.set() - member access should be structural"
        # Check that 'value' was skipped
        value_refs = [r for r in refs if r[0] == "value"]
        assert len(value_refs) == 0, "bare 'value' should be skipped when in skip_names"

    def test_define_body_skipped(self):
        """#define macro bodies should be skipped."""
        lines = [
            "#define FOO(x) \\",   # L1 - #define start
            "  do { \\",           # L2 - continuation
            "    TArray x; \\",    # L3 - continuation
            "  } while(0)",        # L4 - last line of macro (no \\)
            "void foo() {",        # L5
            "  TArray<int> a;",    # L6 - real code
            "}",                   # L7
        ]
        target_symbols = {"TArray": [("class", 99, 1)]}
        bracket_data = self._make_bracket_data([
            (5, 7, 1, "function"),
        ])
        refs = track_references_for_file(
            lines, 1, target_symbols,
            bracket_data=bracket_data,
        )
        ref_lines = [r[5] for r in refs]
        assert 3 not in ref_lines, "TArray inside #define should be skipped"
        assert 6 in ref_lines, "TArray in real code should be kept"

    def test_density_limit(self):
        """Per-symbol per-file density should be capped."""
        # Create a function body that mentions "TArray" on many lines
        func_lines = ["void foo() {"]
        for i in range(60):
            func_lines.append(f"  TArray<int> var{i} = arr;")
        func_lines.append("}")

        target_symbols = {"TArray": [("class", 99, 1)]}
        bracket_data = self._make_bracket_data([
            (1, len(func_lines), 1, "function"),
        ])
        refs = track_references_for_file(
            func_lines, 1, target_symbols,
            bracket_data=bracket_data,
        )
        # Should be capped at 50
        assert len(refs) <= 50, f"expected <= 50 refs, got {len(refs)}"

    def test_function_block_tracks_calls(self):
        """Function blocks should track regular identifier references."""
        lines = [
            "void caller() {",    # L1
            "  FVector v;",       # L2 - type usage
            "  foo();",           # L3 - function call
            "}",                  # L4
        ]
        target_symbols = {
            "FVector": [("class", 99, 1)],
            "foo": [("function", 98, 1)],
        }
        bracket_data = self._make_bracket_data([
            (1, 4, 1, "function"),
        ])
        refs = track_references_for_file(
            lines, 1, target_symbols,
            bracket_data=bracket_data,
        )
        ref_names = {r[0] for r in refs}
        assert "FVector" in ref_names
        assert "foo" in ref_names
