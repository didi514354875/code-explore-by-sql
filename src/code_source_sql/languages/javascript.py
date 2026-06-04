"""JavaScript / TypeScript language configuration."""

from __future__ import annotations

import re

from ..configs import LanguageConfig

_NEVER_MATCH = re.compile(r"(?!x)x")


def make_javascript_language() -> LanguageConfig:
    """JavaScript language configuration."""
    return LanguageConfig(
        name="javascript",
        class_re=re.compile(
            r"(?:^|\s)(?:export\s+)?(?:default\s+)?(?:abstract\s+)?(class)\s+(\w+)"
            r"(?:\s+extends\s+(\w+))?"
        ),
        enum_re=_NEVER_MATCH,
        namespace_re=_NEVER_MATCH,
        func_name_re=re.compile(
            r"(?:async\s+)?(?:function\s+)?"
            r"(?:get\s+|set\s+|static\s+|async\s+)*"
            r"(\w+)\s*\("
        ),
        export_macro_re=_NEVER_MATCH,
        calling_conv_re=_NEVER_MATCH,
        attribute_re=_NEVER_MATCH,
        template_re=_NEVER_MATCH,
        dtor_re=_NEVER_MATCH,
        control_flow_re=re.compile(
            r"\b(if|else\s+if|else|while|for|do|switch|catch|try|finally)\b"
        ),
        control_flow_names=frozenset({
            "if", "else", "while", "for", "do", "switch", "catch", "try", "finally",
            "return", "break", "continue", "throw", "yield", "await", "new",
            "delete", "typeof", "instanceof",
        }),
        trailing_mods_re=_NEVER_MATCH,
        access_spec_re=_NEVER_MATCH,
        macro_like_re=_NEVER_MATCH,
        define_re=_NEVER_MATCH,
        extern_c_re=_NEVER_MATCH,
        operator_re=None,
        uses_braces=True,
        uses_namespaces=False,
        uses_colon_inheritance=True,
        scope_operator=".",
        base_keyword="super",
        static_call_re=re.compile(
            r"\b([A-Z][A-Za-z0-9_]+)\.([A-Za-z_][A-Za-z0-9_]*)\s*\("
        ),
        super_call_re=re.compile(
            r"\bsuper\.([A-Za-z_][A-Za-z0-9_]*)\s*\("
        ),
        type_re=re.compile(r"\b([A-Z][A-Za-z0-9_]+)\b"),
        param_type_re=_NEVER_MATCH,
        basic_skip_types=frozenset({
            "Object", "Array", "String", "Number", "Boolean", "Symbol", "BigInt",
            "Promise", "Map", "Set", "WeakMap", "WeakSet", "Date", "RegExp",
            "Error", "Math", "JSON", "console", "undefined", "null", "NaN",
            "Infinity",
        }),
        block_keyword_re=re.compile(r"\b(?:class|function)\b"),
        lambda_re=re.compile(r"=>"),
        namespace_sig_re=None,
        init_list_re=None,
        access_spec_names=frozenset(),
        view_structural_kws=("class ", "function "),
        view_modifier_kws=("async ", "static ", "get ", "set "),
        local_var_modifiers="const|let|var",
        verbatim_string_prefix=None,
        raw_string_char=None,
        range_for_re=re.compile(
            r"for\s*\(\s*(?:const|let|var)?\s*(\w+)\s+of\s+(\w+)"
        ),
        # Comment syntax
        line_comment="//",
        block_comment_pair=("/*", "*/"),
        # String syntax
        string_delimiters=frozenset({'"', "'"}),
        string_escape_char="\\",
        triple_quote_strings=(),
        # Block style
        uses_indent_blocks=False,
        # Preprocessor
        preprocessor_prefix="",
        has_preprocessor_macros=False,
        # Statement / block close
        statement_terminator=";",
        block_close_suffix="}",
        summary_comment_prefix="//",
        # Config-driven control flow
        control_flow_patterns=(
            ("for", re.compile(r"^\s*for\s+\((.{1,80})\)\s*\{?\s*$")),
            ("while", re.compile(r"^\s*while\s+\((.{1,80})\)\s*\{?\s*$")),
            ("if", re.compile(r"^\s*(?:else\s+)?if\s+\((.{1,80})\)\s*\{?\s*$")),
            ("switch", re.compile(r"^\s*switch\s+\((.{1,40})\)\s*\{?\s*$")),
        ),
        return_re=re.compile(r"^\s*return\s+(.{1,60});"),
        # Extra syntax hints
        type_indicator_chars="",
        define_line_re=None,
        has_template_strings=True,
        raw_string_style="cpp",
    )


