"""C language configuration."""

from __future__ import annotations

import re

from ..configs import LanguageConfig

_NEVER_MATCH = re.compile(r"(?!x)x")


def make_c_language() -> LanguageConfig:
    """C language configuration — similar to C++ but no templates, namespaces,
    classes, lambdas, or export macros."""
    return LanguageConfig(
        name="c",
        # C has struct/union (no class); enum same as C++
        class_re=re.compile(
            r"(?:^|\s)(struct|union)\s+"
            r"(?:(?:[A-Z][A-Z0-9_]*_API|[A-Z][A-Z0-9_]*(?:\s*\([^)]*\))?)\s+)*"
            r"(\w+)"
            r"\s*",
        ),
        enum_re=re.compile(r"\benum\s+(\w+)"),
        # No namespaces in C
        namespace_re=_NEVER_MATCH,
        func_name_re=re.compile(r"(\w+)\s*\([^)]*\)\s*$"),
        # No export macros in plain C
        export_macro_re=_NEVER_MATCH,
        calling_conv_re=re.compile(
            r"\b(?:__cdecl|__stdcall|__fastcall|__thiscall|__vectorcall|WINAPI|CALLBACK|"
            r"STDMETHODCALLTYPE|FORCEINLINE|FORCENOINLINE|FORCEINLINE_DEBUGGABLE|inline)\b"
        ),
        attribute_re=re.compile(
            r"\b(?:__declspec|__attribute__|alignas)\s*\([^)]*(?:\)[^)]*)?\)|\[\[[^\]]*\]\]"
        ),
        # No templates in C
        template_re=_NEVER_MATCH,
        # No destructors in C
        dtor_re=_NEVER_MATCH,
        control_flow_re=re.compile(r"\b(if|else\s+if|else|while|for|do|switch|catch|try)\b"),
        control_flow_names=frozenset({
            "if", "else", "while", "for", "do", "switch", "catch", "try",
            "return", "delete", "goto", "break", "continue", "throw",
        }),
        trailing_mods_re=re.compile(
            r"\s*(?:const|constexpr|inline|static)\s*[;{]*\s*$"
        ),
        access_spec_re=re.compile(r"^(?!x)x"),  # C has no access specifiers
        macro_like_re=re.compile(r"^[A-Z][A-Z0-9_]*\s*(?:\([^{};]*\))?\s*$"),
        define_re=re.compile(r"#\s*define\s+"),
        extern_c_re=re.compile(r'\bextern\s+"C"'),
        operator_re=None,
        uses_braces=True,
        uses_namespaces=False,
        uses_colon_inheritance=False,
        # Edge extraction
        scope_operator="::",
        base_keyword="Super",
        static_call_re=re.compile(r"\b([A-Z][A-Za-z0-9_]+)::([A-Za-z_][A-Za-z0-9_]*)\s*\("),
        super_call_re=None,
        type_re=re.compile(r"\b([A-Z][A-Za-z0-9_]+)\b"),
        param_type_re=re.compile(
            r"(?:const\s+)?([A-Z][A-Za-z0-9_]+)\s*(?:\*+|&)?\s+\w+"
        ),
        basic_skip_types=frozenset({
            "int8", "int16", "int32", "int64",
            "uint8", "uint16", "uint32", "uint64",
            "float", "double", "bool", "void", "int", "char", "long", "short",
            "unsigned", "size_t",
        }),
        # Block classification helpers
        block_keyword_re=re.compile(r"\b(?:struct|enum|union)\b"),
        # No lambdas in C
        lambda_re=None,
        # No namespaces in C
        namespace_sig_re=_NEVER_MATCH,
        init_list_re=None,
        # View / summary helpers
        access_spec_names=frozenset(),
        view_structural_kws=("struct ", "enum ", "union "),
        view_modifier_kws=("static ", "FORCEINLINE"),
        local_var_modifiers="const|static|volatile",
        # Bracket scanner hints
        verbatim_string_prefix=None,
        raw_string_char="R",
        # Function body summary hints — C has no range-based for
        range_for_re=None,
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
        preprocessor_prefix="#",
        has_preprocessor_macros=True,
        # Statement / block close
        statement_terminator=";",
        block_close_suffix="};",
        summary_comment_prefix="//",
        # Config-driven control flow
        control_flow_patterns=(
            ("for", re.compile(r"^\s*for\s*\((.{1,80})\)\s*\{?\s*$")),
            ("while", re.compile(r"^\s*while\s*\((.{1,80})\)\s*\{?\s*$")),
            ("if", re.compile(r"^\s*(?:else\s+)?if\s*\((.{1,80})\)\s*\{?\s*$")),
            ("switch", re.compile(r"^\s*switch\s*\((.{1,40})\)\s*\{?\s*$")),
        ),
        return_re=re.compile(r"^\s*return\s+(.{1,60});"),
        # Extra syntax hints
        type_indicator_chars="*&",
        define_line_re=re.compile(r"#\s*define\s+(\w+)(\([^)]*\))?\s*(.*)"),
        has_template_strings=False,
        raw_string_style="cpp",
    )
