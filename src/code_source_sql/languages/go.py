"""Go language configuration."""

from __future__ import annotations

import re

from ..configs import LanguageConfig


def make_go_language() -> LanguageConfig:
    """Go language configuration."""
    return LanguageConfig(
        name="go",
        class_re=re.compile(r"\b(type)\s+(\w+)\s+(?:struct|interface)\b(?:\s*(?://.*)?$)?"),
        enum_re=re.compile(r"(?!x)x"),  # never-match; Go has no enum keyword
        namespace_re=re.compile(r"(?!x)x"),  # never-match; Go uses package, not namespace blocks
        func_name_re=re.compile(r"func\s+(?:\(\w+\s+\*?\w+\)\s+)?(\w+)\s*\("),
        export_macro_re=re.compile(r"(?!x)x"),
        calling_conv_re=re.compile(r"(?!x)x"),
        attribute_re=re.compile(r"(?!x)x"),
        template_re=re.compile(r"\[[^\]]+\]"),  # Go generics: [T any]
        dtor_re=re.compile(r"(?!x)x"),
        control_flow_re=re.compile(r"\b(if|else|for|range|switch|case|select|go|defer|return)\b"),
        control_flow_names=frozenset({
            "if", "else", "for", "switch", "case", "select", "go", "defer",
            "return", "break", "continue", "fallthrough", "goto", "range",
        }),
        trailing_mods_re=re.compile(r"(?!x)x"),
        access_spec_re=re.compile(r"(?!x)x"),
        macro_like_re=re.compile(r"(?!x)x"),
        define_re=re.compile(r"(?!x)x"),
        extern_c_re=re.compile(r"(?!x)x"),
        operator_re=None,
        uses_braces=True,
        uses_namespaces=False,
        uses_colon_inheritance=False,
        scope_operator=".",
        base_keyword="",  # Go has no super/base; embedded fields accessed directly
        static_call_re=re.compile(r"\b([A-Z][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)\s*\("),
        super_call_re=None,
        type_re=re.compile(r"\b([A-Z][A-Za-z0-9_]*)\b"),  # exported names are PascalCase
        param_type_re=re.compile(r"([A-Z][A-Za-z0-9_]*(?:<[^>]*>)?)\s+"),
        basic_skip_types=frozenset({
            "int", "int8", "int16", "int32", "int64",
            "uint", "uint8", "uint16", "uint32", "uint64",
            "float32", "float64", "string", "bool", "byte", "rune",
            "error", "complex64", "complex128", "uintptr",
        }),
        block_keyword_re=re.compile(r"\b(?:func|type|struct|interface|map|chan)\b"),
        lambda_re=re.compile(r"func\s*\("),  # Go anonymous functions
        namespace_sig_re=None,
        init_list_re=None,
        access_spec_names=frozenset(),
        view_structural_kws=("type ", "func "),
        view_modifier_kws=("go ", "defer "),
        local_var_modifiers="var|const",
        verbatim_string_prefix=None,
        raw_string_char=None,  # Go uses backtick for raw strings
        range_for_re=re.compile(
            r"for\s+(?:\w+(?:,\s*\w+)?\s*:=\s+)?range\s+(\w+)"
        ),
        # Comment syntax
        line_comment="//",
        block_comment_pair=("/*", "*/"),
        # String syntax
        string_delimiters=frozenset({'"'}),
        string_escape_char="\\",
        triple_quote_strings=(),
        # Block style
        uses_indent_blocks=False,
        # Preprocessor
        preprocessor_prefix="",
        has_preprocessor_macros=False,
        # Statement / block close
        statement_terminator="",  # Go has no semicolons
        block_close_suffix="}",
        summary_comment_prefix="//",
        # Config-driven control flow
        control_flow_patterns=(
            ("for", re.compile(r"^\s*for\s+(.{1,80})\s*\{?\s*$")),
            ("if", re.compile(r"^\s*if\s+(.{1,80})\s*\{?\s*$")),
            ("switch", re.compile(r"^\s*switch\s+(.{1,40})\s*\{?\s*$")),
            ("select", re.compile(r"^\s*select\s*\{?\s*$")),
        ),
        return_re=re.compile(r"^\s*return\s+(.{1,60})"),  # no semicolons in Go
        # Extra syntax hints
        type_indicator_chars="",
        define_line_re=None,
        has_template_strings=False,
        raw_string_style="cpp",
    )