def make_typescript_language() -> LanguageConfig:
    """TypeScript language configuration."""
    return LanguageConfig(
        name="typescript",
        class_re=re.compile(
            r"(?:^|\s)(?:export\s+)?(?:default\s+)?(?:abstract\s+)?(class)\s+(\w+)"
            r"(?:\s+extends\s+(\w+))?"
        ),
        enum_re=re.compile(r"\benum\s+(\w+)"),
        namespace_re=re.compile(r"\bnamespace\s+(\w+)"),
        func_name_re=re.compile(
            r"(?:async\s+)?(?:function\s+)?"
            r"(?:get\s+|set\s+|static\s+|async\s+|abstract\s+)*"
            r"(\w+)\s*[(<]"
        ),
        export_macro_re=_NEVER_MATCH,
        calling_conv_re=_NEVER_MATCH,
        attribute_re=re.compile(r"@\w+(?:\.\w+)*(?:\([^)]*\))?"),
        template_re=re.compile(r"<[^<>]*>"),
        dtor_re=_NEVER_MATCH,
        control_flow_re=re.compile(
            r"\b(if|else\s+if|else|while|for|do|switch|catch|try|finally)\b"
        ),
        control_flow_names=frozenset({
            "if", "else", "while", "for", "do", "switch", "catch", "try", "finally",
            "return", "break", "continue", "throw", "yield", "await", "new",
            "delete", "typeof", "instanceof",
        }),
        trailing_mods_re=_NEVER_MATCH,
        access_spec_re=_NEVER_MATCH,
        macro_like_re=_NEVER_MATCH,
        define_re=_NEVER_MATCH,
        extern_c_re=_NEVER_MATCH,
        operator_re=None,
        uses_braces=True,
        uses_namespaces=False,
        uses_colon_inheritance=True,
        scope_operator=".",
        base_keyword="super",
        static_call_re=re.compile(
            r"\b([A-Z][A-Za-z0-9_]+)\.([A-Za-z_][A-Za-z0-9_]*)\s*\("
        ),
        super_call_re=re.compile(
            r"\bsuper\.([A-Za-z_][A-Za-z0-9_]*)\s*\("
        ),
        type_re=re.compile(r"\b([A-Z][A-Za-z0-9_]+)\b"),
        param_type_re=re.compile(r"(\w+)\s*:\s*([A-Z][A-Za-z0-9_]+)"),
        basic_skip_types=frozenset({
            "Object", "Array", "String", "Number", "Boolean", "Symbol", "BigInt",
            "Promise", "Map", "Set", "WeakMap", "WeakSet", "Date", "RegExp",
            "Error", "Math", "JSON", "console", "undefined", "null", "NaN",
            "Infinity",
            # TypeScript-specific
            "string", "number", "boolean", "void", "never", "unknown", "any",
            "object", "symbol", "bigint",
            "Record", "Partial", "Required", "Readonly", "Pick", "Omit",
            "Exclude", "Extract",
        }),
        block_keyword_re=re.compile(
            r"\b(?:class|function|interface|enum|namespace|type)\b"
        ),
        lambda_re=re.compile(r"=>"),
        func_sig_end_re=re.compile(r"\)\s*(?::\s*\w[\w<>\[\]| ]*)?\s*\{?\s*$"),
        namespace_sig_re=None,
        init_list_re=None,
        access_spec_names=frozenset(),
        view_structural_kws=(
            "class ", "function ", "interface ", "enum ", "namespace ", "type ",
        ),
        view_modifier_kws=("async ", "static ", "get ", "set "),
        local_var_modifiers="const|let|var",
        verbatim_string_prefix=None,
        raw_string_char=None,
        range_for_re=re.compile(
            r"for\s*\(\s*(?:const|let|var)?\s*(\w+)\s+of\s+(\w+)"
        ),
        # Comment syntax
        line_comment="//",
        block_comment_pair=("/*", "*/"),
        # String syntax
        string_delimiters=frozenset({'"', "'"}),
        string_escape_char="\\",
        triple_quote_strings=(),
        # Block style
        uses_indent_blocks=False,
        # Preprocessor
        preprocessor_prefix="",
        has_preprocessor_macros=False,
        # Statement / block close
        statement_terminator=";",
        block_close_suffix="}",
        summary_comment_prefix="//",
        # Config-driven control flow
        control_flow_patterns=(
            ("for", re.compile(r"^\s*for\s+\((.{1,80})\)\s*\{?\s*$")),
            ("while", re.compile(r"^\s*while\s+\((.{1,80})\)\s*\{?\s*$")),
            ("if", re.compile(r"^\s*(?:else\s+)?if\s+\((.{1,80})\)\s*\{?\s*$")),
            ("switch", re.compile(r"^\s*switch\s+\((.{1,40})\)\s*\{?\s*$")),
        ),
        return_re=re.compile(r"^\s*return\s+(.{1,60});"),
        # Extra syntax hints
        type_indicator_chars="",
        define_line_re=None,
        has_template_strings=True,
        raw_string_style="cpp",
    )
